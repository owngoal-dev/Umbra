import SwiftUI

struct TVApplicationsView: View {
    @EnvironmentObject private var model: TVModel
    @State private var query = ""

    private var filtered: [UMBInstalledAppInfo] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? model.apps : model.apps.filter {
            ($0.name ?? "").localizedStandardContains(text)
                || ($0.bundleIdentifier ?? "").localizedStandardContains(text)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let reason = model.unavailableReason {
                Text(reason).font(.callout).foregroundStyle(.secondary).padding(24)
            }
            if filtered.isEmpty {
                Group {
                    if model.busy {
                        ProgressView(localized("Loading…"))
                    } else {
                        TVEmptyView(
                            title: query.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty ? "No apps found" : "No search results",
                            symbol: model.apps.isEmpty ? "square.stack.3d.up" : "magnifyingglass"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TVList(horizontalInset: 0) { TVApplicationRows(apps: filtered) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TVAppearance.background.ignoresSafeArea())
        .searchable(text: $query, prompt: localized("name or identifier"))
    }
}

private struct TVApplicationRows: View {
    let apps: [UMBInstalledAppInfo]

    var body: some View {
        ForEach(apps, id: \.bundleIdentifier) { app in
            TVApplicationRow(app: app)
        }
    }
}

private struct TVApplicationRow: View {
    @EnvironmentObject private var model: TVModel
    let app: UMBInstalledAppInfo
    @State private var confirmsClear = false
    @State private var confirmsBlacklist = false
    @State private var acknowledgedCompatibility = false

    private var blacklisted: Bool {
        model.isBlacklisted(app)
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if !blacklisted, !acknowledgedCompatibility, UMBBackend.requiresCompatibilityWarning() {
                    confirmsBlacklist = true
                } else {
                    model.setBlacklisted(!blacklisted, app: app)
                }
            } label: {
                HStack(spacing: 24) {
                    if let icon = app.icon {
                        Image(uiImage: icon).resizable().scaledToFit()
                            .frame(width: 96, height: 72)
                            .accessibilityHidden(true)
                    }
                    TVRow(
                        title: app.name ?? app.bundleIdentifier ?? "",
                        subtitle: app.bundleIdentifier,
                        disclosure: false
                    )
                    Capsule()
                        .fill(.white.opacity(blacklisted ? 0.9 : 0.2))
                        .frame(width: 64, height: 36)
                        .overlay(alignment: blacklisted ? .trailing : .leading) {
                            Circle().fill(blacklisted ? TVAppearance.background : .white)
                                .frame(width: 28, height: 28).padding(4)
                        }
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel((app.name ?? "") + ", " + localized("Blacklist"))
            .accessibilityValue(localized(blacklisted ? "Enabled" : "Disabled"))
            .disabled(model.busy || model.unavailableReason != nil)

            Button { confirmsClear = true } label: {
                Image(systemName: "trash")
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
            .frame(width: 88)
            .accessibilityLabel(localized("Clear App Data") + ": " + (app.name ?? ""))
            .disabled(model.busy)
        }
        .alert(localized("Warning"), isPresented: $confirmsBlacklist) {
            Button(localized("Cancel"), role: .cancel) {}
            Button(localized("Continue")) {
                acknowledgedCompatibility = true
                model.setBlacklisted(true, app: app)
            }
        } message: {
            Text(
                localized(
                    "\nFor iOS15 A12+ devices:\n\nthe blacklisted app will have its app extension disabled, and may cause a spinlock panic when the app is running in the foreground/background.\n\nYou can first try disabling tweak injection for this app in Choicy, and only blacklist the app if it doesn't work."
                )
            )
        }
        .alert(String(format: localized("Clear data for %@?"), app.name ?? ""), isPresented: $confirmsClear) {
            Button(localized("Cancel"), role: .cancel) {}
            Button(localized("Clear Data"), role: .destructive) { model.clear(app) }
        } message: {
            Text(localized("This permanently removes this app’s data. This cannot be undone."))
        }
    }
}
