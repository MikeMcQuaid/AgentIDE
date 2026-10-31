import AppKit
import SanductorData
import SwiftUI
import TerminalUI

// MARK: - NotificationsSettingsPane

/// Which agent events notify and what each sounds like. The chime
/// picker that lived in the app menu moved here with the rest.
struct NotificationsSettingsPane: View {
    // MARK: Internal

    var body: some View {
        Form {
            eventRow(.done, title: "Agent finished", detail: "A turn completed; the answer is waiting.")
            eventRow(.blocked, title: "Agent needs input", detail: "A question or approval is waiting.")
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    private static let iconSpacing: CGFloat = 6

    private func eventRow(
        _ event: NotificationPreferences.Event,
        title: String,
        detail: String,
    ) -> some View {
        Section {
            HStack(spacing: Self.iconSpacing) {
                statusIcon(for: event)
                Toggle(title, isOn: toggleBinding(key: event.enabledKey))
            }
            if event == .blocked {
                Toggle("Count in the Dock badge", isOn: toggleBinding(key: NotificationPreferences.badgeKey))
            }
            Text(detail)
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
            SoundPicker(event: event)
        }
    }

    /// The sidebar icon this event pairs with, so the sound and the
    /// glyph learn each other here.
    @ViewBuilder
    private func statusIcon(for event: NotificationPreferences.Event) -> some View {
        switch event {
        case .done:
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
                .hoverHelp("The sidebar's turn-done icon")

        case .blocked:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
                .hoverHelp("The sidebar's waiting-on-input icon")
        }
    }

    /// Absence means on, matching the readers' defaults.
    private func toggleBinding(key: String) -> Binding<Bool> {
        Binding(
            get: {
                UserDefaults.standard.object(forKey: key) == nil
                    || UserDefaults.standard.bool(forKey: key)
            },
            set: { UserDefaults.standard.set($0, forKey: key) },
        )
    }
}

// MARK: - SoundPicker

/// One event's chime: silence, the system's sound directories or an
/// audio file of your own, previewing each pick as it lands.
private struct SoundPicker: View {
    // MARK: Internal

    let event: NotificationPreferences.Event

    var body: some View {
        HStack {
            Picker("Sound", selection: previewingSelection) {
                Text("None").tag("")
                ForEach(CompletionSound.systemSounds(), id: \.path) { sound in
                    Text(sound.name).tag(sound.path)
                }
                if isCustom {
                    Text(URL(filePath: chosen).lastPathComponent).tag(chosen)
                }
            }
            .hoverHelp("Played on this event whether or not banners may show; None is silence")
            Button {
                CompletionSound.play(path: chosen)
            } label: {
                Image(systemName: "play.circle")
                    .accessibilityLabel("Play the selected sound")
            }
            .buttonStyle(.borderless)
            .disabled(chosen.isEmpty)
            .hoverHelp("Play the selected sound")
            Button("Choose File…") { chooseFile() }
                .hoverHelp("Any audio file playback accepts")
        }
    }

    // MARK: Private

    /// Redraws after a pick; the truth lives in the defaults key.
    @State private var generation = 0

    private var chosen: String {
        _ = generation
        return NotificationPreferences.sound(for: event)
    }

    private var isCustom: Bool {
        chosen.isEmpty == false
            && CompletionSound.systemSounds().contains { $0.path == chosen } == false
    }

    private var previewingSelection: Binding<String> {
        Binding(
            get: { chosen },
            set: { path in
                UserDefaults.standard.set(path, forKey: event.soundKey)
                generation += 1
                CompletionSound.play(path: path)
            },
        )
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = CompletionSound.allowedTypes
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/System/Library/Sounds")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        previewingSelection.wrappedValue = url.path
    }
}

// MARK: - EditorSettingsPane

/// The command used to open files in an external editor.
struct EditorSettingsPane: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("External editor") {
                TextField("Command", text: $externalEditor, prompt: Text("e.g. zed --wait"))
                Text("Runs on Cmd-clicking a file in a diff, finder result or conversation, "
                    + "with the file path appended; arguments split on spaces. Empty hands "
                    + "Cmd-clicked files to the system's default app. A plain click always "
                    + "opens the built-in editor.")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @AppStorage(AppSettings.externalEditorKey)
    private var externalEditor = ""
}
