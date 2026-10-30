import SwiftUI

struct TVEnvironmentView: View {
    @EnvironmentObject private var model: TVModel

    private func message(for finding: [String: String]) -> String {
        if ["SSH Server", "Dropbear", "Frida Server"].map(localized).contains(finding["title"] ?? "") {
            return localized("Detected on a default port.")
        }
        return finding["message"] ?? ""
    }

    var body: some View {
        TVPage(title: localized("Environment Check")) {} content: {
            TVList {
                if model.findings.isEmpty, !model.busy {
                    TVEmptyView(title: "No issues found", symbol: "checkmark.shield")
                }
                ForEach(Array(model.findings.enumerated()), id: \.offset) { _, finding in
                    TVSection(finding["title"]) {
                        Text(message(for: finding))
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    .focusable()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
