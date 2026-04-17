import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showFileImporter = false
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.recentConversions.isEmpty {
                dropZoneArea
            } else {
                compactDropZoneArea.padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                recentConversionsList
                    .frame(maxHeight: 220)
            }
            statusBar
        }
        .frame(width: windowWidth, height: windowHeight)
        .onOpenURL { url in viewModel.handleOpenURL(url) }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data, UTType(filenameExtension: "eml") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.handleFileImport(result: .success(url))
            }
        }
        .sheet(isPresented: $viewModel.showDatePicker) {
            RecurringDatePickerView(viewModel: viewModel)
        }
        .alert("Convert attachments to PDF?", isPresented: $viewModel.showPDFConvertPrompt) {
            Button("Convert") { viewModel.confirmPDFConversion(convert: true) }
            Button("Skip", role: .cancel) { viewModel.confirmPDFConversion(convert: false) }
        } message: {
            Text("This email has \(viewModel.pendingConvertibleFilenames.count) convertible attachment\(viewModel.pendingConvertibleFilenames.count == 1 ? "" : "s"). Save a PDF version alongside the original and embed it in the note?")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Open...") { showFileImporter = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "hookActivity")
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: viewModel.hasRunningHooks ? "bolt.fill" : "bolt")
                            .foregroundStyle(activityIconColor)
                        if viewModel.hasRecentHookFailures {
                            Circle().fill(.red).frame(width: 6, height: 6).offset(x: 3, y: -3)
                        }
                    }
                }
                .help("Hook Activity")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings")
            }
        }
    }

    private var activityIconColor: Color {
        if viewModel.hasRecentHookFailures { return .red }
        if viewModel.hasRunningHooks { return .accentColor }
        return .primary
    }

    /// Window width scales with layout: grid needs more horizontal room.
    private var windowWidth: CGFloat {
        let layout = viewModel.settings.effectiveDropZoneLayout
        let count = viewModel.settings.enabledVaults.count
        if layout == .grid && count >= 2 {
            return 420  // wider for 2-column grid
        }
        return 360
    }

    /// Window height scales with content — avoids wasted whitespace for small
    /// vault counts while still giving enough room for larger grids.
    private var windowHeight: CGFloat {
        let statusBarHeight: CGFloat = 28
        let contentHeight = dropAreaContentHeight
        let recentListHeight: CGFloat = viewModel.recentConversions.isEmpty ? 0 : 220
        let compactDropHeight: CGFloat = viewModel.recentConversions.isEmpty ? 0 : 0 // compact is already part of its own padding
        return contentHeight + recentListHeight + compactDropHeight + statusBarHeight
    }

    /// Content area height for the drop zone based on layout + vault count.
    private var dropAreaContentHeight: CGFloat {
        let enabled = viewModel.settings.enabledVaults
        let layout = viewModel.settings.effectiveDropZoneLayout

        // With recent conversions, the compact drop area is small.
        if !viewModel.recentConversions.isEmpty {
            // Compact header — single row or small grid
            if enabled.count <= 1 { return 64 }
            if layout == .grid {
                let rows = (enabled.count + 1) / 2  // 2 per row
                return CGFloat(rows) * 44 + CGFloat(rows - 1) * 8 + 16
            }
            return 80  // picker + compact zone
        }

        // Empty state — full drop zone area
        if enabled.isEmpty { return 160 }
        if enabled.count == 1 { return 220 }  // single zone + hint

        switch layout {
        case .grid:
            // 2-column grid
            let cellHeight = gridCellHeight(vaultCount: enabled.count)
            let rows = (enabled.count + 1) / 2
            return CGFloat(rows) * cellHeight + CGFloat(rows - 1) * 10 + 24  // padding
        case .dropdown, .segmented:
            return 220  // picker + zone + hint
        }
    }

    // MARK: - Drop Zone Area

    @ViewBuilder
    private var dropZoneArea: some View {
        let enabled = viewModel.settings.enabledVaults
        if enabled.isEmpty {
            noVaultHint
        } else if enabled.count == 1 {
            // Single vault → always show one big drop zone, no picker
            singleDropZone(vault: enabled[0])
        } else {
            switch viewModel.settings.effectiveDropZoneLayout {
            case .grid:
                gridDropZones(vaults: enabled)
            case .dropdown:
                dropdownDropZone(vaults: enabled)
            case .segmented:
                segmentedDropZone(vaults: enabled)
            }
        }
    }

    @ViewBuilder
    private var compactDropZoneArea: some View {
        let enabled = viewModel.settings.enabledVaults
        if enabled.isEmpty {
            EmptyView()
        } else if enabled.count == 1 {
            singleCompactDropZone(vault: enabled[0])
        } else {
            switch viewModel.settings.effectiveDropZoneLayout {
            case .grid:
                gridCompactDropZones(vaults: enabled)
            case .dropdown:
                dropdownCompactDropZone(vaults: enabled)
            case .segmented:
                segmentedCompactDropZone(vaults: enabled)
            }
        }
    }

    // MARK: - Single Vault Layouts

    private func singleDropZone(vault: VaultConfig) -> some View {
        VStack(spacing: 12) {
            VaultDropCell(
                vault: vault,
                viewModel: viewModel,
                variant: .large,
                showVaultName: false
            )
            .frame(width: 220, height: 160)
            Text("or ⌘O to open a file")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func singleCompactDropZone(vault: VaultConfig) -> some View {
        VaultDropCell(
            vault: vault,
            viewModel: viewModel,
            variant: .compact,
            showVaultName: false
        )
        .frame(height: 48)
    }

    // MARK: - Grid (Option A)

    private func gridDropZones(vaults: [VaultConfig]) -> some View {
        let columns = vaults.count >= 2 ? 2 : 1
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 10), count: columns)
        return LazyVGrid(columns: gridItems, spacing: 10) {
            ForEach(vaults) { vault in
                VaultDropCell(
                    vault: vault,
                    viewModel: viewModel,
                    variant: .large,
                    showVaultName: true
                )
                .frame(height: gridCellHeight(vaultCount: vaults.count))
            }
        }
        .padding(12)
    }

    private func gridCompactDropZones(vaults: [VaultConfig]) -> some View {
        let columns = vaults.count >= 2 ? 2 : 1
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
        return LazyVGrid(columns: gridItems, spacing: 8) {
            ForEach(vaults) { vault in
                VaultDropCell(
                    vault: vault,
                    viewModel: viewModel,
                    variant: .compact,
                    showVaultName: true
                )
                .frame(height: 44)
            }
        }
    }

    private func gridCellHeight(vaultCount: Int) -> CGFloat {
        // 2-4 vaults: 2x2 grid with tall cells
        // 5-6 vaults: 2x3 or 3x2 grid with shorter cells
        if vaultCount <= 2 { return 180 }
        if vaultCount <= 4 { return 130 }
        return 100
    }

    // MARK: - Dropdown (Option B)

    private func dropdownDropZone(vaults: [VaultConfig]) -> some View {
        VStack(spacing: 12) {
            vaultDropdownPicker(vaults: vaults)
            if let active = viewModel.settings.activeVault {
                VaultDropCell(
                    vault: active,
                    viewModel: viewModel,
                    variant: .large,
                    showVaultName: false
                )
                .frame(width: 220, height: 140)
            }
            Text("or ⌘O to open a file")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func dropdownCompactDropZone(vaults: [VaultConfig]) -> some View {
        VStack(spacing: 6) {
            vaultDropdownPicker(vaults: vaults)
            if let active = viewModel.settings.activeVault {
                VaultDropCell(
                    vault: active,
                    viewModel: viewModel,
                    variant: .compact,
                    showVaultName: false
                )
                .frame(height: 44)
            }
        }
    }

    private func vaultDropdownPicker(vaults: [VaultConfig]) -> some View {
        Picker("Vault", selection: Binding(
            get: { viewModel.settings.activeVaultID ?? vaults.first?.id ?? UUID() },
            set: { viewModel.settings.activeVaultID = $0 }
        )) {
            ForEach(vaults) { vault in
                HStack {
                    VaultIndicator(vault: vault, size: 10)
                    Text(vault.name)
                }.tag(vault.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    // MARK: - Segmented (Option C)

    private func segmentedDropZone(vaults: [VaultConfig]) -> some View {
        VStack(spacing: 12) {
            vaultSegmentedPicker(vaults: vaults)
            if let active = viewModel.settings.activeVault {
                VaultDropCell(
                    vault: active,
                    viewModel: viewModel,
                    variant: .large,
                    showVaultName: false
                )
                .frame(width: 220, height: 140)
            }
            Text("or ⌘O to open a file")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func segmentedCompactDropZone(vaults: [VaultConfig]) -> some View {
        VStack(spacing: 6) {
            vaultSegmentedPicker(vaults: vaults)
            if let active = viewModel.settings.activeVault {
                VaultDropCell(
                    vault: active,
                    viewModel: viewModel,
                    variant: .compact,
                    showVaultName: false
                )
                .frame(height: 44)
            }
        }
    }

    private func vaultSegmentedPicker(vaults: [VaultConfig]) -> some View {
        Picker("Vault", selection: Binding(
            get: { viewModel.settings.activeVaultID ?? vaults.first?.id ?? UUID() },
            set: { viewModel.settings.activeVaultID = $0 }
        )) {
            ForEach(vaults) { vault in
                Text(vault.name).tag(vault.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    // MARK: - No Vault Hint

    private var noVaultHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No vault configured")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Settings") { openSettings() }
        }
        .padding()
    }

    // MARK: - Recent List

    private var recentConversionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT")
                .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.recentConversions) { conversion in
                        recentRow(conversion)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }

    private func recentRow(_ conversion: RecentConversion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversion.filename.replacingOccurrences(of: ".md", with: ""))
                    .font(.caption).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 4) {
                    // Vault badge
                    if let vaultID = conversion.vaultID,
                       let vault = viewModel.settings.vault(id: vaultID) {
                        VaultIndicator(vault: vault, size: 8)
                        Text(vault.name).foregroundStyle(.secondary)
                        Text("·")
                    } else if let name = conversion.vaultName {
                        Text(name).foregroundStyle(.secondary)
                        Text("·")
                    }
                    Text(conversion.timestamp, format: .dateTime.hour().minute())
                    if conversion.attendeeCount > 0 { Text("·"); Text("\(conversion.attendeeCount) attendees") }
                    if let stripped = conversion.strippedInfo { Text("·"); Text(stripped) }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if viewModel.settings.isVaultConfigured {
                Button { viewModel.openInObsidian(conversion) } label: {
                    Image(systemName: "book").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in Obsidian")
            }
            Button { viewModel.revealInFinder(conversion) } label: {
                Image(systemName: "folder").font(.caption2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.settings.isVaultConfigured ? .green : .yellow)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
    }

    private var statusText: String {
        let enabled = viewModel.settings.enabledVaults
        if enabled.isEmpty { return "No vault configured" }
        if enabled.count == 1 { return enabled[0].name }
        return "\(enabled.count) vaults configured"
    }
}

// MARK: - Vault Drop Cell

/// A single drop target associated with a specific vault. Wraps the AppKit
/// `VaultDropNSView` which handles NSFilePromiseReceiver (Outlook file promises),
/// file URLs, and inline pasteboard content.
struct VaultDropCell: View {
    enum Variant { case large, compact }

    let vault: VaultConfig
    @Bindable var viewModel: AppViewModel
    let variant: Variant
    let showVaultName: Bool

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            VaultDropTargetView(
                vaultID: vault.id,
                onICSContent: { text, name in
                    viewModel.processICSText(text, sourceName: name, vaultID: vault.id)
                },
                onEMLContent: { text, name in
                    viewModel.processEMLText(text, sourceName: name, vaultID: vault.id)
                },
                onDropTargeted: { targeted in
                    isTargeted = targeted
                }
            )

            RoundedRectangle(cornerRadius: variant == .large ? 16 : 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: variant == .large ? 16 : 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .allowsHitTesting(false)

            cellContent
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var cellContent: some View {
        if variant == .large {
            ZStack {
                // Dot in upper-left
                if showVaultName {
                    VStack {
                        HStack {
                            VaultIndicator(vault: vault, size: 12)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }

                VStack(spacing: 8) {
                    if showVaultName {
                        Text(isTargeted ? "Release to save\nto \(vault.name)" : vault.name)
                            .font(.callout).fontWeight(.medium)
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: showVaultName ? 28 : 36))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    if !showVaultName {
                        Text(isTargeted ? "Release to convert" : "Drop .ics or .eml here")
                            .font(.callout)
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    }
                }
                .padding(10)
            }
        } else {
            // Compact variant — horizontal layout
            HStack(spacing: 8) {
                if showVaultName {
                    VaultIndicator(vault: vault, size: 10)
                    Text(vault.name)
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                }
                Image(systemName: "arrow.down.doc")
                    .font(.caption).foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                if !showVaultName {
                    Text(isTargeted ? "Release" : "Drop another file")
                        .font(.caption)
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

// MARK: - Recurring Date Picker

struct RecurringDatePickerView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private var timeRangeText: String {
        guard let event = viewModel.pendingEvent else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone.current
        return "\(f.string(from: event.startDate)) - \(f.string(from: event.endDate))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("Recurring Event")
                .font(.headline)

            if let event = viewModel.pendingEvent {
                Text(event.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Meeting date:")
                    .font(.callout)
                DatePicker(
                    "Date",
                    selection: $viewModel.selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.field)
                .labelsHidden()
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.cancelRecurringDate()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Note") {
                    viewModel.confirmRecurringDate()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 280)
    }
}
