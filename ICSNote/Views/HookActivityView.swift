import SwiftUI

/// Dedicated window showing hook execution history — running, successful,
/// failed, or skipped. Stays open while the user works so failures are visible.
struct HookActivityView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.hookRuns.isEmpty {
                emptyState
            } else {
                runList
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }

    private var header: some View {
        HStack {
            Text("Hook Activity").font(.headline)
            if viewModel.hasRunningHooks {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Text(summary)
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear") { viewModel.clearHookRuns() }
                .controlSize(.small)
                .disabled(viewModel.hookRuns.isEmpty)
        }
        .padding()
    }

    private var summary: String {
        let total = viewModel.hookRuns.count
        guard total > 0 else { return "" }
        let running = viewModel.hookRuns.filter { !$0.isComplete }.count
        let failed = viewModel.hookRuns.filter { $0.isFailure }.count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if failed > 0 { parts.append("\(failed) failed") }
        parts.append("\(total) total")
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt").font(.largeTitle).foregroundStyle(.tertiary)
            Text("No hook activity yet").foregroundStyle(.secondary)
            Text("Hooks fire automatically after notes are saved.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var runList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.hookRuns) { run in
                    HookRunRow(run: run, onCancel: { viewModel.cancelHookRun(run) })
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Row

private struct HookRunRow: View {
    let run: HookRun
    var onCancel: (() -> Void)? = nil
    @State private var expanded = false
    @State private var tab: DetailTab = .stdout

    private enum DetailTab: String, CaseIterable, Identifiable {
        case prompt, stdout, stderr
        var id: String { rawValue }
        var label: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.hookName).font(.body).fontWeight(.medium).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(run.vaultName).foregroundStyle(.secondary)
                        Text("·")
                        Text(run.noteFilename).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        Text("·")
                        Text(run.startedAt, format: .dateTime.hour().minute())
                        if let duration = durationText {
                            Text("·")
                            Text(duration)
                        }
                        if case .failure(let exitCode) = run.status {
                            Text("·")
                            Text("exit \(exitCode)").foregroundStyle(.red)
                        } else if case .cancelled = run.status {
                            Text("·")
                            Text("cancelled").foregroundStyle(.gray)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !run.isComplete {
                    Button {
                        onCancel?()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel this hook")
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            if expanded {
                detailPanel
            }
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var detailPanel: some View {
        if case .skipped(let reason) = run.status {
            Text("Reason: \(reason)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)
        } else {
            VStack(spacing: 6) {
                Picker("", selection: $tab) {
                    ForEach(DetailTab.allCases) { t in
                        let label = "\(t.label)\(badgeText(for: t))"
                        Text(label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView {
                    Text(textFor(tab).isEmpty ? "(empty)" : textFor(tab))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 240)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

                HStack {
                    Spacer()
                    Button {
                        let s = textFor(tab)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(s, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .disabled(textFor(tab).isEmpty)
                }
            }
        }
    }

    private func textFor(_ tab: DetailTab) -> String {
        switch tab {
        case .prompt: return run.prompt
        case .stdout: return run.stdout
        case .stderr: return run.stderr
        }
    }

    private func badgeText(for tab: DetailTab) -> String {
        let count = textFor(tab).count
        guard count > 0 else { return "" }
        if count < 1000 { return " (\(count))" }
        return " (\(count / 1000)k)"
    }

    private var rowBackground: some ShapeStyle {
        switch run.status {
        case .failure:
            return AnyShapeStyle(Color.red.opacity(0.08))
        case .skipped:
            return AnyShapeStyle(Color.orange.opacity(0.08))
        case .cancelled:
            return AnyShapeStyle(Color.gray.opacity(0.1))
        case .success, .running:
            return AnyShapeStyle(.quaternary.opacity(0.5))
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch run.status {
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle.fill").foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.gray)
        }
    }

    private var durationText: String? {
        guard let finishedAt = run.finishedAt else { return nil }
        let elapsed = finishedAt.timeIntervalSince(run.startedAt)
        if elapsed < 1 { return String(format: "%.0fms", elapsed * 1000) }
        if elapsed < 60 { return String(format: "%.1fs", elapsed) }
        let minutes = Int(elapsed / 60)
        let seconds = Int(elapsed) % 60
        return "\(minutes)m \(seconds)s"
    }
}
