#if os(iOS)
    import SwiftTerm
    import UIKit

    final class PhoneKeyboard: UIInputView {
        // MARK: Lifecycle

        init(terminal: PhoneTerminalView, expanded: Bool = false) {
            self.terminal = terminal
            self.expanded = expanded
            super.init(frame: .zero, inputViewStyle: .keyboard)
            allowsSelfSizing = true
            let rows = UIStackView(arrangedSubviews: expanded ? extraRows() : [accessoryRow()])
            rows.axis = .vertical
            rows.spacing = Self.spacing
            rows.distribution = .fillEqually
            rows.translatesAutoresizingMaskIntoConstraints = false
            addSubview(rows)
            NSLayoutConstraint.activate([
                rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
                rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
                rows.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
                rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding),
                heightAnchor.constraint(equalToConstant: intrinsicContentSize.height),
            ])
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateModifiers),
                name: .terminalViewControlModifierReset,
                object: terminal,
            )
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("Use init(terminal:expanded:)")
        }

        deinit { repeatTask?.cancel() }

        // MARK: Internal

        override var intrinsicContentSize: CGSize {
            let count: CGFloat = expanded ? Self.extraRowCount : 1
            return CGSize(
                width: UIView.noIntrinsicMetric,
                height: count * Self.keyHeight + (count - 1) * Self.spacing + Self.padding + Self.padding,
            )
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                repeatTask?.cancel()
            }
        }

        @objc
        func updateModifiers() {
            controlButton?.isSelected = terminal?.controlModifier ?? false
            shiftButton?.isSelected = terminal?.shiftModifier ?? false
        }

        // MARK: Private

        private static let keyHeight: CGFloat = 44
        private static let padding: CGFloat = 8
        private static let spacing: CGFloat = 4
        private static let extraRowCount: CGFloat = 5
        private static let functionCount = 10
        private static let functionsPerRow = 5
        private static let repeatDelayMilliseconds = 600
        private static let repeatInterval: Duration = .milliseconds(100)

        private weak var terminal: PhoneTerminalView?
        private let expanded: Bool
        private var controlButton: UIButton?
        private var shiftButton: UIButton?
        private var repeatTask: Task<Void, Never>?

        private func accessoryRow() -> UIStackView {
            let control = button("Ctrl", image: "control") { [weak self] _ in
                self?.terminal?.controlModifier.toggle()
                self?.updateModifiers()
            }
            controlButton = control
            let shift = button("Shift", image: "shift") { [weak self] _ in
                self?.terminal?.shiftModifier.toggle()
                self?.updateModifiers()
            }
            shiftButton = shift
            return row([
                key("Esc", bytes: EscapeSequences.cmdEsc), control, shift,
                key("Tab", bytes: EscapeSequences.cmdTab, image: "arrow.right.to.line.compact"),
                key("Left", bytes: EscapeSequences.moveLeftNormal, image: "arrow.left", repeats: true),
                key("Down", bytes: EscapeSequences.moveDownNormal, image: "arrow.down", repeats: true),
                key("Up", bytes: EscapeSequences.moveUpNormal, image: "arrow.up", repeats: true),
                key("Right", bytes: EscapeSequences.moveRightNormal, image: "arrow.right", repeats: true),
                button("Extra keys", image: "keyboard") { [weak self] _ in
                    guard let target = self?.terminal else {
                        return
                    }

                    target.inputView = target.inputView == nil ? PhoneKeyboard(terminal: target, expanded: true) : nil
                    target.reloadInputViews()
                },
            ])
        }

        private func extraRows() -> [UIStackView] {
            let functions = (0 ..< Self.functionCount).map { index in
                key("F" + String(index + 1), bytes: EscapeSequences.cmdF[index])
            }
            let symbols = ["[]{}<>&", "+-*=%`\\"].map { text in
                text.map { character in
                    button(String(character)) { [weak self] _ in self?.terminal?.insertText(String(character)) }
                }
            }
            return [
                row(Array(functions.prefix(Self.functionsPerRow))),
                row(Array(functions.suffix(Self.functionsPerRow))),
                row(symbols[0] + [key("Ins", bytes: EscapeSequences.cmdInsert)]),
                row(symbols[1] + [key("Delete", bytes: EscapeSequences.cmdDelKey, image: "delete.forward")]),
                row([
                    key("Home", bytes: EscapeSequences.moveHomeNormal),
                    key("End", bytes: EscapeSequences.moveEndNormal),
                    key("PgUp", bytes: EscapeSequences.cmdPageUp),
                    key("PgDn", bytes: EscapeSequences.cmdPageDown),
                ]),
            ]
        }

        private func row(_ buttons: [UIButton]) -> UIStackView {
            let stack = UIStackView(arrangedSubviews: buttons)
            stack.spacing = Self.spacing
            stack.distribution = .fillEqually
            return stack
        }

        private func button(_ title: String, image: String? = nil, action: @escaping (Bool) -> Void) -> UIButton {
            let button = UIButton(type: .system)
            button.configuration = .glass()
            button.configurationUpdateHandler = { button in
                var config = button.isSelected ? UIButton.Configuration.prominentGlass() : .glass()
                config.title = image == nil ? title : nil
                config.image = image.flatMap { UIImage(systemName: $0) }
                config.contentInsets = NSDirectionalEdgeInsets(
                    top: Self.spacing, leading: Self.spacing, bottom: Self.spacing, trailing: Self.spacing,
                )
                config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var result = attributes
                    result.font = .preferredFont(forTextStyle: .caption1)
                    return result
                }
                button.configuration = config
            }
            button.accessibilityLabel = title
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            let activation = MobileKeyActivation { held in
                UIDevice.current.playInputClick()
                action(held)
            }
            button.addAction(UIAction { _ in activation.touchDown() }, for: .touchDown)
            button.addAction(UIAction { _ in activation.activate() }, for: .primaryActionTriggered)
            button.addAction(UIAction { _ in activation.cancelTouch() }, for: [.touchUpOutside, .touchCancel])
            return button
        }

        private func key(_ title: String, bytes: [UInt8], image: String? = nil, repeats: Bool = false) -> UIButton {
            let button = button(title, image: image) { [weak self] held in
                guard let self, let terminal else {
                    return
                }

                repeatTask?.cancel()
                let modified = MobileTerminalKeys.modified(
                    bytes, shift: terminal.shiftModifier, control: terminal.controlModifier,
                )
                terminal.send(modified)
                terminal.resetModifiers()
                if repeats, held {
                    repeatTask = Task { [weak terminal] in
                        do {
                            try await Task.sleep(for: .milliseconds(Self.repeatDelayMilliseconds))
                            while Task.isCancelled == false {
                                terminal?.send(modified)
                                try await Task.sleep(for: Self.repeatInterval)
                            }
                        } catch { /* Releasing the key stops its repeats. */ }
                    }
                }
            }
            button.addAction(UIAction { [weak self] _ in self?.repeatTask?.cancel() }, for: [
                .touchUpInside, .touchUpOutside, .touchCancel,
            ])
            return button
        }
    }
#endif
