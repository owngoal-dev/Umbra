import SwiftUI

struct TVRootView: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        Group {
            if model.ready {
                TabView {
                    TVApplicationsView()
                        .tabItem { Label(localized("Blacklist"), systemImage: "shield") }
                    NavigationView { TVCleanerView() }
                        .tabItem { Label(localized("var Cleanup"), systemImage: "folder") }
                    NavigationView { TVEnvironmentView() }
                        .tabItem { Label(localized("Environment Check"), systemImage: "checkmark.shield") }
                }
            } else {
                VStack(spacing: 32) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 72))
                    Text("Umbra").font(.largeTitle)
                    if let error = model.startupError {
                        Text(localized("Startup failed")).font(.headline)
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button(localized("Try Again")) { model.start() }
                    } else {
                        ProgressView(localized("Loading…"))
                    }
                }
                .frame(maxWidth: 1000)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.ready, let activity = model.activity {
                HStack(spacing: 16) {
                    ProgressView()
                    Text(activity).font(.callout)
                }
                .padding(20)
                .background(.regularMaterial, in: Capsule())
                .padding(40)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
            }
        }
        .preferredColorScheme(.dark)
        .background(TVAppearance.background.ignoresSafeArea())
        .alert(item: $model.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(localized("Done")))
            )
        }
    }
}
