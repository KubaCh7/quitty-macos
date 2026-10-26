import SwiftUI

/// Content of the update window.
struct UpdateView: View {
    @ObservedObject var updater: Updater
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .glassCircle(tint: Color.accentColor)

            if let release = updater.release {
                VStack(spacing: 4) {
                    Text("A new version of Quitty is available")
                        .font(.title3.weight(.semibold))
                    Text("Quitty \(release.version) is ready. You have \(updater.currentVersion).")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                ScrollView {
                    Text(Self.formattedNotes(release.notes))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(height: 150)
                .glassCard(cornerRadius: 16)

                if let message = failureMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GlassGroup {
                    HStack {
                        Button("Skip This Version") {
                            updater.skip(release)
                            close()
                        }
                        .glassButton()
                        Spacer()
                        Button("Later", action: close)
                            .glassButton()
                        Button {
                            Task { await updater.install(release) }
                        } label: {
                            if updater.status == .installing {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Installing…")
                                }
                            } else {
                                Text("Install and Relaunch")
                            }
                        }
                        .glassButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                    }
                    .disabled(updater.status == .installing)
                }
            } else {
                Text("Quitty is up to date")
                    .font(.title3.weight(.semibold))
                Button("Close", action: close)
                    .glassButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .padding(.top, 8)
        .frame(width: 460)
    }

    private var failureMessage: String? {
        if case .failed(let message) = updater.status {
            return message
        }
        return nil
    }

    /// Release notes are Markdown; headings become bold lines because
    /// `Text` only renders inline Markdown.
    private static func formattedNotes(_ notes: String) -> AttributedString {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AttributedString("No release notes.") }
        let lines = trimmed.components(separatedBy: .newlines).map { line -> String in
            guard line.hasPrefix("#") else { return line }
            let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return heading.isEmpty ? "" : "**\(heading)**"
        }
        let markdown = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}
