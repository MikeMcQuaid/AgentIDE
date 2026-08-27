import Foundation

/// The web links inside a plain message, so a pull request URL in
/// the messages pane can be clicked rather than copied out by hand.
public enum MessageLinks {
    /// Every web link in the text, with the range it occupies.
    /// Detection rather than parsing: messages are command output
    /// and prose, and both put links in whatever they please.
    public static func links(in text: String) -> [(range: Range<String.Index>, url: URL)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let whole = NSRange(text.startIndex ..< text.endIndex, in: text)
        return detector.matches(in: text, range: whole).compactMap { match in
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text)
            else {
                return nil
            }

            return (range, url)
        }
    }
}
