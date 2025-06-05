# SwiftKEF

A Swift library for controlling KEF wireless speakers (LSX II, LS50 Wireless II, LS60) over the network with real-time event monitoring.

> **Disclaimer**: This project is not affiliated with, authorized by, endorsed by, or in any way officially connected with KEF Audio or its subsidiaries. All product names, trademarks and registered trademarks are property of their respective owners.

![Swift](https://img.shields.io/badge/Swift-6.1-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-blue.svg)
![License](https://img.shields.io/badge/License-MIT-brightgreen.svg)

## Features

- 🔊 **Volume Control**: Set volume, mute/unmute
- 🎵 **Playback Control**: Play/pause, next/previous track
- 📻 **Source Selection**: Switch between inputs (WiFi, Bluetooth, Optic, etc.)
- 🔌 **Power Management**: Turn speakers on/off
- ℹ️ **Speaker Information**: Get name, MAC address, firmware details
- 🎼 **Track Information**: Get current playing track metadata
- 🔄 **Real-time Event Monitoring**: Live updates for volume, playback, and track changes
- ⏱️ **Song Position Tracking**: Monitor playback progress in real-time
- 🔍 **Auto-Discovery**: Find KEF speakers on your network using mDNS/Bonjour (Apple platforms)
- ⚡ **Async/Await**: Modern Swift concurrency support
- 🛡️ **Type Safety**: Strongly typed enums for sources and status

## Installation

### Swift Package Manager

Add SwiftKEF to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/melonamin/SwiftKEF.git", from: "1.1.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Select the version you want to use

## Requirements

- Swift 6.1+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+ / Linux
- KEF wireless speaker on the same network

## Usage

### Basic Setup

```swift
import SwiftKEF
import AsyncHTTPClient

// Create HTTP client
let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
defer {
    try await httpClient.shutdown()
}

// Initialize speaker with known IP
let speaker = KEFSpeaker(host: "192.168.1.100", httpClient: httpClient)
```

### Speaker Discovery (Apple platforms only)

```swift
// Discover speakers on the network
let speakers = try await KEFSpeaker.discover(httpClient: httpClient, timeout: 5.0)
for discovered in speakers {
    print("Found: \(discovered.name) at \(discovered.host)")
    
    // Create speaker instance from discovery
    let speaker = KEFSpeaker.from(discovered: discovered, httpClient: httpClient)
}

// Or use real-time discovery stream
for await discovered in KEFSpeaker.discoverStream(httpClient: httpClient) {
    print("Discovered: \(discovered.name) at \(discovered.host)")
    
    // Optional: Check model and MAC address
    if let model = discovered.model {
        print("Model: \(model)")
    }
}
```

### Volume Control

```swift
// Set volume (0-100)
try await speaker.setVolume(50)

// Get current volume
let volume = try await speaker.getVolume()
print("Current volume: \(volume)")

// Mute
try await speaker.mute()

// Unmute
try await speaker.unmute()
```

### Power Control

```swift
// Turn on
try await speaker.powerOn()

// Turn off (standby)
try await speaker.shutdown()

// Check power status
let status = try await speaker.getStatus()
if status == .poweredOn {
    print("Speaker is on")
}
```

### Source Selection

```swift
// Set input source
try await speaker.setSource(.bluetooth)
try await speaker.setSource(.optic)

// Get current source
let source = try await speaker.getSource()
print("Current source: \(source.rawValue)")

// Available sources
for source in KEFSource.allCases {
    print(source.rawValue)
}
```

### Playback Control

```swift
// Toggle play/pause
try await speaker.togglePlayPause()

// Next track
try await speaker.nextTrack()

// Previous track
try await speaker.previousTrack()

// Check if playing
let isPlaying = try await speaker.isPlaying()

// Get track information
if isPlaying {
    let songInfo = try await speaker.getSongInformation()
    print("Now playing: \(songInfo.title ?? "Unknown")")
    print("Artist: \(songInfo.artist ?? "Unknown")")
    print("Album: \(songInfo.album ?? "Unknown")")
    
    // Get playback position
    if let position = try await speaker.getSongPosition(),
       let duration = try await speaker.getSongDuration() {
        let progress = Double(position) / Double(duration)
        print("Progress: \(Int(progress * 100))%")
    }
}
```

### Speaker Information

```swift
// Get speaker name
let name = try await speaker.getSpeakerName()

// Get MAC address
let mac = try await speaker.getMacAddress()

// Get firmware info
let firmware = try await speaker.getFirmwareVersion()
print("Model: \(firmware.model)")
print("Version: \(firmware.version)")
```

### Error Handling

```swift
do {
    try await speaker.setVolume(75)
} catch KEFError.networkError(let message) {
    print("Network error: \(message)")
} catch KEFError.speakerNotResponding {
    print("Speaker is not responding")
} catch {
    print("Error: \(error)")
}
```

### Real-time Event Monitoring

Monitor speaker status changes in real-time using the polling API. The speaker sends immediate updates when any monitored parameter changes:

```swift
// Single poll for current events
let event = try await speaker.pollSpeaker(timeout: 10)
if let volume = event.volume {
    print("Volume changed to: \(volume)")
}

// Continuous polling stream
let eventStream = await speaker.startPolling(
    pollInterval: 10,      // Check for events every 10 seconds
    pollSongStatus: true   // Include real-time song position updates
)

for try await event in eventStream {
    // Handle volume changes
    if let volume = event.volume {
        print("Volume: \(volume)")
    }
    
    // Handle source changes
    if let source = event.source {
        print("Source: \(source.rawValue)")
    }
    
    // Handle playback updates
    if let state = event.playbackState {
        print("Playback: \(state.rawValue)")
    }
    
    // Track position updates (when pollSongStatus is true)
    if let position = event.songPosition,
       let duration = event.songDuration {
        let progress = Double(position) / Double(duration)
        print("Progress: \(Int(progress * 100))%")
    }
}
```

## Example Applications

### Command Line Tools

- [KefirCLI](https://github.com/melonamin/KefirCLI) - Feature-rich CLI with interactive TUI mode and real-time updates
- [KEFControl](https://github.com/melonamin/KEFControl) - Simple command-line interface

### SwiftUI Example

```swift
import SwiftUI
import SwiftKEF
import AsyncHTTPClient

struct ContentView: View {
    @State private var volume: Int = 0
    @State private var isPlaying = false

    let speaker: KEFSpeaker

    var body: some View {
        VStack {
            Text("Volume: \(volume)")

            Slider(value: Binding(
                get: { Double(volume) },
                set: { newValue in
                    Task {
                        try await speaker.setVolume(Int(newValue))
                    }
                }
            ), in: 0...100)

            Button(isPlaying ? "Pause" : "Play") {
                Task {
                    try await speaker.togglePlayPause()
                    isPlaying.toggle()
                }
            }
        }
        .task {
            volume = try await speaker.getVolume()
            isPlaying = try await speaker.isPlaying()
        }
    }
}
```

## Supported Speakers

- KEF LSX II
- KEF LS50 Wireless II
- KEF LS60

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

This Swift implementation is inspired by the [pykefcontrol](https://github.com/N0ciple/pykefcontrol) Python library.

## Author

[@melonamin](https://github.com/melonamin)

## Links

- [Documentation](https://melonamin.github.io/SwiftKEF/)
- [Swift Package Index](https://swiftpackageindex.com/melonamin/SwiftKEF)
- [Report Issues](https://github.com/melonamin/SwiftKEF/issues)
