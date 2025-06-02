import Testing
@testable import SwiftKEF

struct SwiftKEFTests {
    
    @Test func testKEFSourceAllCases() {
        let expectedSources: [KEFSource] = [.standby, .wifi, .bluetooth, .tv, .optical, .coaxial, .analog, .usb]
        #expect(KEFSource.allCases.count == expectedSources.count)
        
        for source in expectedSources {
            #expect(KEFSource.allCases.contains(source))
        }
    }
    
    @Test func testKEFSourceRawValues() {
        #expect(KEFSource.standby.rawValue == "standby")
        #expect(KEFSource.wifi.rawValue == "wifi")
        #expect(KEFSource.bluetooth.rawValue == "bluetooth")
        #expect(KEFSource.tv.rawValue == "tv")
        #expect(KEFSource.optical.rawValue == "optical")
        #expect(KEFSource.coaxial.rawValue == "coaxial")
        #expect(KEFSource.analog.rawValue == "analog")
        #expect(KEFSource.usb.rawValue == "usb")
    }
    
    @Test func testKEFSpeakerStatusRawValues() {
        #expect(KEFSpeakerStatus.standby.rawValue == "standby")
        #expect(KEFSpeakerStatus.poweredOn.rawValue == "poweredOn")
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
    }
}