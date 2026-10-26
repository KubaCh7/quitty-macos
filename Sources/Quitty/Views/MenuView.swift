import SwiftUI

/// The panel that opens from the menu bar icon.
struct MenuView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater

    var body: some View {
        GlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                header
                if !model.isTrusted {
                    permissionCard
                }
                exclusionsCard
                settingsCard
                updateCard
                footer
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { model.refresh() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(model.isActive ? Color.white : Color.secondary)
                .frame(width: 40, height: 40)
                .glassCircle(tint: model.isActive ? Color.accentColor : nil)

            VStack(alignment: .leading, spacing: 2) {
                Text("Quitty")
                    .font(.headline)
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("Enabled", isOn: $model.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(12)
        .glassCard()
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Accessibility access")
                        .font(.callout.weight(.semibold))
                    Text("Quitty can't see when you close windows until you turn it on in System Settings → Privacy & Security → Accessibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Open System Settings") { model.openAccessibilitySettings() }
                    .glassButton(prominent: true)
                Spacer()
                Button("Already on? Reset") { model.resetAccessibilityPermission() }
                    .glassButton()
                    .help("Removes a stale Accessibility entry left by an older copy of Quitty, then asks again.")
            }
            .controlSize(.small)
        }
        .padding(12)
        .glassCard(tint: Color.orange.opacity(0.35))
    }

    private var exclusionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Never quit", systemImage: "hand.raised")

            if model.apps.isEmpty {
                Text("No apps are running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.apps) { app in
                            AppRow(app: app, isExcluded: Binding(
                                get: { model.isExcluded(app.id) },
                                set: { model.setExcluded(app.id, $0) }
                            ))
                        }
                    }
                }
                .frame(height: min(CGFloat(model.apps.count) * AppRow.height, 200))
            }

            HStack {
                Text("Finder is never quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add App…") { model.addExclusionFromFinder() }
                    .glassButton()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .glassCard()
    }

    private var settingsCard: some View {
        VStack(spacing: 8) {
            SettingRow(title: "Launch at login", systemImage: "power", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Divider().opacity(0.5)
            SettingRow(title: "Check for updates automatically", systemImage: "arrow.triangle.2.circlepath",
                       isOn: $model.autoCheckForUpdates)
        }
        .padding(12)
        .glassCard()
    }

    private var updateCard: some View {
        HStack(spacing: 10) {
            Image(systemName: updater.release == nil ? "checkmark.seal" : "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(updater.release == nil ? Color.secondary : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(updateTitle)
                    .font(.callout)
                Text(updateSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if updater.release != nil {
                Button("Update…") { model.showUpdateWindow() }
                    .glassButton(prominent: true)
            } else if updater.status == .checking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Check") { model.checkForUpdates() }
                    .glassButton()
            }
        }
        .controlSize(.small)
        .padding(12)
        .glassCard()
    }

    private var footer: some View {
        HStack {
            Text("Version \(updater.currentVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit Quitty") { NSApp.terminate(nil) }
                .glassButton()
                .controlSize(.small)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
    }

    private var updateTitle: String {
        if let release = updater.release {
            return "Quitty \(release.version) is available"
        }
        switch updater.status {
        case .checking: return "Checking for updates…"
        case .upToDate: return "Quitty is up to date"
        case .failed: return "Couldn't check for updates"
        case .idle, .installing: return "Updates"
        }
    }

    private var updateSubtitle: String {
        if case .failed(let message) = updater.status {
            return message
        }
        return "You have version \(updater.currentVersion)"
    }
}

private struct SectionTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct AppRow: View {
    static let height: CGFloat = 30

    let app: AppEntry
    @Binding var isExcluded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(app.name)
                .lineLimit(1)
            Spacer()
            Toggle(app.name, isOn: $isExcluded)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 4)
        .frame(height: Self.height)
    }
}

private struct SettingRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// The menu bar icon; filled while Quitty is active.
struct MenuBarIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: model.isActive ? "xmark.circle.fill" : "xmark.circle")
    }
}
