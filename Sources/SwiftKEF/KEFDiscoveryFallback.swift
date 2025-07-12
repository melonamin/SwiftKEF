#if !canImport(Network)
import Foundation
import AsyncHTTPClient
#if os(Linux)
import Glibc
#else
import Darwin
#endif

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

/// Fallback discovery implementation for non-Apple platforms
/// Uses IP range scanning as mDNS is not available
public actor KEFDiscovery {
    private let httpClient: HTTPClient
    
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    /// Discover KEF speakers on the local network by scanning common IP ranges
    /// - Parameter timeout: Discovery timeout in seconds (default: 5.0)
    /// - Returns: Array of discovered speakers
    public func discover(timeout: TimeInterval = 5.0) async throws -> [DiscoveredSpeaker] {
        // Get local IP to determine subnet
        let subnet = try await getLocalSubnet()
        
        // Scan the subnet
        return try await scanSubnet(subnet: subnet, timeout: timeout)
    }
    
    /// Create an async stream that yields discovered speakers in real-time
    /// Note: On non-Apple platforms, this performs a single scan and yields results
    /// - Returns: AsyncStream of discovered speakers
    public func discoverStream() -> AsyncStream<DiscoveredSpeaker> {
        AsyncStream { continuation in
            Task {
                do {
                    let speakers = try await discover()
                    for speaker in speakers {
                        continuation.yield(speaker)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }
    
    /// Get the local subnet (e.g., "192.168.1" from "192.168.1.100")
    private func getLocalSubnet() async throws -> String {
        // Try to determine local IP by connecting to a public DNS
        // This is a common technique to find the local IP
        let tempSocket = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        if tempSocket < 0 {
            // Fallback to common subnet
            return "192.168.1"
        }
        defer { close(tempSocket) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 53  // DNS port
        addr.sin_addr.s_addr = inet_addr("8.8.8.8")  // Google DNS
        
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(tempSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if result < 0 {
            return "192.168.1"  // Fallback
        }
        
        var localAddr = sockaddr_in()
        var localAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let getResult = withUnsafeMutablePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getsockname(tempSocket, sockaddrPtr, &localAddrLen)
            }
        }
        
        if getResult < 0 {
            return "192.168.1"  // Fallback
        }
        
        // Convert to string
        let ipString = String(cString: inet_ntoa(localAddr.sin_addr))
        let components = ipString.split(separator: ".")
        if components.count >= 3 {
            return "\(components[0]).\(components[1]).\(components[2])"
        }
        
        return "192.168.1"  // Fallback
    }
    
    /// Scan a subnet for KEF speakers
    private func scanSubnet(subnet: String, timeout: TimeInterval) async throws -> [DiscoveredSpeaker] {
        var speakers: [DiscoveredSpeaker] = []
        
        // Use task group to scan in parallel
        try await withThrowingTaskGroup(of: DiscoveredSpeaker?.self) { group in
            // Scan common IP range (1-254)
            for i in 1...254 {
                let ip = "\(subnet).\(i)"
                
                group.addTask {
                    return await self.probeSpeaker(ip: ip)
                }
            }
            
            // Set a timeout for the entire scan
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            
            // Collect results
            for try await speaker in group {
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
            
            // Use a short timeout for probing
            let name = try await withTimeout(seconds: 0.5) {
                try await speaker.getSpeakerName()
            }
            
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
    
    /// Cancel any ongoing discovery
    public func cancel() {
        // No-op for fallback implementation
    }
}

// Helper function for timeout
private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw KEFError.speakerNotResponding
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
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

#endif // !canImport(Network)