import Foundation

public extension AgentRunner {
    /// Builds a restricted invocation over the captured diff.
    func reviewCommand(
        executable _: String,
        promptFile _: String,
        schemaFile _: String,
        options _: AgentLaunchOptions = AgentLaunchOptions(),
    ) -> String {
        // Test and third-party runners must opt into local review.
        "exit 1"
    }

    /// Reads the completed structured response.
    func reviewOutput(_ output: String) -> String {
        output
    }
}

public extension ClaudeCodeRunner {
    /// Builds a restricted invocation over the captured diff.
    func reviewCommand(
        executable: String,
        promptFile: String,
        schemaFile: String,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) -> String {
        [
            executable, "--safe-mode", "--tools", "", "--strict-mcp-config",
            "--mcp-config", "{\"mcpServers\":{}}", "--disallowedTools", "mcp__*",
            "--no-session-persistence", "--output-format", "json",
        ]
        .map(\.shellQuoted)
        .joined(separator: " ")
        + " " + optionArguments(model: options.model?.shellQuoted, effort: options.effort?.shellQuoted)
        + " --json-schema \"$(cat " + schemaFile.shellQuoted + ")\" -p < " + promptFile.shellQuoted
    }

    /// Reads the completed structured response.
    func reviewOutput(_ output: String) throws -> String {
        guard output.utf8.count <= LocalReviewInput.byteLimit else {
            throw SessionServiceError("The reviewer returned too much text. Review a smaller scope.")
        }
        guard let envelope = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              envelope["type"] as? String == "result",
              envelope["is_error"] as? Bool != true,
              let findings = envelope["structured_output"] as? [String: Any]
        else {
            throw SessionServiceError("Claude did not return a completed structured review.")
        }

        return try String(bytes: JSONSerialization.data(withJSONObject: findings), encoding: .utf8) ?? ""
    }
}

public extension CodexRunner {
    /// Builds a restricted invocation over the captured diff.
    func reviewCommand(
        executable: String,
        promptFile: String,
        schemaFile: String,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) -> String {
        let disabled = [
            "shell_tool", "unified_exec", "code_mode_host", "multi_agent", "apps", "plugins", "hooks",
            "browser_use", "computer_use", "image_generation", "tool_suggest", "skill_search",
            "shell_snapshot", "workspace_dependencies", "view_image",
        ].flatMap { ["--disable", $0] }
        return ([
            executable, "--ask-for-approval", "never", "exec", "--ignore-user-config",
            "--sandbox", "read-only", "--skip-git-repo-check", "--color", "never",
            "-c", "web_search=\"disabled\"", "-c", "project_doc_max_bytes=0",
            "--output-schema", schemaFile,
        ] + disabled)
            .map(\.shellQuoted)
            .joined(separator: " ")
            + " " + optionArguments(model: options.model?.shellQuoted, effort: options.effort?.shellQuoted)
            + " - < " + promptFile.shellQuoted
    }
}
