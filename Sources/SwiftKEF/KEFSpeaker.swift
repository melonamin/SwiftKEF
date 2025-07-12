import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

/// Represents the available input sources for KEF speakers
public enum KEFSource: String, CaseIterable, Sendable {
    case wifi = "wifi"
    case bluetooth = "bluetooth"
    case tv = "tv"
    case optic = "optic"
    case coaxial = "coaxial"
    case analog = "analog"
    case usb = "usb"
}

/// Represents the power status of a KEF speaker
public enum KEFSpeakerStatus: String, Sendable {
    case standby = "standby"
    case powerOn = "powerOn"
}

/// Contains information about the currently playing track
public struct SongInfo: Sendable, Equatable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let coverURL: String?

    public init(
        title: String? = nil, artist: String? = nil, album: String? = nil, coverURL: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.coverURL = coverURL
    }
}

/// Represents the playback state of the speaker
public enum PlaybackState: String, Sendable {
    case playing = "playing"
    case paused = "paused"
    case stopped = "stopped"
}

/// Contains real-time status updates from the speaker
public struct KEFSpeakerEvent: Sendable {
    public let source: KEFSource?
    public let volume: Int?
    public let songInfo: SongInfo?
    public let songPosition: Int64?  // Current playback position in milliseconds
    public let songDuration: Int?    // Total duration in milliseconds
    public let playbackState: PlaybackState?
    public let speakerStatus: KEFSpeakerStatus?
    public let deviceName: String?
    public let isMuted: Bool?
    
    public init(
        source: KEFSource? = nil,
        volume: Int? = nil,
        songInfo: SongInfo? = nil,
        songPosition: Int64? = nil,
        songDuration: Int? = nil,
        playbackState: PlaybackState? = nil,
        speakerStatus: KEFSpeakerStatus? = nil,
        deviceName: String? = nil,
        isMuted: Bool? = nil
    ) {
        self.source = source
        self.volume = volume
        self.songInfo = songInfo
        self.songPosition = songPosition
        self.songDuration = songDuration
        self.playbackState = playbackState
        self.speakerStatus = speakerStatus
        self.deviceName = deviceName
        self.isMuted = isMuted
    }
}

/// Errors that can occur when communicating with KEF speakers
public enum KEFError: Error, LocalizedError, Equatable {
    case networkError(String)
    case invalidResponse
    case jsonParsingError
    case speakerNotResponding
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from speaker"
        case .jsonParsingError:
            return "Failed to parse JSON response"
        case .speakerNotResponding:
            return "Speaker is not responding"
        case .invalidURL:
            return "Invalid URL"
        }
    }
}

/// A client for controlling KEF wireless speakers
///
/// This class provides an interface to control KEF wireless speakers over the network,
/// including power control, volume adjustment, source selection, and playback control.
///
/// Example usage:
/// ```swift
/// let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
/// let speaker = KEFSpeaker(host: "192.168.1.100", httpClient: httpClient)
///
/// // Get speaker info
/// let name = try await speaker.getSpeakerName()
///
/// // Control volume
/// try await speaker.setVolume(50)
/// let currentVolume = try await speaker.getVolume()
///
/// // Control playback
/// try await speaker.togglePlayPause()
/// ```
public actor KEFSpeaker {
    public let host: String
    public let port: Int
    private let httpClient: HTTPClient
    private var previousVolume: Int = 15
    private var lastPolled: Date?
    private var pollingQueue: String?
    private var previousPollSongStatus: Bool = false

    /// Initialize a new KEF speaker controller
    /// - Parameters:
    ///   - host: The IP address or hostname of the KEF speaker
    ///   - port: The port number (default is 80)
    ///   - httpClient: An instance of AsyncHTTPClient's HTTPClient
    public init(host: String, port: Int = 80, httpClient: HTTPClient) {
        self.host = host
        self.port = port
        self.httpClient = httpClient
    }

    // MARK: - Power Control

    /// Turn the speaker on
    public func powerOn() async throws {
        try await setStatus(.powerOn)
    }

    /// Turn the speaker off (standby mode)
    public func shutdown() async throws {
        // Use "standby" for power control (not a source)
        let payload = """
            {"type":"kefPhysicalSource","kefPhysicalSource":"standby"}
            """

        let params = [
            "path": "settings:/kef/play/physicalSource",
            "roles": "value",
            "value": payload,
        ]

        _ = try await makeRequest(endpoint: "/api/setData", params: params)
    }

    // MARK: - Volume Control

    /// Mute the speaker by setting volume to 0 and remembering the previous volume
    public func mute() async throws {
        let currentVolume = try await getVolume()
        previousVolume = currentVolume
        try await setVolume(0)
    }

    /// Unmute the speaker by restoring the previous volume
    public func unmute() async throws {
        try await setVolume(previousVolume)
    }

    /// Set the speaker volume
    /// - Parameter volume: Volume level from 0 to 100
    public func setVolume(_ volume: Int) async throws {
        let clampedVolume = max(0, min(100, volume))
        let payload = """
            {"type":"i32_","i32_":\(clampedVolume)}
            """

        let params = [
            "path": "player:volume",
            "roles": "value",
            "value": payload,
        ]

        _ = try await makeRequest(endpoint: "/api/setData", params: params)
    }

    /// Get the current volume level
    /// - Returns: Current volume (0-100)
    public func getVolume() async throws -> Int {
        let params = [
            "path": "player:volume",
            "roles": "value",
        ]

        let response = try await makeRequest(endpoint: "/api/getData", params: params)

        guard let data = response.data(using: .utf8) else {
            throw KEFError.jsonParsingError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let firstItem = json.first,
            let volume = firstItem["i32_"] as? Int
        else {
            throw KEFError.jsonParsingError
        }

        return volume
    }

    // MARK: - Source Control

    /// Set the input source
    /// - Parameter source: The desired input source
    public func setSource(_ source: KEFSource) async throws {
        let payload = """
            {"type":"kefPhysicalSource","kefPhysicalSource":"\(source.rawValue)"}
            """

        let params = [
            "path": "settings:/kef/play/physicalSource",
            "roles": "value",
            "value": payload,
        ]

        _ = try await makeRequest(endpoint: "/api/setData", params: params)
    }

    /// Get the current input source
    /// - Returns: The current input source
    public func getSource() async throws -> KEFSource {
        let params = [
            "path": "settings:/kef/play/physicalSource",
            "roles": "value",
        ]

        let response = try await makeRequest(endpoint: "/api/getData", params: params)

        guard let data = response.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let firstItem = json.first,
            let sourceString = firstItem["kefPhysicalSource"] as? String
        else {
            throw KEFError.jsonParsingError
        }

        // Handle special cases where non-source values are returned
        switch sourceString {
        case "powerOn":
            // This happens when speaker is just turned on but not set to any specific source
            return .wifi  // Default to wifi
        case "standby":
            // This shouldn't happen if we're querying an active speaker, but handle gracefully
            throw KEFError.speakerNotResponding
        default:
            guard let source = KEFSource(rawValue: sourceString) else {
                throw KEFError.jsonParsingError
            }
            return source
        }
    }

    // MARK: - Status

    /// Get the current power status of the speaker
    /// - Returns: Current power status
    public func getStatus() async throws -> KEFSpeakerStatus {
        let params = [
            "path": "settings:/kef/host/speakerStatus",
            "roles": "value",
        ]

        let response = try await makeRequest(endpoint: "/api/getData", params: params)

        guard let data = response.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let firstItem = json.first,
            let statusString = firstItem["kefSpeakerStatus"] as? String,
            let status = KEFSpeakerStatus(rawValue: statusString)
        else {
            throw KEFError.jsonParsingError
        }

        return status
    }

    private func setStatus(_ status: KEFSpeakerStatus) async throws {
        // When turning on, we need to send "powerOn" to physicalSource
        // The API uses "powerOn" not the status enum value
        let physicalSourceValue = status == .powerOn ? "powerOn" : status.rawValue

        let payload = """
            {"type":"kefPhysicalSource","kefPhysicalSource":"\(physicalSourceValue)"}
            """

        let params = [
            "path": "settings:/kef/play/physicalSource",
            "roles": "value",
            "value": payload,
        ]

        _ = try await makeRequest(endpoint: "/api/setData", params: params)
    }

    // MARK: - Track Control

    /// Toggle play/pause for the current track
    public func togglePlayPause() async throws {
        try await trackControl(command: "pause")
    }

    /// Skip to the next track
    public func nextTrack() async throws {
        try await trackControl(command: "next")
    }

    /// Go to the previous track
    public func previousTrack() async throws {
        try await trackControl(command: "previous")
    }

    private func trackControl(command: String) async throws {
        let payload = """
            {"control":"\(command)"}
            """

        let params = [
            "path": "player:player/control",
            "roles": "activate",
            "value": payload,
        ]

        _ = try await makeRequest(endpoint: "/api/setData", params: params)
    }

    // MARK: - Song Information

    /// Get information about the currently playing track
    /// - Returns: Song information including title, artist, album, and cover URL
    public func getSongInformation() async throws -> SongInfo {
        let playerData = try await getPlayerData()

        let trackRoles = playerData["trackRoles"] as? [String: Any] ?? [:]
        let mediaData = trackRoles["mediaData"] as? [String: Any] ?? [:]
        let metaData = mediaData["metaData"] as? [String: Any] ?? [:]

        return SongInfo(
            title: trackRoles["title"] as? String,
            artist: metaData["artist"] as? String,
            album: metaData["album"] as? String,
            coverURL: trackRoles["icon"] as? String
        )
    }

    /// Check if the speaker is currently playing
    /// - Returns: true if playing, false otherwise
    public func isPlaying() async throws -> Bool {
        let playerData = try await getPlayerData()
        return playerData["state"] as? String == "playing"
    }
    
    /// Get the current song position in milliseconds
    /// - Returns: Current position in milliseconds, or nil if not playing
    public func getSongPosition() async throws -> Int64? {
        let params = [
            "path": "player:player/data/playTime",
            "roles": "value",
        ]
        
        let response = try await makeRequest(endpoint: "/api/getData", params: params)
        
        guard let data = response.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstItem = json.first,
              let position = firstItem["i64_"] as? Int64
        else {
            return nil
        }
        
        return position
    }
    
    /// Get the current song duration in milliseconds
    /// - Returns: Duration in milliseconds, or nil if not playing
    public func getSongDuration() async throws -> Int? {
        let playerData = try await getPlayerData()
        guard let status = playerData["status"] as? [String: Any],
              let duration = status["duration"] as? Int
        else {
            return nil
        }
        return duration
    }

    private func getPlayerData() async throws -> [String: Any] {
        let params = [
            "path": "player:player/data",
            "roles": "value",
        ]

        let response = try await makeRequest(endpoint: "/api/getData", params: params)

        guard let data = response.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let firstItem = json.first
        else {
            throw KEFError.jsonParsingError
        }

        return firstItem
    }

    // MARK: - Speaker Information

    /// Get the speaker's friendly name
    /// - Returns: The speaker's name
    public func getSpeakerName() async throws -> String {
        let params = [
            "path": "settings:/deviceName",
            "roles": "value",
        ]

        let response = try await makeRequest(endpoint: "/api/getData", params: params)

        guard let data = response.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let firstItem = json.first,
            let name = firstItem["string_"] as? String
        else {
            throw KEFError.jsonParsingError
        }

        return name
    }

    /// Get the speaker's MAC address
    /// - Returns: The MAC address
    public func getMacAddress() async throws -> String {
        let params = [
            "path": "settings:/system/primaryMacAddress",
            "roles": "value",
        ]

        let response = try await makeRequest(endpoint: "/api/getData", params: params)

        guard let data = response.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let firstItem = json.first,
            let mac = firstItem["string_"] as? String
        else {
            throw KEFError.jsonParsingError
        }

        return mac
    }

    /// Get the speaker's firmware information
    /// - Returns: A tuple containing the model and firmware version
    public func getFirmwareVersion() async throws -> (model: String, version: String) {
        let params = [
            "path": "settings:/releasetext",
            "roles": "value",
        ]

        let response = try await makeRequest(endpoint: "/api/getData", params: params)

        guard let data = response.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let firstItem = json.first,
            let releaseText = firstItem["string_"] as? String
        else {
            throw KEFError.jsonParsingError
        }

        let components = releaseText.split(separator: "_")
        guard components.count >= 2 else {
            throw KEFError.jsonParsingError
        }

        return (model: String(components[0]), version: String(components[1]))
    }

    // MARK: - Polling Support
    
    /// Poll the speaker for real-time status updates
    /// - Parameters:
    ///   - timeout: Timeout in seconds (default 10, max 60)
    ///   - pollSongStatus: Include real-time song position updates
    /// - Returns: Speaker event with all changed parameters
    public func pollSpeaker(timeout: Int = 10, pollSongStatus: Bool = false) async throws -> KEFSpeakerEvent {
        let clampedTimeout = max(1, min(60, timeout))
        
        // Check if we need a new polling queue
        let needNewQueue = pollingQueue == nil ||
                          (lastPolled != nil && Date().timeIntervalSince(lastPolled!) > 50) ||
                          pollSongStatus != previousPollSongStatus
        
        if needNewQueue {
            previousPollSongStatus = pollSongStatus
            pollingQueue = try await createPollingQueue(pollSongStatus: pollSongStatus)
            lastPolled = Date()
        }
        
        guard let queueId = pollingQueue else {
            throw KEFError.invalidResponse
        }
        
        // Poll for events
        let params = [
            "queueId": queueId, // No braces - just the plain queue ID
            "timeout": String(clampedTimeout)
        ]
        
        let response = try await makeRequest(
            endpoint: "/api/event/pollQueue",
            params: params,
            timeout: TimeAmount.seconds(Int64(clampedTimeout) + 1)  // Add 1 second buffer
        )
        
        guard let data = response.data(using: .utf8) else {
            throw KEFError.jsonParsingError
        }
        
        // Handle empty response (no events)
        if response.isEmpty || response == "[]" {
            // Empty response is normal when no changes occur during timeout
            return KEFSpeakerEvent() // Return empty event
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw KEFError.jsonParsingError
        }
        
        // Process events into a dictionary
        var events: [String: Any] = [:]
        for item in json {
            guard let path = item["path"] as? String,
                  let itemValue = item["itemValue"] as? [String: Any] else {
                continue
            }
            events[path] = itemValue
        }
        
        // Parse events into KEFSpeakerEvent
        return try parseEvents(events)
    }
    
    /// Create a new polling queue with event subscriptions
    private func createPollingQueue(pollSongStatus: Bool) async throws -> String {
        var subscriptions: [[String: String]] = [
            ["path": "settings:/mediaPlayer/playMode", "type": "itemWithValue"],
            ["path": "player:volume", "type": "itemWithValue"],
            ["path": "settings:/kef/host/speakerStatus", "type": "itemWithValue"],
            ["path": "settings:/kef/play/physicalSource", "type": "itemWithValue"],
            ["path": "player:player/data", "type": "itemWithValue"],
            ["path": "settings:/deviceName", "type": "itemWithValue"],
            ["path": "settings:/mediaPlayer/mute", "type": "itemWithValue"],
            ["path": "settings:/kef/host/maximumVolume", "type": "itemWithValue"],
            ["path": "settings:/kef/host/volumeStep", "type": "itemWithValue"],
            ["path": "settings:/kef/host/volumeLimit", "type": "itemWithValue"],
            ["path": "settings:/kef/host/modelName", "type": "itemWithValue"],
            ["path": "settings:/version", "type": "itemWithValue"],
            ["path": "network:info", "type": "itemWithValue"],
            ["path": "kef:eqProfile", "type": "itemWithValue"]
        ]
        
        if pollSongStatus {
            subscriptions.append(["path": "player:player/data/playTime", "type": "itemWithValue"])
        }
        
        let payload: [String: Any] = [
            "subscribe": subscriptions,
            "unsubscribe": []
        ]
        
        let response = try await makeRequest(
            endpoint: "/api/event/modifyQueue",
            params: [:],
            method: .POST,
            jsonBody: payload
        )
        
        // Extract queue ID from response (removes quotes)
        let trimmed = response.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return trimmed
    }
    
    /// Parse raw events into a structured KEFSpeakerEvent
    private func parseEvents(_ events: [String: Any]) throws -> KEFSpeakerEvent {
        var source: KEFSource?
        var volume: Int?
        var songInfo: SongInfo?
        var songPosition: Int64?
        var songDuration: Int?
        var playbackState: PlaybackState?
        var speakerStatus: KEFSpeakerStatus?
        var deviceName: String?
        var isMuted: Bool?
        
        for (path, value) in events {
            guard let valueDict = value as? [String: Any] else { continue }
            
            switch path {
            case "settings:/kef/play/physicalSource":
                if let sourceStr = valueDict["kefPhysicalSource"] as? String,
                   sourceStr != "standby" && sourceStr != "powerOn" {
                    source = KEFSource(rawValue: sourceStr)
                }
                
            case "player:player/data/playTime":
                songPosition = valueDict["i64_"] as? Int64
                
            case "player:volume":
                volume = valueDict["i32_"] as? Int
                
            case "player:player/data":
                // Parse song info
                if let trackRoles = valueDict["trackRoles"] as? [String: Any] {
                    let mediaData = trackRoles["mediaData"] as? [String: Any] ?? [:]
                    let metaData = mediaData["metaData"] as? [String: Any] ?? [:]
                    
                    songInfo = SongInfo(
                        title: trackRoles["title"] as? String,
                        artist: metaData["artist"] as? String,
                        album: metaData["album"] as? String,
                        coverURL: trackRoles["icon"] as? String
                    )
                }
                
                // Parse duration
                if let status = valueDict["status"] as? [String: Any] {
                    songDuration = status["duration"] as? Int
                }
                
                // Parse playback state
                if let state = valueDict["state"] as? String {
                    playbackState = PlaybackState(rawValue: state)
                }
                
            case "settings:/kef/host/speakerStatus":
                if let statusStr = valueDict["kefSpeakerStatus"] as? String {
                    speakerStatus = KEFSpeakerStatus(rawValue: statusStr)
                }
                
            case "settings:/deviceName":
                deviceName = valueDict["string_"] as? String
                
            case "settings:/mediaPlayer/mute":
                isMuted = valueDict["bool_"] as? Bool
                
            default:
                continue
            }
        }
        
        return KEFSpeakerEvent(
            source: source,
            volume: volume,
            songInfo: songInfo,
            songPosition: songPosition,
            songDuration: songDuration,
            playbackState: playbackState,
            speakerStatus: speakerStatus,
            deviceName: deviceName,
            isMuted: isMuted
        )
    }
    
    /// Start an async stream that continuously polls for speaker events
    /// - Parameters:
    ///   - pollInterval: Time between polls in seconds (default 10)
    ///   - pollSongStatus: Include real-time song position updates
    /// - Returns: AsyncThrowingStream of speaker events
    public func startPolling(pollInterval: Int = 10, pollSongStatus: Bool = false) -> AsyncThrowingStream<KEFSpeakerEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    while !Task.isCancelled {
                        do {
                            let event = try await pollSpeaker(timeout: pollInterval, pollSongStatus: pollSongStatus)
                            continuation.yield(event)
                        } catch {
                            // Only throw if it's a critical error
                            if case KEFError.speakerNotResponding = error {
                                continuation.finish(throwing: error)
                                break
                            }
                            // For other errors, wait a bit and retry
                            try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - HTTP Request Helper

    private func makeRequest(
        endpoint: String, params: [String: String], method: HTTPMethod = .GET,
        jsonBody: [String: Any]? = nil, timeout: TimeAmount = .seconds(10)
    ) async throws -> String {
        guard var urlComponents = URLComponents(string: "http://\(host)\(endpoint)") else {
            throw KEFError.invalidURL
        }

        if method == .GET && !params.isEmpty {
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else {
            throw KEFError.invalidURL
        }

        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = method

        if let jsonBody = jsonBody {
            request.headers.add(name: "Content-Type", value: "application/json")
            let jsonData = try JSONSerialization.data(withJSONObject: jsonBody)
            request.body = HTTPClientRequest.Body.bytes(ByteBuffer(bytes: jsonData))
        }

        do {
            let response = try await httpClient.execute(request, timeout: timeout)

            guard response.status == HTTPResponseStatus.ok else {
                throw KEFError.networkError("HTTP \(response.status.code)")
            }

            var bodyData = Data()
            for try await chunk in response.body {
                bodyData.append(contentsOf: chunk.readableBytesView)
            }

            guard let responseString = String(data: bodyData, encoding: .utf8) else {
                throw KEFError.invalidResponse
            }

            return responseString
        } catch {
            if error is KEFError {
                throw error
            }
            throw KEFError.networkError(error.localizedDescription)
        }
    }
}
