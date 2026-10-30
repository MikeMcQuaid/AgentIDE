@testable import SanductorData
import Testing

struct CheckLogBudgetTests {
    @Test
    func `oversized warning context keeps its marker and nearest details`() {
        let context = (1 ... 40).map { "    detail " + String($0) + String(repeating: "é", count: 250) }
        let lines = ["[WARN] Deprecated option"] + context
        let kept = CheckLog.verdicts(in: lines.map { ("job", $0) }).map(\.text)
        #expect(kept.contains(lines[0]))
        #expect(kept.contains(context[0]))
        #expect(kept.contains(context[39]) == false)
        #expect(kept.filter { lines.contains($0) }.reduce(0) { $0 + $1.utf8.count + 1 } <= CheckLog.logTailBytes)
    }

    @Test
    func `warning context cannot consume the error allowance`() {
        let lines = (1 ... 400).map { "error: " + String($0) + String(repeating: "x", count: 100) }
            + ["progress", "progress", "progress", "progress", "[WARN] Deprecated option"]
            + (1 ... 40).map { "    detail " + String($0) + String(repeating: "x", count: 500) }
        let kept = CheckLog.verdicts(in: lines.map { ("job", $0) }).map(\.text)
        #expect(kept.contains(lines[0]))
        #expect(kept.contains(lines[399]))
        #expect(kept.contains("[WARN] Deprecated option"))
    }

    @Test(arguments: [100, 2_000])
    func `the final paste budget prioritises errors over warnings and context`(contextLength: Int) {
        var lines = (1 ... 400).map { "warning: " + String($0) + String(repeating: "x", count: 100) }
        lines[199] = "job\tTest\terror: important middle diagnostic"
        lines[200] = "job\tTest\t    useful detail " + String(repeating: "x", count: contextLength)
        let text = CheckLog.format(log: lines.joined(separator: "\n"), heading: "Run 1", byteLimit: 1_024)
        #expect(text.contains("important middle diagnostic"))
        #expect(text.contains("useful detail") == (contextLength == 100))
        #expect(text.contains("warning:") == false)
        #expect(text.contains("log shortened"))
        #expect(text.utf8.count <= 1_024)
    }
}
