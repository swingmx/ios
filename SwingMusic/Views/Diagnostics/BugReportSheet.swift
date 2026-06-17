import SwiftUI

struct BugReportSheet: View {
    let report: BugReport

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var log = Log.shared

    @State private var note: String = ""
    @State private var copied = false
    @FocusState private var noteFocused: Bool

    private var current: BugReport {
        var r = report
        r.note = note
        return r
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Describe what happened…", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                } header: {
                    Text("What happened?")
                } footer: {
                    Text("Your note and the details below are attached so the problem can be reproduced.")
                }

                Section("Report") {
                    Button {
                        UIPasteboard.general.string = report.id
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(report.id).monospaced()
                                Image(systemName: "doc.on.doc").font(.footnote)
                            }
                            .foregroundStyle(.secondary)
                        } label: {
                            Text("Report ID").foregroundStyle(.primary)
                        }
                    }
                }

                Section("Details") {
                    LabeledContent("Device", value: report.device)
                    LabeledContent("iOS", value: report.systemVersion)
                    LabeledContent("App", value: report.appVersion)
                    LabeledContent("Server", value: report.serverURL)
                    LabeledContent("Free Space", value: report.freeDisk)
                }

                Section("Playback") {
                    detailRow("Now Playing", report.nowPlaying)
                    LabeledContent("Queue", value: report.queueInfo)
                    LabeledContent("Downloads", value: report.downloadInfo)
                }

                Section {
                    NavigationLink {
                        LogDetailView()
                    } label: {
                        LabeledContent("Technical Log", value: "\(log.entries.count) entries")
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = current.plainText
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }

                    ShareLink(item: current.plainText,
                              subject: Text("Swing Music Bug \(report.id)"),
                              message: Text("Swing Music bug report")) {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Report a Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LogDetailView: View {
    @ObservedObject private var log = Log.shared

    var body: some View {
        List(log.entries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: entry.level.symbol)
                        .font(.caption2)
                        .foregroundStyle(color(for: entry.level))
                    Text(entry.category.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.date.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Text(entry.message)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        .listStyle(.plain)
        .navigationTitle("Technical Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = log.text()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }

    private func color(for level: Log.Entry.Level) -> Color {
        switch level {
        case .debug: .gray
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}
