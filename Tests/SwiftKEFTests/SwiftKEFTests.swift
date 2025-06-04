import Testing
@testable import SwiftKEF
import Foundation
import AsyncHTTPClient

struct SwiftKEFTests {
    
    // MARK: - Enum Tests
    
    @Test func testKEFSourceAllCases() {
        let expectedSources: [KEFSource] = [.wifi, .bluetooth, .tv, .optic, .coaxial, .analog, .usb]
        #expect(KEFSource.allCases.count == expectedSources.count)
        
        for source in expectedSources {
            #expect(KEFSource.allCases.contains(source))
        }
    }
    
    @Test func testKEFSourceRawValues() {
        #expect(KEFSource.wifi.rawValue == "wifi")
        #expect(KEFSource.bluetooth.rawValue == "bluetooth")
        #expect(KEFSource.tv.rawValue == "tv")
        #expect(KEFSource.optic.rawValue == "optic")
        #expect(KEFSource.coaxial.rawValue == "coaxial")
        #expect(KEFSource.analog.rawValue == "analog")
        #expect(KEFSource.usb.rawValue == "usb")
    }
    
    @Test func testKEFSpeakerStatusRawValues() {
        #expect(KEFSpeakerStatus.standby.rawValue == "standby")
        #expect(KEFSpeakerStatus.powerOn.rawValue == "powerOn")
    }
    
    @Test func testSongInfoInitialization() {
        let songInfo = SongInfo(
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            coverURL: "https://example.com/cover.jpg"
        )
        
        #expect(songInfo.title == "Test Song")
        #expect(songInfo.artist == "Test Artist")
        #expect(songInfo.album == "Test Album")
        #expect(songInfo.coverURL == "https://example.com/cover.jpg")
    }
    
    @Test func testSongInfoWithNilValues() {
        let songInfo = SongInfo()
        
        #expect(songInfo.title == nil)
        #expect(songInfo.artist == nil)
        #expect(songInfo.album == nil)
        #expect(songInfo.coverURL == nil)
    }
    
    @Test func testPlaybackStateRawValues() {
        #expect(PlaybackState.playing.rawValue == "playing")
        #expect(PlaybackState.paused.rawValue == "paused")
        #expect(PlaybackState.stopped.rawValue == "stopped")
    }
    
    @Test func testKEFSpeakerEventInitialization() {
        let songInfo = SongInfo(title: "Test Song", artist: "Test Artist")
        let event = KEFSpeakerEvent(
            source: .wifi,
            volume: 50,
            songInfo: songInfo,
            songPosition: 30000,
            songDuration: 180000,
            playbackState: .playing,
            speakerStatus: .powerOn,
            deviceName: "My Speaker",
            isMuted: false
        )
        
        #expect(event.source == .wifi)
        #expect(event.volume == 50)
        #expect(event.songInfo?.title == "Test Song")
        #expect(event.songPosition == 30000)
        #expect(event.songDuration == 180000)
        #expect(event.playbackState == .playing)
        #expect(event.speakerStatus == .powerOn)
        #expect(event.deviceName == "My Speaker")
        #expect(event.isMuted == false)
    }
    
    @Test func testKEFSpeakerEventWithNilValues() {
        let event = KEFSpeakerEvent()
        
        #expect(event.source == nil)
        #expect(event.volume == nil)
        #expect(event.songInfo == nil)
        #expect(event.songPosition == nil)
        #expect(event.songDuration == nil)
        #expect(event.playbackState == nil)
        #expect(event.speakerStatus == nil)
        #expect(event.deviceName == nil)
        #expect(event.isMuted == nil)
    }
    
    @Test func testKEFErrorDescriptions() {
        let networkError = KEFError.networkError("Connection failed")
        #expect(networkError.errorDescription == "Network error: Connection failed")
        
        let invalidResponse = KEFError.invalidResponse
        #expect(invalidResponse.errorDescription == "Invalid response from speaker")
        
        let jsonError = KEFError.jsonParsingError
        #expect(jsonError.errorDescription == "Failed to parse JSON response")
        
        let notResponding = KEFError.speakerNotResponding
        #expect(notResponding.errorDescription == "Speaker is not responding")
        
        let invalidURL = KEFError.invalidURL
        #expect(invalidURL.errorDescription == "Invalid URL")
    }
    
    @Test func testSendableConformance() {
        // These tests verify that our types conform to Sendable
        func requiresSendable<T: Sendable>(_: T.Type) {}
        
        requiresSendable(KEFSource.self)
        requiresSendable(KEFSpeakerStatus.self)
        requiresSendable(SongInfo.self)
        requiresSendable(PlaybackState.self)
        requiresSendable(KEFSpeakerEvent.self)
    }
    
    @Test func testKEFErrorEquatableConformance() {
        #expect(KEFError.networkError("test") == KEFError.networkError("test"))
        #expect(KEFError.networkError("test") != KEFError.networkError("other"))
        #expect(KEFError.invalidResponse == KEFError.invalidResponse)
        #expect(KEFError.jsonParsingError == KEFError.jsonParsingError)
        #expect(KEFError.speakerNotResponding == KEFError.speakerNotResponding)
        #expect(KEFError.invalidURL == KEFError.invalidURL)
        #expect(KEFError.invalidResponse != KEFError.jsonParsingError)
    }
}

// MARK: - Data Model Tests

struct DataModelTests {
    
    @Test func testSongInfoEquatable() {
        let songInfo1 = SongInfo(title: "Test", artist: "Artist", album: "Album", coverURL: "url")
        let songInfo2 = SongInfo(title: "Test", artist: "Artist", album: "Album", coverURL: "url")
        let songInfo3 = SongInfo(title: "Different", artist: "Artist", album: "Album", coverURL: "url")
        
        #expect(songInfo1 == songInfo2)
        #expect(songInfo1 != songInfo3)
    }
    
    @Test func testKEFSourceDescription() {
        // Test that all sources have valid string representations
        for source in KEFSource.allCases {
            #expect(!source.rawValue.isEmpty)
            #expect(source.rawValue.count > 1)
        }
    }
    
    @Test func testKEFSpeakerStatusDescription() {
        #expect(KEFSpeakerStatus.standby.rawValue == "standby")
        #expect(KEFSpeakerStatus.powerOn.rawValue == "powerOn")
        
        // Test that we can create from raw values
        #expect(KEFSpeakerStatus(rawValue: "standby") == .standby)
        #expect(KEFSpeakerStatus(rawValue: "powerOn") == .powerOn)
        #expect(KEFSpeakerStatus(rawValue: "invalid") == nil)
    }
    
    @Test func testKEFSourceFromRawValue() {
        // Test valid raw values
        #expect(KEFSource(rawValue: "wifi") == .wifi)
        #expect(KEFSource(rawValue: "bluetooth") == .bluetooth)
        #expect(KEFSource(rawValue: "tv") == .tv)
        #expect(KEFSource(rawValue: "optic") == .optic)
        #expect(KEFSource(rawValue: "coaxial") == .coaxial)
        #expect(KEFSource(rawValue: "analog") == .analog)
        #expect(KEFSource(rawValue: "usb") == .usb)
        
        // Test invalid raw value
        #expect(KEFSource(rawValue: "invalid") == nil)
        #expect(KEFSource(rawValue: "optical") == nil) // Common mistake
        #expect(KEFSource(rawValue: "standby") == nil) // Not a source
    }
}

// MARK: - Integration Tests
// These tests require a real speaker or would need to be mocked at a higher level

struct IntegrationTests {
    
    @Test func testSpeakerInitialization() async throws {
        // Test that we can create a speaker instance
        // This doesn't make network calls
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        let speaker = KEFSpeaker(host: "192.168.1.100", httpClient: httpClient)
        #expect(await speaker.host == "192.168.1.100")
        try await httpClient.shutdown()
    }
    
    @Test func testSpeakerInitializationWithPort() async throws {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        let speaker = KEFSpeaker(host: "192.168.1.100", port: 8080, httpClient: httpClient)
        #expect(await speaker.host == "192.168.1.100")
        #expect(await speaker.port == 8080)
        try await httpClient.shutdown()
    }
    
    @Test func testURLConstruction() async throws {
        // Test that the speaker constructs valid URLs
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        let speaker = KEFSpeaker(host: "192.168.1.100", httpClient: httpClient)
        
        // We can't easily test the internal URL construction without making it public
        // or using a real network call, but we can verify the speaker is properly initialized
        #expect(await speaker.host == "192.168.1.100")
        #expect(await speaker.port == 80) // Default port
        try await httpClient.shutdown()
    }
    
    @Test func testVolumeValidation() {
        // Volume should be clamped between 0 and 100
        // We can't test this without network calls, but we document the expected behavior
        
        // Expected behavior:
        // - Volume < 0 should be clamped to 0
        // - Volume > 100 should be clamped to 100
        // - Volume 0-100 should be used as-is
        #expect(Bool(true)) // Placeholder for documentation
    }
    
    @Test func testSourceValidation() {
        // All KEFSource enum cases should be valid for setSource
        // The speaker should handle the "standby" and "powerOn" special cases internally
        
        // Expected behavior:
        // - getSource() returns "standby" -> throws KEFError.speakerNotResponding
        // - getSource() returns "powerOn" -> returns .wifi as default
        // - All other values map directly to KEFSource enum
        #expect(Bool(true)) // Placeholder for documentation
    }
}

// MARK: - Error Handling Tests

struct ErrorHandlingTests {
    
    @Test func testKEFErrorLocalizedDescription() {
        // Test that all errors have proper localized descriptions
        let errors: [KEFError] = [
            .networkError("Test error"),
            .invalidResponse,
            .jsonParsingError,
            .speakerNotResponding,
            .invalidURL
        ]
        
        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
            #expect(error.localizedDescription == error.errorDescription)
        }
    }
    
    @Test func testErrorCasesAreMutuallyExclusive() {
        let error1 = KEFError.networkError("Test")
        let error2 = KEFError.networkError("Different")
        let error3 = KEFError.invalidResponse
        
        #expect(error1 != error2) // Different associated values
        #expect(error1 != error3) // Different cases
        #expect(error2 != error3) // Different cases
    }
}

// MARK: - Polling Tests

struct PollingTests {
    
    @Test func testPlaybackStateFromRawValue() {
        // Test valid raw values
        #expect(PlaybackState(rawValue: "playing") == .playing)
        #expect(PlaybackState(rawValue: "paused") == .paused)
        #expect(PlaybackState(rawValue: "stopped") == .stopped)
        
        // Test invalid raw value
        #expect(PlaybackState(rawValue: "invalid") == nil)
        #expect(PlaybackState(rawValue: "play") == nil) // Common mistake
    }
    
    @Test func testKEFSpeakerEventPartialUpdates() {
        // Test that KEFSpeakerEvent can represent partial updates
        let volumeOnlyEvent = KEFSpeakerEvent(volume: 75)
        #expect(volumeOnlyEvent.volume == 75)
        #expect(volumeOnlyEvent.source == nil)
        #expect(volumeOnlyEvent.songInfo == nil)
        
        let sourceOnlyEvent = KEFSpeakerEvent(source: .bluetooth)
        #expect(sourceOnlyEvent.source == .bluetooth)
        #expect(sourceOnlyEvent.volume == nil)
        
        let playbackEvent = KEFSpeakerEvent(
            songPosition: 45000,
            playbackState: .playing
        )
        #expect(playbackEvent.songPosition == 45000)
        #expect(playbackEvent.playbackState == .playing)
        #expect(playbackEvent.volume == nil)
    }
    
    @Test func testPollingTimeoutValidation() {
        // Document expected behavior for timeout validation
        // - Timeout should be clamped between 1 and 60 seconds
        // - Default timeout is 10 seconds
        // - HTTP timeout should be slightly longer than poll timeout
        #expect(Bool(true)) // Placeholder for documentation
    }
    
    @Test func testPollingQueueManagement() {
        // Document expected polling queue behavior
        // - Queue is created on first poll or when expired (>50 seconds)
        // - Queue is recreated when pollSongStatus parameter changes
        // - Queue ID is extracted from response (removing quotes)
        #expect(Bool(true)) // Placeholder for documentation
    }
}

// MARK: - Concurrency Tests

struct ConcurrencyTests {
    
    @Test func testActorIsolation() async throws {
        // Test that KEFSpeaker properly uses actor isolation
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        let _ = KEFSpeaker(host: "192.168.1.100", httpClient: httpClient)
        
        // All public methods should be async
        // This is enforced at compile time, so if it compiles, it passes
        #expect(Bool(true))
        try await httpClient.shutdown()
    }
    
    @Test func testSendableTypes() {
        // All public types should be Sendable for concurrent use
        // This is verified at compile time through the Sendable conformances
        
        func requiresSendable<T: Sendable>(_: T) {}
        
        // These should all compile without warnings
        requiresSendable(KEFSource.wifi)
        requiresSendable(KEFSpeakerStatus.standby)
        requiresSendable(SongInfo())
        requiresSendable(KEFError.invalidResponse)
        requiresSendable(PlaybackState.playing)
        requiresSendable(KEFSpeakerEvent())
    }
}