import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            vaultsTab.tabItem { Label("Vaults", systemImage: "folder") }
            strippingTab.tabItem { Label("Stripping", systemImage: "scissors") }
            replacementsTab.tabItem { Label("Replacements", systemImage: "arrow.left.arrow.right") }
            notesTab.tabItem { Label("Notes", systemImage: "note.text") }
            emailTab.tabItem { Label("Email", systemImage: "envelope") }
            hooksTab.tabItem { Label("Hooks", systemImage: "bolt") }
        }
        .frame(width: 620, height: 520)
    }

    // MARK: - Vaults Tab

    @State private var discoveredVaults: [ObsidianVaultDiscovery.DiscoveredVault] = []

    private var vaultsTab: some View {
        VaultsTabView(settings: settings, discoveredVaults: $discoveredVaults)
    }

    // MARK: - Stripping

    private var strippingTab: some View {
        Form {
            Section("Meeting Info Stripping") {
                Toggle("Strip Zoom dial-in information", isOn: $settings.stripZoom)
                Toggle("Strip Microsoft Teams join information", isOn: $settings.stripTeams)
            }
            Section {
                Text("When enabled, conferencing boilerplate (dial-in numbers, meeting IDs, join links) is removed from the description. A small note is added indicating what was removed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Feedback") {
                Toggle("Play sound on successful conversion", isOn: $settings.playSuccessSound)
            }
        }
        .formStyle(.grouped).padding()
    }

    // MARK: - Replacements

    private var replacementsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Title Text Replacements").font(.headline)
            Text("Applied to meeting and email titles before generating the filename and markdown heading.")
                .font(.caption).foregroundStyle(.secondary)
            Table(of: TextReplacement.self) {
                TableColumn("Find") { replacement in
                    if let index = settings.textReplacements.firstIndex(where: { $0.id == replacement.id }) {
                        TextField("Find", text: $settings.textReplacements[index].find).textFieldStyle(.plain)
                    }
                }
                TableColumn("Replace With") { replacement in
                    if let index = settings.textReplacements.firstIndex(where: { $0.id == replacement.id }) {
                        TextField("Replace with", text: $settings.textReplacements[index].replace).textFieldStyle(.plain)
                    }
                }
                TableColumn("") { replacement in
                    Button {
                        settings.textReplacements.removeAll { $0.id == replacement.id }
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .width(30)
            } rows: {
                ForEach(settings.textReplacements) { replacement in
                    TableRow(replacement)
                }
            }
            HStack {
                Spacer()
                Button("Add Rule") { settings.textReplacements.append(TextReplacement()) }
            }
        }
        .padding()
    }

    // MARK: - Email

    private var emailTab: some View {
        Form {
            Section("Attachments") {
                Toggle("Save email attachments to vault", isOn: $settings.saveAttachments)
                if settings.saveAttachments {
                    Text("Attachments are saved to each vault's attachment subfolder (configured per-vault) and linked with [[wiki-links]]. Existing PDFs are embedded inline with ![[...]]. Inline signature images are skipped.")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("Convert to PDF", selection: $settings.pdfConversionMode) {
                        ForEach(PDFConversionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Text("For convertible files (.doc, .docx, .rtf, .html, .txt), save a PDF copy alongside the original and embed the PDF in the note. Ask mode prompts once per email drop.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Threads") {
                Toggle("Merge email threads", isOn: $settings.mergeEmailThreads)
                Text("When enabled, dropping a reply (RE:/FW:) appends to an existing note in the target vault with the same subject instead of creating a new file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Email Notes Template") {
                TextEditor(text: $settings.emailNotesTemplate)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    .frame(height: 60)
                Text("Markdown appended under the ## Notes heading in email notes. Leave blank for no template.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
    }

    // MARK: - Hooks

    private var hooksTab: some View {
        HooksTabView(settings: settings)
    }

    // MARK: - Notes

    private var notesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meeting Notes Template").font(.headline)
            Text("Markdown appended after the ## Notes heading in each meeting note.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $settings.notesTemplate)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        }
        .padding()
    }
}

// MARK: - Vaults Tab View

struct VaultsTabView: View {
    @Bindable var settings: AppSettings
    @Binding var discoveredVaults: [ObsidianVaultDiscovery.DiscoveredVault]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Obsidian Vaults").font(.headline)
                Spacer()
                Button("Rescan") { rescan() }
                    .controlSize(.small)
            }
            .padding([.horizontal, .top])

            Text("Check a vault to enable drops into it. Per-vault subfolders control where notes and attachments are saved.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(allVaultsForDisplay(), id: \.displayKey) { item in
                        VaultRowView(settings: settings, item: item)
                    }
                    if allVaultsForDisplay().isEmpty {
                        Text("No Obsidian vaults detected. Open a vault in Obsidian first, or add one manually:")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal)
                        Button("Browse for vault folder...") { browseAndAdd() }
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Button("Add vault manually...") { browseAndAdd() }
                    .controlSize(.small)
                Spacer()
            }
            .padding(8)

            Divider()

            // Drop zone layout picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Drop Zone Layout").font(.subheadline).fontWeight(.semibold)
                Picker("", selection: $settings.dropZoneLayout) {
                    ForEach(DropZoneLayout.allCases) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(layoutDescription)
                    .font(.caption).foregroundStyle(.secondary)

                if settings.effectiveDropZoneLayout != settings.dropZoneLayout {
                    Text("⚠︎ Too many vaults enabled for this layout — using Dropdown.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding()
        }
        .onAppear { rescan() }
    }

    private var layoutDescription: String {
        switch settings.dropZoneLayout {
        case .grid:      "A drop zone per vault. Best for 1-3 vaults (max 6)."
        case .dropdown:  "Single drop zone with a vault dropdown. Works for any number of vaults."
        case .segmented: "Single drop zone with a vault selector above. Best for 2-5 vaults."
        }
    }

    private func rescan() {
        discoveredVaults = ObsidianVaultDiscovery.discover()
    }

    /// Combine discovered Obsidian vaults with any manually-added vaults from settings.
    /// Each display item carries the VaultConfig if one exists, otherwise a discovered-only record.
    struct DisplayItem: Identifiable {
        var id: String { displayKey }
        let displayKey: String           // Stable across rescans (the vault path)
        let path: String
        let name: String
        var vaultConfig: VaultConfig?    // nil if not yet added to settings
    }

    private func allVaultsForDisplay() -> [DisplayItem] {
        var seenPaths: Set<String> = []
        var items: [DisplayItem] = []

        // First: settings-configured vaults (preserves user ordering)
        for vault in settings.vaults {
            seenPaths.insert(vault.path)
            items.append(DisplayItem(
                displayKey: vault.path,
                path: vault.path,
                name: vault.name,
                vaultConfig: vault
            ))
        }
        // Then: discovered vaults that aren't already configured
        for discovered in discoveredVaults where !seenPaths.contains(discovered.path) {
            items.append(DisplayItem(
                displayKey: discovered.path,
                path: discovered.path,
                name: discovered.name,
                vaultConfig: nil
            ))
        }
        return items
    }

    private func browseAndAdd() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select an Obsidian vault folder"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            guard !settings.vaults.contains(where: { $0.path == path }) else { return }
            let name = url.lastPathComponent
            settings.vaults.append(VaultConfig(name: name, path: path, enabled: true))
            if settings.activeVaultID == nil {
                settings.activeVaultID = settings.vaults.last?.id
            }
        }
    }
}

// MARK: - Vault Row

struct VaultRowView: View {
    @Bindable var settings: AppSettings
    let item: VaultsTabView.DisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                let isEnabled = item.vaultConfig?.enabled ?? false
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in setEnabled(newValue) }
                )) {
                    HStack(spacing: 8) {
                        if let vc = item.vaultConfig {
                            VaultIndicator(vault: vc, size: 12)
                        } else {
                            Circle().stroke(.secondary, lineWidth: 1).frame(width: 10, height: 10)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body).fontWeight(.medium)
                            Text(item.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                Spacer()
            }

            if let vc = item.vaultConfig, vc.enabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Meetings").frame(width: 90, alignment: .trailing)
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("subfolder (optional)", text: bindingForSubfolder(vaultID: vc.id))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    HStack {
                        Text("Emails").frame(width: 90, alignment: .trailing)
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("subfolder", text: bindingForEmailSubfolder(vaultID: vc.id))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    HStack {
                        Text("Attachments").frame(width: 90, alignment: .trailing)
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("subfolder", text: bindingForAttachmentSubfolder(vaultID: vc.id))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.3))
        )
        .padding(.horizontal)
    }

    private func setEnabled(_ enabled: Bool) {
        if let index = settings.vaults.firstIndex(where: { $0.path == item.path }) {
            settings.vaults[index].enabled = enabled
        } else if enabled {
            // Add a new VaultConfig for this discovered-but-not-yet-added vault
            let newVault = VaultConfig(name: item.name, path: item.path, enabled: true)
            settings.vaults.append(newVault)
            if settings.activeVaultID == nil {
                settings.activeVaultID = newVault.id
            }
        }
        // Pick a new active vault if the old one was disabled
        if let active = settings.activeVault, !active.enabled {
            settings.activeVaultID = settings.enabledVaults.first?.id
        }
        if settings.activeVaultID == nil {
            settings.activeVaultID = settings.enabledVaults.first?.id
        }
    }

    private func bindingForSubfolder(vaultID: UUID) -> Binding<String> {
        Binding(
            get: { settings.vault(id: vaultID)?.subfolder ?? "" },
            set: { newValue in
                if let idx = settings.vaults.firstIndex(where: { $0.id == vaultID }) {
                    settings.vaults[idx].subfolder = newValue
                }
            }
        )
    }

    private func bindingForEmailSubfolder(vaultID: UUID) -> Binding<String> {
        Binding(
            get: { settings.vault(id: vaultID)?.emailSubfolder ?? "" },
            set: { newValue in
                if let idx = settings.vaults.firstIndex(where: { $0.id == vaultID }) {
                    settings.vaults[idx].emailSubfolder = newValue
                }
            }
        )
    }

    private func bindingForAttachmentSubfolder(vaultID: UUID) -> Binding<String> {
        Binding(
            get: { settings.vault(id: vaultID)?.attachmentSubfolder ?? "" },
            set: { newValue in
                if let idx = settings.vaults.firstIndex(where: { $0.id == vaultID }) {
                    settings.vaults[idx].attachmentSubfolder = newValue
                }
            }
        )
    }
}

// MARK: - Hooks Tab

struct HooksTabView: View {
    @Bindable var settings: AppSettings
    @State private var editingHook: PostSaveHook?
    @State private var isNewHook = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Post-Save Hooks").font(.headline)
                Spacer()
                Button {
                    let draft = PostSaveHook(name: "New Hook")
                    editingHook = draft
                    isNewHook = true
                } label: {
                    Label("Add Hook", systemImage: "plus")
                }
                .controlSize(.small)
            }
            .padding([.horizontal, .top])

            Text("Run a Claude Code skill automatically after a note is saved. Useful for summarizing meetings, tagging emails, or kicking off downstream workflows.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if HookRunner.detectedClaudePath == nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("claude CLI not found — hooks will be silently skipped. Install via Homebrew or add to PATH.")
                        .font(.caption).foregroundStyle(.orange)
                }
                .padding(.horizontal).padding(.bottom, 8)
            }

            Divider()

            DisclosureGroup("Custom skill directories (\(settings.customSkillPaths.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add directories outside the standard Claude locations — scanned recursively for any SKILL.md.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(settings.customSkillPaths.enumerated()), id: \.offset) { index, path in
                        HStack {
                            Text(path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button {
                                settings.customSkillPaths.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.message = "Select a folder containing custom Claude skills"
                        if panel.runModal() == .OK, let url = panel.url {
                            let path = url.path
                            if !settings.customSkillPaths.contains(path) {
                                settings.customSkillPaths.append(path)
                            }
                        }
                    } label: {
                        Label("Add directory...", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if settings.hooks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.slash").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No hooks configured").foregroundStyle(.secondary)
                    Text("Add a hook to run a Claude skill after each note is saved.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(settings.hooks) { hook in
                            HookRowView(
                                settings: settings,
                                hook: hook,
                                onEdit: {
                                    editingHook = hook
                                    isNewHook = false
                                },
                                onDuplicate: {
                                    duplicateHook(hook)
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .sheet(item: $editingHook) { draft in
            HookEditorSheet(
                settings: settings,
                hook: draft,
                isNew: isNewHook,
                onSave: { updated in
                    if let idx = settings.hooks.firstIndex(where: { $0.id == updated.id }) {
                        settings.hooks[idx] = updated
                    } else {
                        settings.hooks.append(updated)
                    }
                    editingHook = nil
                },
                onCancel: { editingHook = nil },
                onDelete: {
                    settings.hooks.removeAll { $0.id == draft.id }
                    editingHook = nil
                }
            )
        }
    }

    /// Create a copy of a hook with a new UUID, "(Copy)" appended to the name,
    /// and insert it right after the original in the list.
    private func duplicateHook(_ original: PostSaveHook) {
        var copy = original
        // Give it a fresh identity — PostSaveHook.id is a `let`, so we rebuild
        copy = PostSaveHook(
            id: UUID(),
            name: original.name.isEmpty ? "Copy" : "\(original.name) (Copy)",
            enabled: original.enabled,
            vaultID: original.vaultID,
            trigger: original.trigger,
            action: original.action,
            timeoutSeconds: original.timeoutSeconds,
            permissionMode: original.permissionMode,
            allowedTools: original.allowedTools
        )
        if let idx = settings.hooks.firstIndex(where: { $0.id == original.id }) {
            settings.hooks.insert(copy, at: idx + 1)
        } else {
            settings.hooks.append(copy)
        }
    }
}

// MARK: - Hook Row

struct HookRowView: View {
    @Bindable var settings: AppSettings
    let hook: PostSaveHook
    let onEdit: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { hook.enabled },
                set: { newValue in
                    if let idx = settings.hooks.firstIndex(where: { $0.id == hook.id }) {
                        settings.hooks[idx].enabled = newValue
                    }
                }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(hook.name.isEmpty ? "Untitled" : hook.name)
                    .font(.body).fontWeight(.medium)
                    .foregroundStyle(hook.enabled ? Color.primary : Color.secondary)
                HStack(spacing: 4) {
                    Text(hook.trigger.displayName)
                    Text("·")
                    Text(vaultLabel)
                    Text("·")
                    Text(hook.action.displayType)
                    if case .claudeSkill(let skillName, _) = hook.action, !skillName.isEmpty {
                        Text("·")
                        Text("/\(skillName)").foregroundStyle(.tertiary)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDuplicate()
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.plain)
            .help("Duplicate this hook")
            .controlSize(.small)

            Button("Edit") { onEdit() }
                .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private var vaultLabel: String {
        guard let id = hook.vaultID else { return "all vaults" }
        return settings.vault(id: id)?.name ?? "(missing vault)"
    }
}

// MARK: - Hook Editor Sheet

struct HookEditorSheet: View {
    @Bindable var settings: AppSettings
    @State var hook: PostSaveHook
    let isNew: Bool
    let onSave: (PostSaveHook) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var discoveredSkills: [ClaudeSkillDiscovery.DiscoveredSkill] = []
    @State private var showVariablesHelp = false

    private var selectedSkillName: String {
        if case .claudeSkill(let name, _) = hook.action { return name }
        return ""
    }

    private var promptTemplate: String {
        if case .claudeSkill(_, let template) = hook.action { return template }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "Add Hook" : "Edit Hook")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                Form {
                    Section("General") {
                        TextField("Name", text: $hook.name)
                        Toggle("Enabled", isOn: $hook.enabled)
                    }

                    Section("When to run") {
                        Picker("Trigger", selection: $hook.trigger) {
                            ForEach(HookTrigger.allCases) { t in
                                Text(t.displayName).tag(t)
                            }
                        }

                        Picker("Vault", selection: Binding(
                            get: { hook.vaultID },
                            set: { hook.vaultID = $0 }
                        )) {
                            Text("All vaults").tag(UUID?.none)
                            ForEach(settings.enabledVaults) { v in
                                Text(v.name).tag(UUID?.some(v.id))
                            }
                        }
                    }

                    Section("Claude Skill") {
                        Picker("Skill", selection: Binding<String>(
                            get: { selectedSkillName },
                            set: { newName in
                                hook.action = .claudeSkill(skillName: newName, promptTemplate: promptTemplate)
                            }
                        )) {
                            Text("— pick a skill —").tag("")
                            ForEach(discoveredSkills) { skill in
                                Text("\(skill.name) (\(skill.source))").tag(skill.name)
                            }
                        }
                        if let selected = discoveredSkills.first(where: { $0.name == selectedSkillName }) {
                            Text(selected.description)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(4)
                        }

                        HStack {
                            Text("Prompt template")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Menu("Insert default") {
                                Button("Reference skill by path (reliable)") {
                                    let template = "Follow the instructions in {{skill_path}} and apply them to the note at {{file_path}}."
                                    hook.action = .claudeSkill(skillName: selectedSkillName, promptTemplate: template)
                                }
                                Button("Inline skill content (most reliable)") {
                                    let template = "Apply the following skill to the note at {{file_path}}:\n\n{{skill_content}}"
                                    hook.action = .claudeSkill(skillName: selectedSkillName, promptTemplate: template)
                                }
                                Button("Invoke by skill name (only for standard locations)") {
                                    let template = "Use the /{{skill_name}} skill on the note at {{file_path}}."
                                    hook.action = .claudeSkill(skillName: selectedSkillName, promptTemplate: template)
                                }
                            }
                            .controlSize(.small)
                            .disabled(selectedSkillName.isEmpty)
                        }
                        Text("Tip: skills outside ~/.claude/skills/ (like custom paths) can't be invoked by name. Use {{skill_path}} or {{skill_content}} instead.")
                            .font(.caption).foregroundStyle(.secondary)

                        TextEditor(text: Binding<String>(
                            get: { promptTemplate },
                            set: { newTemplate in
                                hook.action = .claudeSkill(skillName: selectedSkillName, promptTemplate: newTemplate)
                            }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        .frame(minHeight: 80, maxHeight: 150)

                        DisclosureGroup("Available variables", isExpanded: $showVariablesHelp) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(HookContext.availableVariables, id: \.self) { v in
                                    Text("{{\(v)}}").font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section("Permissions") {
                        Picker("Permission mode", selection: Binding<ClaudePermissionMode>(
                            get: { hook.effectivePermissionMode },
                            set: { hook.permissionMode = $0 }
                        )) {
                            ForEach(ClaudePermissionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        Text(hook.effectivePermissionMode.explanation)
                            .font(.caption).foregroundStyle(.secondary)

                        TextField("Allowed tools (optional)", text: Binding<String>(
                            get: { hook.allowedTools ?? "" },
                            set: { hook.allowedTools = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Text("Space-separated tool names pre-approved regardless of mode. Examples: `Read Edit Write Bash`, `mcp__outlook__*`, `mcp__slack__send_message`. Leave blank to only use the mode above.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Timeout") {
                        HStack {
                            TextField("Seconds", value: Binding<Double>(
                                get: { hook.effectiveTimeoutSeconds },
                                set: { hook.timeoutSeconds = $0 }
                            ), format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            Text("seconds (0 = no limit)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Skills that hit external APIs or do long work may need more than the default 10 minutes. Exit code 143 in the Activity window means the skill was terminated by this timeout.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            }

            Divider()

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { onDelete() }
                }
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(hook) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 540, height: 520)
        .onAppear {
            // Scan skills using the target vault as project path, if one is selected.
            let projectPath = hook.vaultID.flatMap { settings.vault(id: $0)?.path }
            discoveredSkills = ClaudeSkillDiscovery.discover(
                projectPath: projectPath,
                customPaths: settings.customSkillPaths
            )
        }
    }

    private var canSave: Bool {
        guard !hook.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if case .claudeSkill(let name, let template) = hook.action {
            return !name.isEmpty && !template.isEmpty
        }
        return false
    }
}
