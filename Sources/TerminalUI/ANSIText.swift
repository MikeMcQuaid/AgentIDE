import SwiftUI

// SGR parsing is inherently numeric and tabular: the codes and the
// palette are the ANSI protocol's own constants, and naming each one
// or splitting the dispatch would only restate the specification
// less recognisably.
// swiftlint:disable no_magic_numbers cyclomatic_complexity large_tuple

/// Converts SGR-styled terminal text (what `capture-pane -e` emits:
/// plain text plus colour and style escapes, never cursor movement)
/// into an attributed string, so the scrollback viewer keeps the
/// pane's colours as ordinary selectable text.
enum ANSIText {
    // MARK: Internal

    /// The styled text; unknown escape sequences are stripped.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var run = ""
        var state = Style()
        var characters = text.makeIterator()
        while let character = characters.next() {
            guard character == "\u{1B}" else {
                run.append(character)
                continue
            }

            state.flush(&run, into: &result)
            consumeEscape(&characters, into: &state)
        }
        state.flush(&run, into: &result)
        return result
    }

    /// The text with every escape sequence removed, for emptiness
    /// checks.
    static func plain(_ text: String) -> String {
        String(attributed(text).characters)
    }

    // MARK: Private

    /// The active SGR style, applied to each finished run.
    private struct Style {
        var foreground: Color?
        var background: Color?
        var isBold = false
        var isUnderlined = false

        mutating func flush(_ run: inout String, into result: inout AttributedString) {
            guard run.isEmpty == false else {
                return
            }

            var piece = AttributedString(run)
            piece.foregroundColor = foreground
            piece.backgroundColor = background
            if isBold {
                piece.font = CodeStyle.font.bold()
            }
            if isUnderlined {
                piece.underlineStyle = .single
            }
            result += piece
            run = ""
        }
    }

    /// Consumes one escape sequence, applying SGR parameters and
    /// discarding everything else (operating system commands end at
    /// BEL, control sequences at their final letter).
    private static func consumeEscape(
        _ characters: inout String.Iterator,
        into state: inout Style,
    ) {
        switch characters.next() {
        case "[":
            var parameters = ""
            while let character = characters.next() {
                if character.isLetter || character == "~" {
                    if character == "m" {
                        apply(parameters, to: &state)
                    }
                    return
                }
                parameters.append(character)
            }

        case "]":
            while let character = characters.next(), character != "\u{07}" {
                // Discard until the bell terminator.
            }

        default:
            break
        }
    }

    /// Applies one SGR parameter list to the style.
    private static func apply(_ parameters: String, to state: inout Style) {
        var codes = parameters.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        if codes.isEmpty {
            codes = [0]
        }
        var index = 0
        while index < codes.count {
            index += applyCode(at: index, of: codes, to: &state)
        }
    }

    /// Applies the code at `index`, returning how many parameters it
    /// consumed.
    private static func applyCode(at index: Int, of codes: [Int], to state: inout Style) -> Int {
        switch codes[index] {
        case 0:
            state = Style()

        case 1:
            state.isBold = true

        case 4:
            state.isUnderlined = true

        case 22:
            state.isBold = false

        case 24:
            state.isUnderlined = false

        case 30 ... 37:
            state.foreground = standard(codes[index] - 30)

        case 39:
            state.foreground = nil

        case 40 ... 47:
            state.background = standard(codes[index] - 40)

        case 49:
            state.background = nil

        case 90 ... 97:
            state.foreground = standard(codes[index] - 90 + 8)

        case 100 ... 107:
            state.background = standard(codes[index] - 100 + 8)

        case 38,
             48:
            let (colour, consumed) = extended(codes, from: index)
            if codes[index] == 38 {
                state.foreground = colour
            } else {
                state.background = colour
            }
            return consumed

        default:
            break
        }
        return 1
    }

    /// A 256-colour or truecolour parameter run, returning the
    /// colour and how many parameters it spanned.
    private static func extended(_ codes: [Int], from index: Int) -> (Color?, Int) {
        guard index + 1 < codes.count else {
            return (nil, 2)
        }

        switch codes[index + 1] {
        case 5 where index + 2 < codes.count:
            return (indexed(codes[index + 2]), 3)

        case 2 where index + 4 < codes.count:
            let colour = Color(
                red: Double(codes[index + 2]) / 255,
                green: Double(codes[index + 3]) / 255,
                blue: Double(codes[index + 4]) / 255,
            )
            return (colour, 5)

        default:
            return (nil, 2)
        }
    }

    /// The xterm 256-colour palette: the 16 named colours, a 6x6x6
    /// cube, then a grey ramp.
    private static func indexed(_ index: Int) -> Color? {
        switch index {
        case 0 ... 15:
            return standard(index)

        case 16 ... 231:
            let steps: [Double] = [0, 95, 135, 175, 215, 255]
            let value = index - 16
            return Color(
                red: steps[value / 36] / 255,
                green: steps[value / 6 % 6] / 255,
                blue: steps[value % 6] / 255,
            )

        case 232 ... 255:
            let grey = Double(8 + (index - 232) * 10) / 255
            return Color(red: grey, green: grey, blue: grey)

        default:
            return nil
        }
    }

    /// The 16 named colours, tuned to read on both terminal themes.
    private static func standard(_ index: Int) -> Color? {
        let table: [(Double, Double, Double)] = [
            (0.2, 0.2, 0.2), (0.8, 0.1, 0.1), (0.1, 0.6, 0.1), (0.65, 0.5, 0),
            (0.15, 0.35, 0.85), (0.7, 0.25, 0.7), (0, 0.6, 0.6), (0.65, 0.65, 0.65),
            (0.45, 0.45, 0.45), (1, 0.3, 0.3), (0.25, 0.8, 0.25), (0.85, 0.75, 0.2),
            (0.35, 0.55, 1), (0.9, 0.45, 0.9), (0.2, 0.8, 0.8), (0.9, 0.9, 0.9),
        ]
        guard table.indices.contains(index) else {
            return nil
        }

        let (red, green, blue) = table[index]
        return Color(red: red, green: green, blue: blue)
    }
}

// swiftlint:enable no_magic_numbers cyclomatic_complexity large_tuple
