import SwiftUI

struct TVCleanerView: View {
    @EnvironmentObject private var model: TVModel
    @State private var confirmsRemoval = false
    @State private var removalPaths: [String] = []

    var body: some View {
        TVPage(
            title: localized("var Cleanup"),
            subtitle: localized(
                "Review files in specified paths that apps may use to identify a jailbreak. Remove only items you recognize."
            )
        ) {
            if model.scanError != nil || model.groups.contains(where: { $0.errorMessage != nil }) {
                Button(localized("Try Again")) { model.scan() }.disabled(model.busy)
            }
            if !model.items.isEmpty {
                Button { model.selectAll() } label: {
                    Text(localized(model.allSelected ? "Deselect All" : "Select All"))
                }.disabled(model.busy || model.scanError != nil)
                Button(role: .destructive) {
                    removalPaths = model.selectedPaths
                    confirmsRemoval = true
                } label: {
                    Label(
                        String(format: localized("Remove %ld selected items"), model.selectedPaths.count),
                        systemImage: "trash"
                    )
                }.disabled(model.busy || model.scanError != nil || model.selectedPaths.isEmpty)
            }
        } content: {
            TVList {
                if let error = model.scanError {
                    TVEmptyView(title: "Unable to Scan", symbol: "exclamationmark.triangle", message: error)
                }
                ForEach(model.groups, id: \.path) { group in
                    TVSection(group.path) {
                        if let error = group.errorMessage {
                            Text(error).foregroundStyle(.secondary)
                        }
                        ForEach(group.items, id: \.path) { item in
                            NavigationLink(destination: TVCleanItemView(item: item)) {
                                TVRow(
                                    title: item.name,
                                    subtitle: model.failures[item.path]
                                        ??
                                        (item
                                            .ignored ?
                                            localized(item
                                                .checked ? "Selected Manually" : "Protected by a custom rule") : nil),
                                    symbol: item.checked ? "checkmark.circle.fill" : (item.folder ? "folder" : "doc")
                                )
                            }
                        }
                    }
                }
                if model.hasScanned, model.groups.isEmpty, model.scanError == nil, !model.busy {
                    TVEmptyView(title: "No Matching Items", symbol: "checkmark.circle")
                }
            }
        }
        .onAppear {
            if !model.hasScanned, !model.busy {
                model.scan()
            }
        }
        .onChange(of: model.busy) { busy in
            if !busy, !model.hasScanned {
                model.scan()
            }
        }
        .alert(localized("Remove Selected Items"), isPresented: $confirmsRemoval) {
            Button(localized("Cancel"), role: .cancel) {}
            Button(localized("Remove"), role: .destructive) { model.remove(removalPaths) }
        } message: {
            Text(String(format: localized("The %ld selected items will be permanently deleted."), removalPaths.count))
        }
    }
}

private struct TVCleanItemView: View {
    @EnvironmentObject private var model: TVModel
    let item: UMBCleanItem

    private var currentItem: UMBCleanItem? {
        model.items.first { $0.path == item.path }
    }

    var body: some View {
        TVList {
            TVSection {
                Text(item.path).font(.body).fixedSize(horizontal: false, vertical: true)
                if item.ignored {
                    Text(localized("Protected by a custom rule")).foregroundStyle(.secondary)
                }
                if let failure = model.failures[item.path] {
                    Text(failure).foregroundStyle(.secondary)
                }
            }
            TVSection {
                Toggle(localized("Select"), isOn: Binding(
                    get: { currentItem?.checked ?? false }, set: { value in
                        if let currentItem {
                            model.select(currentItem, value: value)
                        }
                    }
                )).disabled(model.busy || model.scanError != nil || currentItem == nil)
            }
        }
        .tvDetailTitle(item.name)
    }
}
