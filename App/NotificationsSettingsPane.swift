import AgentIDEData
import AppKit
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
            eventRow(.finished, title: "Agent exited", detail: "The agent's process ended.")
            eventRow(
                .output,
                title: "Agent output",
                detail: "Unread output once the agent pauses for you; streaming output "
                    + "never counts, and this never chimes.",
            )
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    private static let iconSpacing: CGFloat = 6
    private static let dotSize: CGFloat = 6

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
            Toggle("Count in the Dock badge", isOn: toggleBinding(key: event.badgeKey))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if event.soundKey != nil {
                SoundPicker(event: event)
            }
        }
    }

    /// The sidebar icon this event pairs with, so the sound and the
    /// glyph learn each other here.
    @ViewBuilder
    private func statusIcon(for event: NotificationPreferences.Event) -> some View {
        switch event {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
                .hoverHelp("The sidebar's turn-done icon")

        case .blocked:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
                .hoverHelp("The sidebar's waiting-on-input icon")

        case .finished:
            Image(systemName: "stop.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                .hoverHelp("The sidebar's exited icon")

        case .output:
            Circle()
                .fill(.tint)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .accessibilityHidden(true)
                .hoverHelp("The sidebar's unread dot")
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
                // The picker only renders for events with a sound
                // slot, so the key is always there in practice.
                if let key = event.soundKey {
                    UserDefaults.standard.set(path, forKey: key)
                }
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

/// The external editor command and the one monospace typography
/// every code surface shares.
struct EditorSettingsPane: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("External editor") {
                TextField("Command", text: $externalEditor, prompt: Text("e.g. zed --wait"))
                Text("Runs with the file path appended; arguments split on spaces. "
                    + "Empty keeps everything in the built-in editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Monospace font") {
                Picker("Font", selection: $fontName) {
                    ForEach(Self.monospaceFontNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Stepper("Size " + String(Int(fontSize)), value: $fontSize, in: Self.sizeRange)
                Text("Shared by diffs, the editor, finder results and code blocks; "
                    + "terminals already open keep the font they started with.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    private static let sizeRange: ClosedRange<Double> = 9 ... 24

    /// Every installed fixed-pitch face, the default first.
    private static let monospaceFontNames: [String] = {
        let fixed = NSFontManager.shared
            .availableFontNames(with: .fixedPitchFontMask)?
            .sorted() ?? []
        return [CodeStyle.defaultFontName] + fixed.filter { $0 != CodeStyle.defaultFontName }
    }()

    @AppStorage(AppSettings.externalEditorKey)
    private var externalEditor = ""
    /// Literal defaults, matching `CodeStyle`'s own: the formatter
    /// rewrites `Type.member` initialisers into broken annotations.
    @AppStorage(AppSettings.codeFontNameKey)
    private var fontName = "SFMono-Regular"
    @AppStorage(AppSettings.codeFontSizeKey)
    private var fontSize = 13.0
}
