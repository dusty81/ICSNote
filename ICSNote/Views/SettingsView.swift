import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            vaultTab.tabItem { Label("Vault", systemImage: "folder") }
            strippingTab.tabItem { Label("Stripping", systemImage: "scissors") }
            replacementsTab.tabItem { Label("Replacements", systemImage: "arrow.left.arrow.right") }
            notesTab.tabItem { Label("Notes", systemImage: "note.text") }
        }
        .frame(width: 500, height: 350)
    }

    private var vaultTab: some View {
        Form {
            Section("Obsidian Vault") {
                HStack {
                    TextField("Vault path", text: .constant(settings.vaultPath))
                        .textFieldStyle(.roundedBorder).disabled(true)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.message = "Select your Obsidian vault folder"
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.vaultPath = url.path
                        }
                    }
                }
                TextField("Subfolder (optional)", text: $settings.subfolder)
                    .textFieldStyle(.roundedBorder)
                Text("Folder within vault — created automatically if it doesn't exist.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
    }

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
        }
        .formStyle(.grouped).padding()
    }

    private var replacementsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Title Text Replacements").font(.headline)
            Text("Applied to the meeting title before generating the filename and markdown heading.")
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

    private var notesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes Template").font(.headline)
            Text("Markdown appended after the ## Notes heading in each generated file.")
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
