import AppKit
import CoreAudio

/// Reads the current default audio output device so the UI can show
/// what you're actually listening through (AirPods, speakers, …).
enum AudioOutput {
    struct Info: Equatable {
        let name: String
        let symbolName: String
    }

    static let fallback = Info(name: "Speakers", symbolName: "speaker.fill")

    static func current() -> Info {
        guard let deviceID = defaultOutputDeviceID() else { return fallback }
        let name = deviceName(deviceID) ?? "Speakers"
        return Info(name: name, symbolName: symbol(forName: name, transport: transportType(deviceID)))
    }

    // MARK: - CoreAudio plumbing

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func transportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        return transport
    }

    // MARK: - Icon selection

    private static func symbol(forName name: String, transport: UInt32) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") {
            return validated(["airpodsmax", "headphones"])
        }
        if lowered.contains("airpods pro") {
            return validated(["airpodspro", "airpods", "headphones"])
        }
        if lowered.contains("airpods") {
            return validated(["airpods", "headphones"])
        }
        if lowered.contains("beats") {
            return validated(["beats.headphones", "headphones"])
        }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return validated(["airplayaudio", "hifispeaker.fill"])
        case kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort:
            return "hifispeaker.fill"
        default:
            return "speaker.fill"
        }
    }

    /// SF Symbol names vary across macOS versions — use the first one
    /// that actually exists on this system.
    private static func validated(_ candidates: [String]) -> String {
        candidates.first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        } ?? "speaker.fill"
    }
}
