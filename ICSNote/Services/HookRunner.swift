import Foundation
import os

/// Tracks live hook processes so the user can cancel them mid-flight.
actor HookProcessRegistry {
    static let shared = HookProcessRegistry()
    private var processes: [UUID: Process] = [:]
    private var userCancelled: Set<UUID> = []

    func register(_ runID: UUID, process: Process) {
        processes[runID] = process
    }

    /// Mark a run as user-cancelled and terminate its process.
    /// Returns `true` if there was a running process that was actually terminated.
    @discardableResult
    func terminate(_ runID: UUID) -> Bool {
        guard let process = processes[runID], process.isRunning else { return false }
        userCancelled.insert(runID)
        process.terminate()
        return true
    }

    func wasUserCancelled(_ runID: UUID) -> Bool {
        userCancelled.contains(runID)
    }

    func cleanup(_ runID: UUID) {
        processes.removeValue(forKey: runID)
        userCancelled.remove(runID)
    }
}

/// Fires post-save hooks asynchronously. Never blocks the caller.
enum HookRunner {

    private static let logger = Logger(subsystem: "com.icsnote.app", category: "HookRunner")

    /// Candidate paths for the `claude` CLI. First one that exists wins.
    /// If none exist, we log and skip Claude skill hooks rather than crashing.
    private static let claudeBinaryCandidates = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
    ]

    /// Fire every applicable hook on a detached task. Fire-and-forget.
    /// Optional callbacks report lifecycle events back to the caller (UI).
    /// Callbacks run on the main actor so the ViewModel can update directly.
    ///
    /// `customSkillPaths` is forwarded to `ClaudeSkillDiscovery` so hooks can
    /// resolve skills stored outside the standard Claude directories.
    static func fire(
        hooks: [PostSaveHook],
        context: HookContext,
        customSkillPaths: [String] = [],
        onStart: (@Sendable @MainActor (HookRun) -> Void)? = nil,
        onFinish: (@Sendable @MainActor (HookRun) -> Void)? = nil
    ) {
        let applicable = hooks.filter { $0.matches(vaultID: context.vaultID, noteType: context.noteType) }
        guard !applicable.isEmpty else { return }

        logger.info("Firing \(applicable.count, privacy: .public) hook(s) for \(context.filename, privacy: .public)")

        for hook in applicable {
            let runRecord = HookRun(
                id: UUID(),
                hookID: hook.id,
                hookName: hook.name,
                vaultName: context.vaultName,
                noteFilename: context.filename,
                startedAt: Date(),
                finishedAt: nil,
                status: .running
            )
            Task.detached(priority: .utility) {
                if let onStart {
                    await onStart(runRecord)
                }
                let finished = await execute(hook: hook, context: context, customSkillPaths: customSkillPaths, runRecord: runRecord)
                if let onFinish {
                    await onFinish(finished)
                }
            }
        }
    }

    // MARK: - Execution

    private static func execute(hook: PostSaveHook, context: HookContext, customSkillPaths: [String], runRecord: HookRun) async -> HookRun {
        switch hook.action {
        case .claudeSkill(_, let promptTemplate):
            return await runClaudeSkill(hook: hook, promptTemplate: promptTemplate, context: context, customSkillPaths: customSkillPaths, runRecord: runRecord)
        }
    }

    private static func runClaudeSkill(hook: PostSaveHook, promptTemplate: String, context: HookContext, customSkillPaths: [String], runRecord: HookRun) async -> HookRun {
        var result = runRecord

        guard let claudePath = firstExistingPath(claudeBinaryCandidates) else {
            logger.error("Hook \(hook.name, privacy: .public): claude CLI not found in standard locations")
            result.status = .skipped(reason: "claude CLI not found")
            result.finishedAt = Date()
            return result
        }

        // Resolve the skill so we can substitute {{skill_path}} / {{skill_content}}
        let skillName = hook.skillName ?? ""
        let discovered = ClaudeSkillDiscovery.discover(
            projectPath: context.vaultPath,
            customPaths: customSkillPaths
        )
        let skill = discovered.first { $0.name == skillName }
        let skillPath = skill?.path.path ?? ""
        let skillContent: String = {
            guard let skill else { return "" }
            return (try? String(contentsOf: skill.path, encoding: .utf8)) ?? ""
        }()

        // First pass: context variables (file_path, vault_name, etc.)
        var prompt = context.substitute(in: promptTemplate)
        // Second pass: skill-specific variables
        prompt = prompt
            .replacingOccurrences(of: "{{skill_name}}", with: skillName)
            .replacingOccurrences(of: "{{skill_path}}", with: skillPath)
            .replacingOccurrences(of: "{{skill_content}}", with: skillContent)
        result.prompt = prompt

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        var args = [
            "-p", prompt,
            "--permission-mode", hook.effectivePermissionMode.cliValue,
        ]
        if let allowed = hook.allowedTools?.trimmingCharacters(in: .whitespacesAndNewlines),
           !allowed.isEmpty {
            args.append(contentsOf: ["--allowedTools", allowed])
        }
        process.arguments = args
        // cd into the vault so project-level skills (.claude/skills/) are discovered
        process.currentDirectoryURL = URL(fileURLWithPath: context.vaultPath)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            logger.error("Hook \(hook.name, privacy: .public): failed to launch claude: \(error.localizedDescription, privacy: .public)")
            result.stderr = "Failed to launch: \(error.localizedDescription)"
            result.status = .failure(exitCode: -1)
            result.finishedAt = Date()
            return result
        }

        // Register with the cancellation registry so the user can stop it
        await HookProcessRegistry.shared.register(runRecord.id, process: process)

        // Enforce the configured timeout. 0 means "no timeout — let it run".
        let timeout = hook.effectiveTimeoutSeconds
        let timeoutTask: Task<Void, Error>?
        if timeout > 0 {
            timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                    logger.error("Hook \(hook.name, privacy: .public): timed out after \(timeout, privacy: .public)s, terminated")
                }
            }
        } else {
            timeoutTask = nil
        }

        // Block the async task on the process exit
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
        timeoutTask?.cancel()

        // Capture both streams regardless of outcome — the user needs to see
        // what the skill actually did even when the exit code is 0.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""
        var errText = String(data: errData, encoding: .utf8) ?? ""

        let exitCode = process.terminationStatus
        let wasSignaled = process.terminationReason == .uncaughtSignal && exitCode == 143
        let wasUserCancelled = await HookProcessRegistry.shared.wasUserCancelled(runRecord.id)
        await HookProcessRegistry.shared.cleanup(runRecord.id)
        result.finishedAt = Date()

        // Distinguish user cancellation from our timeout — both end with SIGTERM (143)
        if wasSignaled && errText.isEmpty {
            if wasUserCancelled {
                errText = "Cancelled by user."
            } else {
                errText = "Timed out after \(Int(timeout))s. Increase timeout in hook settings if the skill needs more time."
            }
        }

        // Cap each stream at 100KB for memory sanity
        result.stdout = truncate(outText, limit: 100_000)
        result.stderr = truncate(errText, limit: 100_000)

        if exitCode == 0 {
            logger.info("Hook \(hook.name, privacy: .public): completed (\(outText.count, privacy: .public) bytes stdout)")
            result.status = .success
        } else if wasUserCancelled {
            logger.info("Hook \(hook.name, privacy: .public): cancelled by user")
            result.status = .cancelled
        } else {
            logger.error("Hook \(hook.name, privacy: .public): exit \(exitCode, privacy: .public) \(errText, privacy: .public)")
            result.status = .failure(exitCode: exitCode)
        }
        return result
    }

    /// Cancel a running hook by its run ID. Safe to call when the run is
    /// already finished — will be a no-op.
    static func cancel(runID: UUID) async {
        let terminated = await HookProcessRegistry.shared.terminate(runID)
        if terminated {
            logger.info("Cancelled hook run \(runID.uuidString, privacy: .public)")
        }
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "\n… [truncated, \(text.count - limit) more bytes]"
    }

    // MARK: - Helpers

    private static func firstExistingPath(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Returns the currently detected path to the `claude` CLI, if any.
    /// Exposed so the Settings UI can tell the user whether hooks will work.
    static var detectedClaudePath: String? {
        firstExistingPath(claudeBinaryCandidates)
    }
}
