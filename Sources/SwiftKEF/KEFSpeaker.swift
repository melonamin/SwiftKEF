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

    // MARK: - HTTP Request Helper

    private func makeRequest(
        endpoint: String, params: [String: String], method: HTTPMethod = .GET,
        jsonBody: [String: Any]? = nil
    ) async throws -> String {
        var urlComponents = URLComponents(string: "http://\(host)\(endpoint)")!

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
            request.body = .bytes(ByteBuffer(data: jsonData))
        }

        do {
            let response = try await httpClient.execute(request, timeout: .seconds(10))

            guard response.status == .ok else {
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
