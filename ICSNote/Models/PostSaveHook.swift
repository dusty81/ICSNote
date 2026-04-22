import Foundation

/// Maps to Claude Code's `--permission-mode` CLI flag. Controls whether
/// the headless `claude -p` invocation can write files or run bash without
/// prompting. For hooks running unattended, `default` usually fails — the
/// skill hits a permission prompt and falls back to chat output.
enum ClaudePermissionMode: String, Codable, CaseIterable, Identifiable {
    case acceptEdits       // auto-approve file edits, still prompts for bash
    case bypassPermissions // skip ALL permission prompts (bash + files)
    case plan              // plan mode: read-only, no writes at all
    case defaultMode       // prompt for everything (won't work unattended)

    var id: String { rawValue }

    /// CLI argument value for --permission-mode
    var cliValue: String {
        switch self {
        case .acceptEdits:       "acceptEdits"
        case .bypassPermissions: "bypassPermissions"
        case .plan:              "plan"
        case .defaultMode:       "default"
        }
    }

    var displayName: String {
        switch self {
        case .acceptEdits:       "Accept edits (recommended)"
        case .bypassPermissions: "Bypass all prompts (full access)"
        case .plan:              "Plan only (read-only)"
        case .defaultMode:       "Default (will fail unattended)"
        }
    }

    var explanation: String {
        switch self {
        case .acceptEdits:       "Auto-approves file writes/edits. Bash commands still require manual approval — which will block if the skill uses them."
        case .bypassPermissions: "Skips every permission prompt. Most permissive; use for trusted skills that need shell access."
        case .plan:              "Read-only. The skill can analyze the note but not modify anything."
        case .defaultMode:       "Prompts for approval on every write or command. Will hang or fall back to chat output in non-interactive mode — generally not useful for hooks."
        }
    }
}

enum HookTrigger: String, Codable, CaseIterable, Identifiable {
    case meeting
    case email
    case any

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meeting: "Meetings only"
        case .email:   "Emails only"
        case .any:     "Meetings and emails"
        }
    }
}

/// A post-save action. For v1, only Claude Code skill invocation is supported.
/// Webhooks and shell commands are planned for later phases.
enum PostSaveAction: Codable, Equatable {
    case claudeSkill(skillName: String, promptTemplate: String)
    // Future: .webhook(url:method:headers:body:), .shellCommand(executable:args:)

    var displayType: String {
        switch self {
        case .claudeSkill: "Claude Skill"
        }
    }
}

/// A single execution of a hook. Tracked in the ViewModel for UI feedback.
struct HookRun: Identifiable, Equatable, Sendable {
    enum Status: Sendable, Equatable {
        case running
        case success
        case failure(exitCode: Int32)
        case skipped(reason: String)   // e.g., claude binary missing
        case cancelled                 // user cancelled via stop button
    }

    let id: UUID
    let hookID: UUID
    let hookName: String
    let vaultName: String
    let noteFilename: String
    let startedAt: Date
    var finishedAt: Date?
    var status: Status
    /// The full prompt that was sent to `claude -p` (after variable substitution).
    var prompt: String = ""
    /// Standard output captured from the process. Always populated when finished.
    var stdout: String = ""
    /// Standard error captured from the process. Always populated when finished.
    var stderr: String = ""

    var isComplete: Bool {
        if case .running = status { return false }
        return true
    }

    var isFailure: Bool {
        if case .failure = status { return true }
        return false
    }
}

struct PostSaveHook: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var enabled: Bool
    var vaultID: UUID?           // nil = all vaults
    var trigger: HookTrigger
    var action: PostSaveAction
    /// Seconds before the running process is terminated. nil = use default.
    /// 0 = no timeout (let it run as long as needed).
    var timeoutSeconds: Double?
    /// Permission mode for the `claude -p` invocation. nil = use default.
    var permissionMode: ClaudePermissionMode?
    /// Space-separated list of tool names to allow without prompting,
    /// e.g., `"Read Edit Write mcp__outlook__search mcp__slack__*"`.
    /// Maps to Claude's `--allowedTools` flag. Additive to the permission mode.
    var allowedTools: String?

    init(
        id: UUID = UUID(),
        name: String = "",
        enabled: Bool = true,
        vaultID: UUID? = nil,
        trigger: HookTrigger = .any,
        action: PostSaveAction = .claudeSkill(skillName: "", promptTemplate: ""),
        timeoutSeconds: Double? = nil,
        permissionMode: ClaudePermissionMode? = nil,
        allowedTools: String? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.vaultID = vaultID
        self.trigger = trigger
        self.action = action
        self.timeoutSeconds = timeoutSeconds
        self.permissionMode = permissionMode
        self.allowedTools = allowedTools
    }

    /// Default permission mode for new hooks — `acceptEdits` is the sweet spot
    /// for note-editing skills while still requiring approval for shell access.
    static let defaultPermissionMode: ClaudePermissionMode = .acceptEdits

    var effectivePermissionMode: ClaudePermissionMode {
        permissionMode ?? Self.defaultPermissionMode
    }

    /// Default timeout for newly-created hooks. Tuned for Claude skills doing
    /// real work (git sync, summarization, API calls) — 30s was too short.
    static let defaultTimeoutSeconds: Double = 600  // 10 minutes

    var effectiveTimeoutSeconds: Double {
        timeoutSeconds ?? Self.defaultTimeoutSeconds
    }

    /// The skill name for Claude-skill actions, or nil for other action types.
    var skillName: String? {
        if case .claudeSkill(let name, _) = action { return name }
        return nil
    }

    /// True if this hook should fire for the given vault + content type.
    func matches(vaultID: UUID, noteType: HookTrigger) -> Bool {
        guard enabled else { return false }
        if let filterID = self.vaultID, filterID != vaultID { return false }
        return trigger == .any || trigger == noteType
    }
}
