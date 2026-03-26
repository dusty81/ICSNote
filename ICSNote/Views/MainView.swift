import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showFileImporter = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            // AppKit-based drop target covers the entire window.
            // Uses NSFilePromiseReceiver for reliable Outlook file promise handling.
            DropTargetView(
                onICSContent: { text, name in
                    viewModel.processICSText(text, sourceName: name)
                },
                onDropTargeted: { targeted in
                    viewModel.isDropTargeted = targeted
                }
            )

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gear").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }

                if viewModel.recentConversions.isEmpty {
                    dropZone.frame(maxHeight: .infinity)
                } else {
                    compactDropZone.padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                    recentConversionsList
                }

                statusBar
            }
            .allowsHitTesting(true)
        }
        .frame(width: 320, height: 400)
        .onOpenURL { url in viewModel.handleOpenURL(url) }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.handleFileImport(result: .success(url))
            }
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
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    viewModel.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: viewModel.isDropTargeted ? [] : [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(viewModel.isDropTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                )
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(viewModel.isDropTargeted ? Color.accentColor : Color.secondary)
                        Text(viewModel.isDropTargeted ? "Release to convert" : "Drop .ics file here")
                            .font(.callout)
                            .foregroundStyle(viewModel.isDropTargeted ? Color.accentColor : Color.secondary)
                    }
                }
                .frame(width: 180, height: 140)
            Text("or File → Open")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .allowsHitTesting(false)
    }

    private var compactDropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                viewModel.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: 2, dash: viewModel.isDropTargeted ? [] : [8])
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.isDropTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .overlay {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3).foregroundStyle(viewModel.isDropTargeted ? Color.accentColor : Color.secondary)
                    Text(viewModel.isDropTargeted ? "Release to convert" : "Drop another .ics file")
                        .font(.callout).foregroundStyle(viewModel.isDropTargeted ? Color.accentColor : Color.secondary)
                }
            }
            .frame(height: 48)
            .allowsHitTesting(false)
    }

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
                    Text(conversion.timestamp, style: .relative)
                    if conversion.attendeeCount > 0 { Text("·"); Text("\(conversion.attendeeCount) attendees") }
                    if let stripped = conversion.strippedInfo { Text("·"); Text(stripped) }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button { viewModel.revealInFinder(conversion) } label: {
                Image(systemName: "arrow.up.forward").font(.caption2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.settings.isVaultConfigured ? .green : .yellow)
                .frame(width: 8, height: 8)
            Text(viewModel.settings.isVaultConfigured ? statusPath : "No vault configured")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
    }

    private var statusPath: String {
        let vault = (viewModel.settings.vaultPath as NSString).lastPathComponent
        if viewModel.settings.subfolder.isEmpty { return vault }
        return "\(vault) / \(viewModel.settings.subfolder)"
    }
}
