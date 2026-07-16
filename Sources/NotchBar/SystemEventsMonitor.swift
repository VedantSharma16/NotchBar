import AppKit
import CoreAudio
import CoreMediaIO
import IOKit.ps
import SwiftUI

/// Watches the system for notch-worthy moments: charger plug/unplug,
/// low battery, audio output changes (AirPods!), and mic/camera use.
/// Battery and audio are event-driven; mic/camera are polled gently.
final class SystemEventsMonitor {
    private let activities: ActivityCenter
    private var powerRunLoopSource: CFRunLoopSource?
    private var indicatorTimer: Timer?

    private var lastPluggedIn: Bool?
    private var micWasInUse = false
    private var cameraWasInUse = false

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        startPowerMonitoring()
        startAudioOutputMonitoring()
        indicatorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPrivacyIndicators()
        }
    }

    // MARK: - Battery / charger (IOKit, event-driven)

    private func startPowerMonitoring() {
        lastPluggedIn = Self.readPower()?.pluggedIn
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<SystemEventsMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { monitor.powerChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerRunLoopSource = source
    }

    private func powerChanged() {
        guard let power = Self.readPower() else { return }

        if let previous = lastPluggedIn, previous != power.pluggedIn {
            activities.post(NotchActivity(
                key: "power",
                symbol: power.pluggedIn ? "bolt.fill" : "battery.75percent",
                tint: power.pluggedIn ? .green : .white,
                text: "\(power.percent)%",
                detail: power.pluggedIn
                    ? "Charging — \(power.percent)%"
                    : "On battery — \(power.percent)%",
                priority: 70,
                expiresAt: Date().addingTimeInterval(4)
            ))
        }
        lastPluggedIn = power.pluggedIn

        if power.percent <= 15 && !power.pluggedIn {
            activities.post(NotchActivity(
                key: "low-battery",
                symbol: "battery.25percent",
                tint: .red,
                text: "\(power.percent)%",
                detail: "Low battery — \(power.percent)% remaining",
                priority: 90,
                expiresAt: nil,
                pulses: true
            ))
        } else {
            activities.remove(key: "low-battery")
        }
    }

    private static func readPower() -> (percent: Int, pluggedIn: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                  let type = desc[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0,
                  let state = desc[kIOPSPowerSourceStateKey] as? String
            else { continue }
            let percent = Int((Double(current) / Double(max) * 100).rounded())
            return (percent, state == kIOPSACPowerValue)
        }
        return nil
    }

    // MARK: - Audio output changes (CoreAudio, event-driven)

    private func startAudioOutputMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            // Give CoreAudio a beat to settle on the new device's name.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.outputDeviceChanged()
            }
        }
    }

    private func outputDeviceChanged() {
        let output = AudioOutput.current()
        activities.post(NotchActivity(
            key: "audio-output",
            symbol: output.symbolName,
            tint: .white,
            text: String(output.name.prefix(11)),
            detail: "Now playing through \(output.name)",
            priority: 60,
            expiresAt: Date().addingTimeInterval(4)
        ))
    }

    // MARK: - Mic / camera indicators (polled every 2 s)

    private func checkPrivacyIndicators() {
        let micNow = Self.micInUse()
        if micNow != micWasInUse {
            micWasInUse = micNow
            if micNow {
                activities.post(NotchActivity(
                    key: "mic",
                    symbol: "mic.fill",
                    tint: .orange,
                    text: "Mic",
                    detail: "Microphone is in use",
                    priority: 80
                ))
            } else {
                activities.remove(key: "mic")
            }
        }

        let cameraNow = Self.cameraInUse()
        if cameraNow != cameraWasInUse {
            cameraWasInUse = cameraNow
            if cameraNow {
                activities.post(NotchActivity(
                    key: "camera",
                    symbol: "video.fill",
                    tint: .green,
                    text: "Camera",
                    detail: "Camera is in use",
                    priority: 80
                ))
            } else {
                activities.remove(key: "camera")
            }
        }
    }

    private static func micInUse() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != 0 else { return false }

        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            deviceID, &runningAddress, 0, nil, &runningSize, &running
        ) == noErr else { return false }
        return running != 0
    }

    private static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize
        ) == 0, dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &dataUsed, &devices
        ) == 0 else { return false }

        var runningAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        for device in devices {
            var running: UInt32 = 0
            var used: UInt32 = 0
            if CMIOObjectGetPropertyData(
                device, &runningAddress, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &used, &running
            ) == 0, running != 0 {
                return true
            }
        }
        return false
    }
}
