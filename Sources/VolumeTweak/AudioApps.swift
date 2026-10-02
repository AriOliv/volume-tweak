import AppKit
import CoreAudio

/// Um app (agrupando seus processos auxiliares) que está reproduzindo áudio.
struct AudioApp: Identifiable, Equatable {
    let id: String              // bundle ID do app "dono" (ou nome do executável)
    let name: String
    let icon: NSImage?
    var processObjectIDs: [AudioObjectID]
    var isPlaying: Bool

    static func == (a: AudioApp, b: AudioApp) -> Bool {
        a.id == b.id && a.processObjectIDs == b.processObjectIDs && a.isPlaying == b.isPlaying
    }
}

enum AudioAppScanner {
    /// Lista os processos que o Core Audio conhece e agrupa por app.
    /// Processos auxiliares (ex.: com.google.Chrome.helper) são atribuídos ao app
    /// cujo bundle ID é prefixo do deles.
    static func scan() -> [AudioApp] {
        let objects = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList,
                                                           zero: AudioObjectID(0))) ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier != nil }

        var groups: [String: AudioApp] = [:]
        for object in objects {
            guard let pid = try? object.read(kAudioProcessPropertyPID, initial: pid_t(0)),
                  pid != ownPID else { continue }
            let playing = ((try? object.read(kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0) != 0
            let bundleID = (try? object.readString(kAudioProcessPropertyBundleID)) ?? ""

            let owner = owningApp(pid: pid, bundleID: bundleID, running: running)
            let key = owner?.bundleIdentifier ?? (bundleID.isEmpty ? executableName(pid) : bundleID)
            guard !key.isEmpty, !ignored.contains(key) else { continue }

            if var existing = groups[key] {
                existing.processObjectIDs.append(object)
                existing.isPlaying = existing.isPlaying || playing
                groups[key] = existing
            } else {
                groups[key] = AudioApp(id: key,
                                       name: owner?.localizedName ?? displayName(bundleID: bundleID, pid: pid),
                                       icon: owner?.icon,
                                       processObjectIDs: [object],
                                       isPlaying: playing)
            }
        }
        return groups.values
            .map { var g = $0; g.processObjectIDs.sort(); return g }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Daemons do sistema que aparecem na lista mas não fazem sentido controlar.
    private static let ignored: Set<String> = [
        "com.apple.audio.coreaudiod", "com.apple.CoreSpeech", "com.apple.siri",
        "com.apple.controlcenter", "com.apple.audio.AudioComponentRegistrar",
    ]

    private static func owningApp(pid: pid_t, bundleID: String,
                                  running: [NSRunningApplication]) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: pid),
           app.activationPolicy == .regular { return app }
        guard !bundleID.isEmpty else { return NSRunningApplication(processIdentifier: pid) }
        // Prefixo mais longo vence (ex.: com.google.Chrome.helper → com.google.Chrome).
        return running
            .filter { app in
                guard let id = app.bundleIdentifier else { return false }
                return bundleID == id || bundleID.hasPrefix(id + ".")
            }
            .max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
            ?? NSRunningApplication(processIdentifier: pid)
    }

    private static func executableName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }

    private static func displayName(bundleID: String, pid: pid_t) -> String {
        let exe = executableName(pid)
        if !exe.isEmpty { return exe }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
