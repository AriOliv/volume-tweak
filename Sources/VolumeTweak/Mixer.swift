import CoreAudio
import Foundation
import SwiftUI

@MainActor
final class Mixer: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var gains: [String: Float] = [:]
    @Published var showIdle = false
    @Published private(set) var lastError: String?

    private var taps: [String: AppTap] = [:]
    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private static let gainsKey = "gains"

    static let maxGain: Float = 2.0

    init() {
        gains = (defaults.dictionary(forKey: Self.gainsKey) as? [String: Double])?
            .mapValues { Float($0) } ?? [:]
        outputDevice = (try? AudioObjectID.defaultOutputDevice()) ?? outputDevice
        observeDefaultOutput()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var visibleApps: [AudioApp] {
        apps.filter { showIdle || $0.isPlaying || gain(for: $0.id) != 1 }
    }

    func gain(for id: String) -> Float { gains[id] ?? 1 }

    func setGain(_ value: Float, for id: String) {
        let snapped = abs(value - 1) < 0.02 ? 1 : value
        gains[id] = snapped == 1 ? nil : snapped
        defaults.set(gains.mapValues { Double($0) }, forKey: Self.gainsKey)
        if let tap = taps[id] {
            tap.gain.value = snapped
        }
        sync()
    }

    func resetAll() {
        gains.removeAll()
        defaults.removeObject(forKey: Self.gainsKey)
        sync()
    }

    func refresh() {
        let scanned = AudioAppScanner.scan()
        if scanned != apps { apps = scanned }
        sync()
    }

    /// Garante que exista um tap exatamente para os apps com ganho ≠ 100%.
    private func sync() {
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        for (id, tap) in taps {
            guard let app = byID[id], gain(for: id) != 1, app.processObjectIDs == tap.processObjectIDs else {
                tap.stop()
                taps[id] = nil
                continue
            }
        }
        for app in apps where gain(for: app.id) != 1 && taps[app.id] == nil {
            do {
                taps[app.id] = try AppTap(processObjectIDs: app.processObjectIDs,
                                          outputDevice: outputDevice,
                                          gain: gain(for: app.id))
                lastError = nil
            } catch {
                lastError = "\(app.name): \(error)"
            }
        }
    }

    private func observeDefaultOutput() {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(.system, &addr, .main) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, let device = try? AudioObjectID.defaultOutputDevice(),
                      device != self.outputDevice else { return }
                self.outputDevice = device
                self.taps.values.forEach { $0.stop() }
                self.taps.removeAll()
                self.sync()
            }
        }
    }
}
