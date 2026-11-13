import AppKit
import SwiftUI

/// Choix d'un raccourci clavier : clic, puis la combinaison voulue (Échap annule).
/// Une lettre avec ⌘ ou ⌃ ; les raccourcis déjà pris par LabPanel ou macOS sont refusés.
struct ShortcutRecorder: View {
    let title: LocalizedStringKey
    @Binding var shortcut: Shortcut?
    let defaultShortcut: Shortcut

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var problem: LocalizedStringKey?

    init(_ title: LocalizedStringKey, shortcut: Binding<Shortcut?>, defaultShortcut: Shortcut) {
        self.title = title
        _shortcut = shortcut
        self.defaultShortcut = defaultShortcut
    }

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Button {
                        isRecording ? stopRecording() : startRecording()
                    } label: {
                        Group {
                            if isRecording {
                                Text("Tape le raccourci…")
                            } else if let shortcut {
                                Text(verbatim: shortcut.display).monospaced()
                            } else {
                                Text("Aucun")
                            }
                        }
                        .frame(minWidth: 120)
                    }
                    .help("Clique, puis tape la combinaison voulue. Échap pour annuler.")

                    Menu {
                        Button("Rétablir \(defaultShortcut.display)") { set(defaultShortcut) }
                            .disabled(shortcut == defaultShortcut)
                        Button("Aucun raccourci") { set(nil) }
                            .disabled(shortcut == nil)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func set(_ value: Shortcut?) {
        stopRecording()
        problem = nil
        shortcut = value
    }

    private func startRecording() {
        guard keyMonitor == nil else { return }
        problem = nil
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Échap
                stopRecording()
                return nil
            }
            guard let recorded = Shortcut(event: event) else {
                problem = "Une lettre avec ⌘ ou ⌃ (⌥ et ⇧ en plus si tu veux)."
                return nil
            }
            guard !recorded.isReserved else {
                problem = "\(recorded.display) est déjà utilisé par LabPanel ou macOS."
                return nil
            }
            set(recorded)
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecording = false
    }
}
