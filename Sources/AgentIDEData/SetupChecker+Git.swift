import Foundation

extension SetupChecker {
    func gitConfiguration() async -> (issues: [SetupIssue], signingConfigured: Bool) {
        let result = try? await service.git.git(
            ["config", "--global", "--get-regexp", "^(user\\.(name|email|signingkey)|gpg\\..*|commit\\.gpgsign)$"],
            in: nil,
            allowFailure: true,
        )
        let values = Dictionary((result?.standardOutput.split(separator: "\n") ?? []).compactMap { line in
            let pair = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            return pair.count > 1 ? (String(pair[0]), String(pair[1])) : nil
        }) { _, last in last }
        var issues = [SetupIssue]()
        if ["user.name", "user.email"].contains(where: { values[$0]?.isEmpty != false }) {
            issues.append(SetupIssue(
                step: .gitIdentity,
                title: "Set your Git identity",
                explanation: "Git needs your name and email to commit. Replace the examples with your own details.",
                commands: """
                git config --global user.name 'Your Name'
                git config --global user.email 'you@example.com'
                sv build
                """,
                alternative: "",
            ))
        }
        return await (issues, requiresSignedCommits ? signingConfigured(values) : true)
    }

    private func signingConfigured(_ values: [String: String]) async -> Bool {
        let format = values["gpg.format"] ?? "openpgp"
        if format == "ssh" {
            guard let key = values["user.signingkey"], key.isEmpty == false else {
                return false
            }

            let signer = values["gpg.ssh.program"] ?? "/usr/bin/ssh-keygen"
            let executable = try? await service.processes.run(
                ["/bin/zsh", "-fc", "command -v " + signer.shellQuoted], workingDirectory: nil, environment: [:],
            )
            guard executable?.succeeded == true else {
                return false
            }

            if key.hasPrefix("key::") {
                return values["gpg.ssh.program"] != nil ? true : await agentHasKey(String(key.dropFirst("key::".count)))
            }
            let path = key.hasPrefix("~/") ? FileManager.default.homeDirectoryForCurrentUser.path
                + "/" + key.dropFirst("~/".count) : key
            guard FileManager.default.isReadableFile(atPath: path) else {
                return false
            }

            if values["gpg.ssh.program"] != nil || path.hasSuffix(".pub") == false
                || FileManager.default.isReadableFile(atPath: String(path.dropLast(".pub".count)))
            {
                return true
            }
            return await agentHasKey((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
        }
        guard ["openpgp", "x509"].contains(format),
              let key = values["user.signingkey"] ?? values["user.email"], key.isEmpty == false
        else {
            return false
        }

        let result = try? await service.processes.run(
            [
                values["gpg." + format + ".program"] ?? values["gpg.program"] ?? (format == "x509" ? "gpgsm" : "gpg"),
                "--batch", "--with-colons", "--list-secret-keys", key,
            ],
            workingDirectory: nil,
            environment: [:],
        )
        return result?.succeeded == true && result?.standardOutput.isEmpty == false
    }

    private func agentHasKey(_ key: String) async -> Bool {
        let keyFieldCount = 2
        let fields = key.split(whereSeparator: \.isWhitespace).prefix(keyFieldCount)
        guard fields.count == keyFieldCount else {
            return false
        }

        let result = try? await service.processes.run(
            ["/usr/bin/ssh-add", "-L"], workingDirectory: nil, environment: [:],
        )
        return result?.succeeded == true && result?.standardOutput.split(separator: "\n").contains { line in
            line.split(whereSeparator: \.isWhitespace).prefix(keyFieldCount).elementsEqual(fields)
        } == true
    }
}
