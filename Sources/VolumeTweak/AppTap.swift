import CoreAudio
import Foundation

/// Ganho lido pela thread de áudio. Escrita/leitura de Float alinhado é atômica no arm64/x86_64,
/// então não usamos lock no caminho de tempo real.
final class GainBox {
    var value: Float
    init(_ value: Float) { self.value = value }
}

/// Intercepta o áudio de um conjunto de processos (silenciando a saída original),
/// aplica ganho e reproduz no dispositivo de saída.
final class AppTap {
    let processObjectIDs: [AudioObjectID]
    let gain: GainBox

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "volumetweak.io", qos: .userInteractive)

    init(processObjectIDs: [AudioObjectID], outputDevice: AudioObjectID, gain: Float) throws {
        self.processObjectIDs = processObjectIDs
        self.gain = GainBox(gain)
        do {
            try start(outputDevice: outputDevice)
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    private func start(outputDevice: AudioObjectID) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.name = "VolumeTweak"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")

        let outputUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VolumeTweak",
            kAudioAggregateDeviceUIDKey: "volumetweak.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
                  "AudioHardwareCreateAggregateDevice")

        let gain = self.gain
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, input, _, output, _ in
            AppTap.render(input: input, output: output, gain: gain.value)
        }, "AudioDeviceCreateIOProcIDWithBlock")
        try check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        ioProcID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Copia o mixdown estéreo do tap para os dois primeiros canais da saída, com ganho.
    /// Os buffers de entrada do tap ficam no fim da lista (após eventuais entradas do dispositivo).
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>,
                               gain: Float) {
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }

        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard ins.count > 0, outs.count > 0 else { return }

        // Localiza os buffers do tap (2 canais) a partir do fim.
        var tapBuffers: [AudioBuffer] = []
        var channels = 0
        for buffer in ins.reversed() where channels < 2 {
            tapBuffers.insert(buffer, at: 0)
            channels += Int(buffer.mNumberChannels)
        }

        func source(_ channel: Int) -> (UnsafePointer<Float>, stride: Int, frames: Int)? {
            var c = channel
            for buffer in tapBuffers {
                let n = Int(buffer.mNumberChannels)
                if c < n, let data = buffer.mData {
                    let p = data.assumingMemoryBound(to: Float.self)
                    let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * n)
                    return (UnsafePointer(p + c), n, frames)
                }
                c -= n
            }
            return nil
        }

        var outChannel = 0
        for buffer in outs {
            guard let data = buffer.mData else { continue }
            let n = Int(buffer.mNumberChannels)
            let dst = data.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * n)
            for c in 0..<n where outChannel + c < 2 {
                // Se o tap for mono, replica no canal direito.
                guard let src = source(outChannel + c) ?? source(0) else { continue }
                for f in 0..<min(frames, src.frames) {
                    let s = src.0[f * src.stride] * gain
                    dst[f * n + c] = max(-1, min(1, s))
                }
            }
            outChannel += n
            if outChannel >= 2 { break }
        }
    }
}
