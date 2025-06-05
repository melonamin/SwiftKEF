#if canImport(Network)
import Foundation
import Network
import AsyncHTTPClient

/// Represents a discovered KEF speaker on the network
public struct DiscoveredSpeaker: Sendable, Equatable {
    public let name: String
    public let host: String
    public let port: Int
    public let model: String?
    public let macAddress: String?
    
    public init(name: String, host: String, port: Int = 80, model: String? = nil, macAddress: String? = nil) {
        self.name = name
        self.host = host
        self.port = port
        self.model = model
        self.macAddress = macAddress
    }
}

/// KEF Speaker Discovery using mDNS/Bonjour
public actor KEFDiscovery {
    private let httpClient: HTTPClient
    
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    /// Discover KEF speakers on the local network
    /// - Parameter timeout: Discovery timeout in seconds (default: 5.0)
    /// - Returns: Array of discovered speakers
    public func discover(timeout: TimeInterval = 5.0) async throws -> [DiscoveredSpeaker] {
        // Try mDNS discovery first
        let mdnsResults = try await discoverViaMDNS(timeout: timeout)
        if !mdnsResults.isEmpty {
            return mdnsResults
        }
        
        // Fall back to IP scanning if mDNS fails
        return try await discoverViaIPScan(timeout: timeout)
    }
    
    /// Discover speakers using IP range scanning
    private func discoverViaIPScan(timeout: TimeInterval) async throws -> [DiscoveredSpeaker] {
        // Get local subnet dynamically
        guard let subnet = getLocalSubnet() else {
            throw KEFError.networkError("Unable to determine local subnet")
        }
        
        // Scan the subnet
        return try await scanSubnet(subnet: subnet, timeout: timeout)
    }
    
    /// Get the local subnet dynamically from network interfaces
    private func getLocalSubnet() -> String? {
        var addresses = [String]()
        
        // Get list of all interfaces on the local machine
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(firstAddr) }
        
        // Iterate through interfaces
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            
            // Check for IPv4 interface
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                // Check if interface is up and not loopback
                let flags = Int32(interface.ifa_flags)
                if (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 {
                    // Convert interface address to a human readable string
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let address = hostname.withUnsafeBufferPointer { ptr in
                        String(cString: ptr.baseAddress!)
                    }
                    
                    // Extract subnet (first 3 octets)
                    let components = address.split(separator: ".")
                    if components.count == 4 {
                        let subnet = components[0...2].joined(separator: ".")
                        // Prefer private network ranges
                        if address.hasPrefix("192.168.") || address.hasPrefix("10.") || address.hasPrefix("172.") {
                            return subnet
                        }
                        addresses.append(subnet)
                    }
                }
            }
        }
        
        // Return first found subnet if no private network found
        return addresses.first
    }
    
    /// Scan a subnet for KEF speakers
    private func scanSubnet(subnet: String, timeout: TimeInterval) async throws -> [DiscoveredSpeaker] {
        var speakers: [DiscoveredSpeaker] = []
        
        // Use task group to scan in parallel
        await withTaskGroup(of: DiscoveredSpeaker?.self) { group in
            // Scan common IP range (1-254)
            for i in 1...254 {
                let ip = "\(subnet).\(i)"
                
                group.addTask { [weak self] in
                    guard let self = self else { return nil }
                    return await self.probeSpeaker(ip: ip)
                }
            }
            
            // Set a timeout for the entire scan
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            
            // Collect results
            for await speaker in group {
                if let speaker = speaker {
                    speakers.append(speaker)
                }
            }
        }
        
        return speakers
    }
    
    /// Probe an IP address to check if it's a KEF speaker
    private func probeSpeaker(ip: String) async -> DiscoveredSpeaker? {
        do {
            let speaker = KEFSpeaker(host: ip, httpClient: httpClient)
            
            // Try to get speaker name with a short timeout
            let name = try await speaker.getSpeakerName()
            
            // If we got a name, it's a KEF speaker
            let macAddress = try? await speaker.getMacAddress()
            let firmware = try? await speaker.getFirmwareVersion()
            
            return DiscoveredSpeaker(
                name: name,
                host: ip,
                port: 80,
                model: firmware?.model,
                macAddress: macAddress
            )
        } catch {
            // Not a KEF speaker or not responding
            return nil
        }
    }
    
    /// Discover KEF speakers via mDNS by looking for AirPlay services
    private func discoverViaMDNS(timeout: TimeInterval) async throws -> [DiscoveredSpeaker] {
        // Use actor-safe discovery manager
        let discoveryManager = MDNSDiscoveryManager()
        
        // Start discovery
        return try await discoveryManager.discover(timeout: timeout) { name, type, domain in
            // Resolve and test each AirPlay service
            await self.resolveAirPlayService(name: name, type: type, domain: domain)
        }
    }
    
    /// Resolve an AirPlay service to check if it's a KEF speaker
    private func resolveAirPlayService(name: String, type: String, domain: String) async -> DiscoveredSpeaker? {
        // Try to resolve to IP using NWConnection
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        
        // Use simple connection test
        let connection = NWConnection(to: endpoint, using: .tcp)
        let resolver = ServiceResolver()
        
        guard let ipAddress = await resolver.resolveToIP(connection: connection) else {
            return nil
        }
        
        // Test if this IP is a KEF speaker
        return await probeSpeaker(ip: ipAddress)
    }
    
    /// Create an async stream that yields discovered speakers in real-time
    /// - Returns: AsyncStream of discovered speakers
    public func discoverStream() -> AsyncStream<DiscoveredSpeaker> {
        AsyncStream { continuation in
            Task {
                do {
                    // Use IP scanning for reliability
                    let speakers = try await discoverViaIPScan(timeout: 10.0)
                    for speaker in speakers {
                        continuation.yield(speaker)
                    }
                } catch {
                    // Ignore errors and just finish
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Convenience Extensions

extension KEFSpeaker {
    /// Discover KEF speakers on the local network
    /// - Parameters:
    ///   - httpClient: HTTP client to use for discovery
    ///   - timeout: Discovery timeout in seconds
    /// - Returns: Array of discovered speakers
    public static func discover(
        httpClient: HTTPClient,
        timeout: TimeInterval = 5.0
    ) async throws -> [DiscoveredSpeaker] {
        let discovery = KEFDiscovery(httpClient: httpClient)
        return try await discovery.discover(timeout: timeout)
    }
    
    /// Create an async stream that yields discovered speakers in real-time
    /// - Parameter httpClient: HTTP client to use for discovery
    /// - Returns: AsyncStream of discovered speakers
    public static func discoverStream(
        httpClient: HTTPClient
    ) -> AsyncStream<DiscoveredSpeaker> {
        AsyncStream { continuation in
            Task {
                let discovery = KEFDiscovery(httpClient: httpClient)
                let stream = await discovery.discoverStream()
                for await speaker in stream {
                    continuation.yield(speaker)
                }
                continuation.finish()
            }
        }
    }
    
    /// Create a KEFSpeaker instance from a discovered speaker
    /// - Parameters:
    ///   - discovered: The discovered speaker info
    ///   - httpClient: HTTP client to use
    /// - Returns: Configured KEFSpeaker instance
    public static func from(
        discovered: DiscoveredSpeaker,
        httpClient: HTTPClient
    ) -> KEFSpeaker {
        return KEFSpeaker(
            host: discovered.host,
            port: discovered.port,
            httpClient: httpClient
        )
    }
}

// MARK: - mDNS Discovery Helpers

/// Thread-safe mDNS discovery manager
private final class MDNSDiscoveryManager {
    func discover(timeout: TimeInterval, resolver: @escaping @Sendable (String, String, String) async -> DiscoveredSpeaker?) async throws -> [DiscoveredSpeaker] {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.swiftkef.mdns")
            let state = DiscoveryState()
            
            // Look for AirPlay services
            let parameters = NWParameters()
            parameters.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: "_airplay._tcp", domain: "local."), using: parameters)
            
            // Set up timeout
            queue.asyncAfter(deadline: .now() + timeout) {
                state.complete { speakers in
                    browser.cancel()
                    continuation.resume(returning: speakers)
                }
            }
            
            browser.browseResultsChangedHandler = { results, _ in
                // Process results
                Task {
                    var newSpeakers: [DiscoveredSpeaker] = []
                    
                    for result in results {
                        if case .service(let name, let type, let domain, _) = result.endpoint {
                            if let speaker = await resolver(name, type, domain) {
                                newSpeakers.append(speaker)
                            }
                        }
                    }
                    
                    // Update state with new speakers
                    if !newSpeakers.isEmpty {
                        state.addSpeakers(newSpeakers)
                    }
                }
            }
            
            browser.stateUpdateHandler = { browserState in
                switch browserState {
                case .failed(let error):
                    state.completeWithError { 
                        browser.cancel()
                        continuation.resume(throwing: KEFError.networkError("mDNS discovery failed: \(error)"))
                    }
                default:
                    break
                }
            }
            
            browser.start(queue: queue)
        }
    }
}

/// Thread-safe discovery state
private final class DiscoveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var speakers: [DiscoveredSpeaker] = []
    private var hasCompleted = false
    
    func addSpeakers(_ newSpeakers: [DiscoveredSpeaker]) {
        lock.lock()
        defer { lock.unlock() }
        
        if !hasCompleted {
            speakers.append(contentsOf: newSpeakers)
        }
    }
    
    func complete(handler: ([DiscoveredSpeaker]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        if !hasCompleted {
            hasCompleted = true
            handler(speakers)
        }
    }
    
    func completeWithError(handler: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        if !hasCompleted {
            hasCompleted = true
            handler()
        }
    }
}

/// Service resolver for converting mDNS services to IP addresses
private final class ServiceResolver {
    func resolveToIP(connection: NWConnection) async -> String? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.swiftkef.resolver")
            let state = ResolverState()
            
            // Timeout
            queue.asyncAfter(deadline: .now() + 2.0) {
                state.complete {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
            
            connection.stateUpdateHandler = { connectionState in
                switch connectionState {
                case .ready:
                    // Extract IP from connection
                    if let endpoint = connection.currentPath?.remoteEndpoint,
                       case .hostPort(let host, _) = endpoint {
                        let ipAddress: String
                        switch host {
                        case .ipv4(let addr):
                            // Convert IPv4Address to string properly
                            ipAddress = addr.debugDescription
                        case .ipv6(let addr):
                            // Convert IPv6Address to string properly
                            ipAddress = addr.debugDescription
                        case .name(let hostname, _):
                            ipAddress = hostname
                        @unknown default:
                            ipAddress = ""
                        }
                        
                        if !ipAddress.isEmpty {
                            state.complete {
                                connection.cancel()
                                continuation.resume(returning: ipAddress)
                            }
                        } else {
                            state.complete {
                                connection.cancel()
                                continuation.resume(returning: nil)
                            }
                        }
                    } else {
                        state.complete {
                            connection.cancel()
                            continuation.resume(returning: nil)
                        }
                    }
                    
                case .failed:
                    state.complete {
                        continuation.resume(returning: nil)
                    }
                    
                default:
                    break
                }
            }
            
            connection.start(queue: queue)
        }
    }
}

/// Thread-safe resolver state
private final class ResolverState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false
    
    func complete(handler: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        if !hasCompleted {
            hasCompleted = true
            handler()
        }
    }
}

#endif // canImport(Network)