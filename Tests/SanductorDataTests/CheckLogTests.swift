@testable import SanductorData
import Testing

struct CheckLogTests {
    @Test(arguments: [
        "[ERR] Could not connect",
        "[FAIL] Expected true",
        "[WARN] Deprecated option",
        "[ERROR] Could not compile",
        "[WARNING] Deprecated option",
        "[err] Could not connect",
        "[fail] Expected true",
        "[warn] Deprecated option",
        "npm ERR! code ERESOLVE",
        "npm WARN deprecated dependency",
        "Sources/A.swift:1:1: error: Missing argument",
        "Sources/A.swift:1:1: warning: Unused function",
        "error[E0425]: cannot find value",
        "app.ts(1,2): error TS2322: Type mismatch",
        "app.cs(1,2): warning CS0168: Unused variable",
        "  1:2  error  Missing semicolon",
        "  1:2  warning  Unused variable",
        "##[error]Could not compile",
        "##[warning]Deprecated option",
        "::error file=app.js,line=1::Missing semicolon",
        "::warning file=app.js,line=1::Unused variable",
        "Test case failed",
        "Check fails",
        "FAILURES: expected true",
        "2 errors generated",
        "2 warnings generated",
        "fatal: unable to access remote",
        "CRITICAL:root:Connection lost",
        "panic: runtime index out of range",
        "thread 'main' panicked at src/main.rs:1:2",
        "ValueError: invalid literal",
        "AssertionError",
        "Exception: unavailable",
        "java.lang.IllegalStateException: unavailable",
        "app.py:1: DeprecationWarning: Use the new API",
        "❌ Expected true",
        "❌\u{FE0F} Expected true",
        "✘ Test recorded an issue",
        "✖ Expected true",
        "✖️ Expected true",
        "⚠ Deprecated option",
        "⚠️ Deprecated option",
    ], [false, true])
    func `diagnostics survive cropping with their context`(diagnostic: String, decorated: Bool) {
        var lines = (1 ... 300).map { "line " + String($0) }
        lines[89] = diagnostic
        if decorated {
            lines = lines.map { "job\tstep\t2026-10-15T12:00:00Z \u{1B}[31m" + $0 + "\u{1B}[0m" }
        }
        let text = CheckLog.format(log: lines.joined(separator: "\n"), heading: "Run 1")
        #expect(text.contains(diagnostic))
        #expect(text.contains("line 87\nline 88\nline 89\n"))
        #expect(text.contains("line 91\nline 92\nline 93\n"))
        #expect(text.contains("line 80\n") == false)
        #expect(text.contains("line 100\n") == false)
        #expect(text.contains("\u{1B}") == false)
        #expect(text.contains("2026-10-15T") == false)
    }

    @Test(arguments: [
        "Compiling ErrorHandler.swift",
        "Compiling FailureTests.swift",
        "Compiling WarningHandler.swift",
        "Test testErrorHandling passed",
        "Test test_failure_handling passed",
        "warning_count=0",
        "failures_expected=false",
        "Configuring failover",
        "no_error: false",
        "no_warning: false",
        "no_exception: false",
        "noError: false",
        "noWarning: false",
        "NO_ERROR: false",
        "NO_WARNING: false",
    ])
    func `severity fragments in identifiers are cropped`(line: String) {
        var lines = (1 ... 300).map { "line " + String($0) }
        lines[89] = line
        #expect(CheckLog.format(log: lines.joined(separator: "\n"), heading: "Run 1").contains(line) == false)
    }

    @Test(arguments: ["[WARN]", "⚠️"])
    func `warning markers use the warning budget`(marker: String) {
        let lines = (1 ... 800).map { index in
            (heading: "", text: marker + " " + String(index) + String(repeating: "x", count: 40))
        }
        let kept = CheckLog.verdicts(in: lines).map(\.text)
        #expect(kept.contains(lines[0].text) == false)
        #expect(kept.contains(lines[799].text))
    }

    @Test(arguments: [
        [
            "Traceback (most recent call last):",
            "  File \"app.py\", line 10, in main",
            "    start()",
            "  File \"app.py\", line 20, in start",
            "    connect()",
            "  File \"app.py\", line 30, in connect",
            "    raise ValueError()",
            "ValueError: invalid configuration",
        ],
        [
            "java.lang.IllegalStateException: unavailable",
            "    at App.start(App.java:1)",
            "    at App.main(App.java:2)",
            "Caused by: connection closed",
            "    at Client.connect(Client.java:3)",
            "    at Client.start(Client.java:4)",
            "    ... 2 more",
        ],
        [
            "thread 'main' panicked at src/main.rs:1:2",
            "stack backtrace:",
            "   0: rust_begin_unwind",
            "             at library/std/src/panicking.rs:1:2",
            "   1: core::panicking::panic_fmt",
            "             at library/core/src/panicking.rs:1:2",
            "   2: app::main",
            "             at ./src/main.rs:1:2",
        ],
        [
            "panic: invalid index",
            "",
            "goroutine 1 [running]:",
            "example.org/app.(*Client).connect(0x123)",
            "\t/work/app/client.go:10 +0x12",
            "main.main()",
            "\t/work/app/main.go:20 +0x34",
            "",
            "goroutine 2 [runnable]:",
            "runtime.run()",
            "\t/usr/local/go/src/runtime/proc.go:30 +0x56",
        ],
        [
            "error[E0308]: mismatched types",
            " --> src/main.rs:2:3",
            "  |",
            "1 | fn main() {",
            "2 |     let value: u32 = \"text\";",
            "  |                      ^^^^^^ expected u32",
            "3 | }",
            "  |",
        ],
        [
            "[FAIL] Values differ",
            "  Expected: first value",
            "  Actual: second value",
            "",
            "--- expected",
            "+++ actual",
            "- first value",
            "+ second value",
        ],
    ])
    func `multiline diagnostics retain the complete adjacent block`(block: [String]) {
        var lines = (1 ... 300).map { "line " + String($0) }
        lines.replaceSubrange(80 ..< 80 + block.count, with: block)
        let text = CheckLog.format(log: lines.joined(separator: "\n"), heading: "Run 1")
        #expect(text.contains(block.joined(separator: "\n")))
        #expect(text.contains("line 70\n") == false)
        #expect(text.contains("line 110\n") == false)
    }

    @Test(arguments: ["Continuing build", "goroutine count: 10", "Calling main.main()", "main.main() complete"])
    func `ordinary progress stops extended diagnostic context`(progress: String) {
        let lines = ["[ERR] disconnected", "    at connect()", "    at start()", progress]
            + (1 ... 10).map { "    unrelated detail " + String($0) }
        let kept = CheckLog.verdicts(in: lines.map { ("job", $0) }).map(\.text)
        #expect(kept.contains(progress))
        #expect(kept.contains("    unrelated detail 1") == false)
    }

    @Test
    func `context stays in its job and step`() {
        let lines: [CheckLog.LogLine] = [
            ("another job", "    unrelated frame before"),
            ("job · test", "[ERR] disconnected"),
            ("job · cleanup", "    unrelated frame after"),
        ]
        let kept = CheckLog.verdicts(in: lines).map(\.text)
        #expect(kept.contains("[ERR] disconnected"))
        #expect(kept.contains("    unrelated frame before") == false)
        #expect(kept.contains("    unrelated frame after") == false)
    }

    @Test
    func `extended context is bounded and overlaps appear once`() {
        let frames = (1 ... 100).map { "    at frame" + String($0) + "()" }
        let lines = frames.reversed() + ["[ERR] disconnected", "[FAIL] assertion"] + frames
        let kept = CheckLog.verdicts(in: lines.map { ("job", $0) }).map(\.text)
        #expect(kept.contains("    at frame40()"))
        #expect(kept.contains("    at frame41()") == false)
        #expect(kept.filter { $0 == "[ERR] disconnected" } == ["[ERR] disconnected"])
        #expect(kept.filter { $0 == "[FAIL] assertion" } == ["[FAIL] assertion"])
    }
}
