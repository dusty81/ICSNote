import SwiftUI

struct HistoryView: View {
    @Bindable var viewModel: AppViewModel
    @State private var searchText = ""
    @State private var filterType: HookTrigger? = nil

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            typeFilter
            Divider()
            content
            footer
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search notes\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
    }

    // MARK: - Filter

    private var typeFilter: some View {
        Picker("Type", selection: $filterType) {
            Text("All").tag(HookTrigger?.none)
            Text("Meetings").tag(HookTrigger?.some(.meeting))
            Text("Emails").tag(HookTrigger?.some(.email))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filteredHistory.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.title).foregroundStyle(.secondary)
                Text(viewModel.allHistory.isEmpty ? "No notes yet" : "No matching notes")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredHistory) { conversion in
                        historyRow(conversion)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(viewModel.allHistory.count) note\(viewModel.allHistory.count == 1 ? "" : "s")")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            if viewModel.missingHistoryCount > 0 {
                Button("Remove \(viewModel.missingHistoryCount) unavailable") {
                    viewModel.removeMissingHistoryEntries()
                }
                .font(.caption2).foregroundStyle(.orange)
                .buttonStyle(.plain)
                Text("\u{00B7}").font(.caption2).foregroundStyle(.secondary)
            }
            Button("Clear All") {
                viewModel.clearHistory()
            }
            .font(.caption2).foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Row

    private func historyRow(_ conversion: RecentConversion) -> some View {
        let fileExists = FileManager.default.fileExists(atPath: conversion.outputURL.path)
        let eligibleHooks = contextMenuHooks(for: conversion)

        return HStack(spacing: 10) {
            Image(systemName: conversion.noteType == .email ? "envelope" : "calendar")
                .font(.caption).foregroundStyle(fileExists ? .secondary : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(conversion.filename.replacingOccurrences(of: ".md", with: ""))
                        .font(.caption).fontWeight(.medium).lineLimit(1)
                        .foregroundStyle(fileExists ? Color.primary : Color.secondary)
                    if !fileExists {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(Color.orange)
                    }
                }
                HStack(spacing: 4) {
                    if let vaultID = conversion.vaultID,
                       let vault = viewModel.settings.vault(id: vaultID) {
                        VaultIndicator(vault: vault, size: 8)
                        Text(vault.name).foregroundStyle(.secondary)
                        Text("\u{00B7}")
                    } else if let name = conversion.vaultName {
                        Text(name).foregroundStyle(.secondary)
                        Text("\u{00B7}")
                    }
                    Text(conversion.timestamp, format: .dateTime.month().day().hour().minute())
                    if let stripped = conversion.strippedInfo {
                        Text("\u{00B7}")
                        Text(stripped)
                    }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            if viewModel.settings.isVaultConfigured && fileExists {
                Button { viewModel.openInObsidian(conversion) } label: {
                    Image(systemName: "book").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Open in Obsidian")
            }
            Button { viewModel.revealInFinder(conversion) } label: {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(fileExists ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .disabled(!fileExists)
            .help("Reveal in Finder")
        }
        .padding(10)
        .background(.quaternary.opacity(fileExists ? 0.5 : 0.2), in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            ForEach(eligibleHooks) { hook in
                Button(hook.name) { viewModel.runHook(hook, for: conversion) }
            }
            if !eligibleHooks.isEmpty { Divider() }
            Button("Remove from History", role: .destructive) {
                viewModel.removeHistoryEntry(conversion)
            }
        }
    }

    // MARK: - Helpers

    private var filteredHistory: [RecentConversion] {
        viewModel.allHistory.filter { conversion in
            let matchesSearch = searchText.isEmpty ||
                conversion.filename.localizedCaseInsensitiveContains(searchText)
            let matchesType = filterType == nil || conversion.noteType == filterType
            return matchesSearch && matchesType
        }
    }

    private func contextMenuHooks(for conversion: RecentConversion) -> [PostSaveHook] {
        viewModel.settings.hooks.filter {
            $0.showInContextMenu && $0.enabled &&
            ($0.trigger == .any || $0.trigger == conversion.noteType)
        }
    }
}
