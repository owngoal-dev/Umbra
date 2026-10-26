import Foundation

/// An app from OwnGoal Studio, featured at the bottom of Settings.
struct OwnGoalApp {
    let name: String
    let taglineKey: String
    let iconName: String
    let packageIdentifier: String
    let repositoryURL: URL

    /// Irisin opens a package page by its APT identity.
    var irisinURL: URL {
        URL(string: "irisin://package/\(packageIdentifier)")!
    }

    /// Sileo uses the same identity for its package page.
    var sileoURL: URL {
        URL(string: "sileo://package/\(packageIdentifier)")!
    }
}

/// The apps featured at the bottom of Settings. Each icon matches a Blacklist
/// row: 44 pt at 1x, 2x and 3x, with a 10 pt continuous corner.
enum OwnGoalApps {
    static let all: [OwnGoalApp] = [
        OwnGoalApp(
            name: "Irisin",
            taglineKey: "Manage Your Packages",
            iconName: "OwnGoalIrisin",
            packageIdentifier: "wiki.qaq.irisin",
            repositoryURL: URL(string: "https://github.com/Lakr233/Irisin")!
        ),
        OwnGoalApp(
            name: "Fila",
            taglineKey: "Manage Your Files",
            iconName: "OwnGoalFila",
            packageIdentifier: "wiki.qaq.fila",
            repositoryURL: URL(string: "https://github.com/owngoal-dev/Fila")!
        ),
        OwnGoalApp(
            name: "Inspector",
            taglineKey: "Inspect Running Processes",
            iconName: "OwnGoalInspector",
            packageIdentifier: "wiki.qaq.inspector",
            repositoryURL: URL(string: "https://github.com/owngoal-dev/Inspector")!
        ),
        OwnGoalApp(
            name: "Xrash",
            taglineKey: "Understand Every Crash",
            iconName: "OwnGoalXrash",
            packageIdentifier: "wiki.qaq.xrash",
            repositoryURL: URL(string: "https://github.com/owngoal-dev/Xrash")!
        ),
        OwnGoalApp(
            name: "iGhostVT",
            taglineKey: "A Ghostty-Powered Terminal",
            iconName: "OwnGoalIGhostVT",
            packageIdentifier: "wiki.qaq.ighostvt",
            repositoryURL: URL(string: "https://github.com/owngoal-dev/iGhostVT")!
        ),
    ]
}
