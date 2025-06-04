# Changelog

All notable changes to SwiftKEF will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-06-04

### Added
- Real-time event polling API for monitoring speaker state changes
  - `pollSpeaker(timeout:pollSongStatus:)` - Single poll for current events
  - `startPolling(pollInterval:pollSongStatus:)` - Continuous event streaming via AsyncThrowingStream
- New public methods for playback tracking:
  - `getSongPosition()` - Get current playback position in milliseconds
  - `getSongDuration()` - Get track duration in milliseconds
- New types for event handling:
  - `KEFSpeakerEvent` - Consolidated event data with all speaker state fields
  - `PlaybackState` enum - Track playback states (playing/paused/stopped)
- Support for real-time song position updates during playback
- Automatic polling queue management with reconnection on timeout

### Fixed
- Polling queue ID format - Now uses plain queue ID without braces for proper speaker compatibility
- Improved error handling for network interruptions during polling

### Changed
- Enhanced `SongInfo` and all enums with `Equatable` conformance for better state tracking

## [1.0.0] - 2024-XX-XX

### Added
- Initial release with core speaker control functionality
- Volume control (set, get, mute, unmute)
- Power management (on, standby, status)
- Source selection (WiFi, Bluetooth, TV, Optical, Coaxial, Analog, USB)
- Playback control (play/pause, next, previous)
- Track information retrieval
- Speaker information (name, MAC address, firmware version)
- Full async/await support with Swift concurrency
- Type-safe enums for sources and status
- Comprehensive error handling with `KEFError` type