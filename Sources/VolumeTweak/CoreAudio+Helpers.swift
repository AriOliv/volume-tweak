import CoreAudio
import Foundation

struct CAError: Error, CustomStringConvertible {
    let status: OSStatus
    let context: String
    var description: String { "\(context) (OSStatus \(status))" }
}

@inline(__always)
func check(_ status: OSStatus, _ context: String) throws {
    guard status == noErr else { throw CAError(status: status, context: context) }
}

func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &value), "read \(selector)")
        return value
    }

    func readArray<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, zero: T) throws -> [T] {
        var addr = address(selector)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size), "size \(selector)")
        let count = Int(size) / MemoryLayout<T>.size
        guard count > 0 else { return [] }
        var values = [T](repeating: zero, count: count)
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &values), "read array \(selector)")
        return values
    }

    func readString(_ selector: AudioObjectPropertySelector) throws -> String {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        try withUnsafeMutablePointer(to: &value) {
            try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, $0), "read string \(selector)")
        }
        return value as String
    }

    static func defaultOutputDevice() throws -> AudioObjectID {
        try AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown))
    }
}
