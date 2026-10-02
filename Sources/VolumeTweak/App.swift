import SwiftUI

@main
struct VolumeTweakApp: App {
    @StateObject private var mixer = Mixer()

    var body: some Scene {
        MenuBarExtra("VolumeTweak", systemImage: "slider.vertical.3") {
            MixerView().environmentObject(mixer)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MixerView: View {
    @EnvironmentObject var mixer: Mixer

    static let rowHeight: CGFloat = 48
    static let rowSpacing: CGFloat = 10

    private var listHeight: CGFloat {
        let rows = CGFloat(mixer.visibleApps.count)
        let content = rows * Self.rowHeight + max(rows - 1, 0) * Self.rowSpacing + 8
        return min(content, 520)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Volume por app").font(.headline)
                Spacer()
                Toggle("Mostrar inativos", isOn: $mixer.showIdle)
                    .toggleStyle(.switch).controlSize(.mini).font(.caption)
            }

            if mixer.visibleApps.isEmpty {
                Text("Nenhum app tocando áudio agora.")
                    .foregroundStyle(.secondary).font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                // ScrollView não tem altura ideal no MenuBarExtra; calculamos pelo nº de linhas.
                ScrollView {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(mixer.visibleApps) { app in AppRow(app: app) }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: listHeight)
            }

            if let error = mixer.lastError {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(3)
            }

            Divider()
            HStack {
                Button("Resetar tudo") { mixer.resetAll() }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .buttonStyle(.borderless).font(.callout)
        }
        .padding(14)
        .frame(width: 380)
    }
}

struct AppRow: View {
    @EnvironmentObject var mixer: Mixer
    let app: AudioApp

    var body: some View {
        let gain = mixer.gain(for: app.id)
        HStack(spacing: 8) {
            Group {
                if let icon = app.icon { Image(nsImage: icon).resizable() }
                else { Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary) }
            }
            .frame(width: 28, height: 28)
            .opacity(app.isPlaying ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.callout).lineLimit(1)
                Slider(value: Binding(get: { Double(gain) },
                                      set: { mixer.setGain(Float($0), for: app.id) }),
                       in: 0...Double(Mixer.maxGain))
                    .controlSize(.regular)
            }

            Button {
                mixer.setGain(gain == 0 ? 1 : 0, for: app.id)
            } label: {
                Image(systemName: gain == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(gain == 0 ? "Reativar" : "Silenciar")

            Text("\(Int((gain * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(gain == 1 ? .secondary : .primary)
                .frame(width: 40, alignment: .trailing)
                .onTapGesture(count: 2) { mixer.setGain(1, for: app.id) }
        }
        .frame(height: MixerView.rowHeight)
    }
}
