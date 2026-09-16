import AgentIDEData
import AppKit
import CoreText
import SwiftUI
import TerminalUI

// MARK: - FontsSettingsPane

/// All typography preferences, applied to the main window as they change.
struct FontsSettingsPane: View {
    // MARK: Internal

    var body: some View {
        Form {
            FontSettingsSection(
                title: "Code and terminals",
                detail: "Terminals, editors, diffs, finder results and code blocks.",
                nameKey: AppSettings.codeFontNameKey,
                sizeKey: AppSettings.codeFontSizeKey,
                defaultName: CodeStyle.defaultFontName,
                defaultSize: CodeStyle.defaultPointSize,
                monospaced: true,
            )
            sidebarSections
            FontSettingsSection(
                title: "Utility tabs",
                detail: "The tabs at the top of the right-hand pane.",
                nameKey: AppSettings.tabFontNameKey,
                sizeKey: AppSettings.tabFontSizeKey,
                defaultName: "",
                defaultSize: TabStyle.defaultPointSize,
                monospaced: false,
            )
            Text("Changes appear immediately in the main window. Reset restores each group's original font and size.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @ViewBuilder private var sidebarSections: some View {
        FontSettingsSection(
            title: "Repository names",
            detail: "Project headings in the left-hand sidebar.",
            nameKey: AppSettings.repositoryFontNameKey,
            sizeKey: AppSettings.repositoryFontSizeKey,
            defaultName: "",
            defaultSize: RepositoryStyle.defaultPointSize,
            monospaced: false,
        )
        FontSettingsSection(
            title: "Worktrees and branch names",
            detail: "Names throughout the app, with sidebar details sized to match.",
            nameKey: AppSettings.nameFontNameKey,
            sizeKey: AppSettings.nameFontSizeKey,
            defaultName: "",
            defaultSize: NameStyle.defaultPointSize,
            monospaced: true,
        )
    }
}

// MARK: - FontSettingsSection

/// One shared picker and size stepper for every kind of text.
private struct FontSettingsSection: View {
    // MARK: Lifecycle

    init(
        title: String,
        detail: String,
        nameKey: String,
        sizeKey: String,
        defaultName: String,
        defaultSize: Double,
        monospaced: Bool,
    ) {
        self.title = title
        self.detail = detail
        self.defaultName = defaultName
        self.defaultSize = defaultSize
        self.monospaced = monospaced
        _fontName = AppStorage(wrappedValue: defaultName, nameKey)
        _fontSize = AppStorage(wrappedValue: defaultSize, sizeKey)
    }

    // MARK: Internal

    var body: some View {
        Section(title) {
            Picker("Font", selection: familyBinding) {
                Text(defaultFamily + " (default)").tag(defaultName)
                ForEach(families, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            LabeledContent("Size") {
                HStack {
                    Stepper(String(Int(sizeBinding.wrappedValue)) + " pt", value: sizeBinding, in: Self.sizeRange)
                    Button("Reset") {
                        fontName = defaultName
                        fontSize = defaultSize
                    }
                    .disabled(fontName == defaultName && sizeBinding.wrappedValue == defaultSize)
                    .hoverHelp("Restore the original font and size for " + title.lowercased())
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    private static let sizeRange: ClosedRange<Double> = 9 ... 32
    private static let installedFamilies = NSFontManager.shared.availableFontFamilies.sorted()
    private static let monospaceFamilies = installedFamilies.filter { family in
        NSFont(name: family, size: CodeStyle.defaultPointSize)?.isFixedPitch == true
    }

    @AppStorage private var fontName: String
    @AppStorage private var fontSize: Double

    private let title: String
    private let detail: String
    private let defaultName: String
    private let defaultSize: Double
    private let monospaced: Bool

    private var defaultFamily: String {
        let face = NSFont(name: defaultName, size: defaultSize)
            ?? (monospaced ? .monospacedSystemFont(ofSize: defaultSize, weight: .regular)
                : .systemFont(ofSize: defaultSize))
        if let family = face.familyName, family.hasPrefix(".") == false {
            return family
        }
        // System fonts report private family names; identify their backing face.
        let postScriptName = CTFontCopyGraphicsFont(face, nil).postScriptName as String? ?? ""
        if postScriptName.hasPrefix(".SFNSMono") {
            return "SF Mono"
        }
        if postScriptName.hasPrefix(".SFNS") {
            return "SF Pro"
        }
        return face.displayName ?? (monospaced ? "System Monospaced" : "System")
    }

    private var families: [String] {
        let installed = monospaced ? Self.monospaceFamilies : Self.installedFamilies
        let current = familyBinding.wrappedValue
        return current == defaultName || installed.contains(current) ? installed : installed + [current]
    }

    private var familyBinding: Binding<String> {
        Binding(
            get: {
                fontName == defaultName ? defaultName
                    : NSFont(name: fontName, size: defaultSize)?.familyName ?? fontName
            },
            set: { fontName = $0 },
        )
    }

    private var sizeBinding: Binding<Double> {
        Binding(get: { fontSize > 0 ? fontSize : defaultSize }, set: { fontSize = $0 })
    }
}
