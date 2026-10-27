import Foundation

/// How Kagami goes about new versions, as the one choice the settings window offers.
///
/// Sparkle keeps this as two switches — check on a schedule, and download what the check finds —
/// and the second means nothing without the first. Three of the four combinations are distinct
/// behaviours; the fourth, downloading without checking, is the same as never checking, so it reads
/// back as `.manual` rather than as a state the picker cannot show.
///
/// Out of the box it is `.manual`: `SUEnableAutomaticChecks` is off in `Info.plist`, so Kagami goes
/// online only when the user asks it to.
enum UpdatePolicy: CaseIterable, Hashable {
    /// Download in the background and install when Kagami next quits.
    case automatic
    /// Check once a day and show what was found, with a choice to install it.
    case ask
    /// Only look when the user asks.
    case manual

    init(checksAutomatically: Bool, downloadsAutomatically: Bool) {
        self = switch (checksAutomatically, downloadsAutomatically) {
        case (true, true): .automatic
        case (true, false): .ask
        case (false, _): .manual
        }
    }

    var checksAutomatically: Bool { self != .manual }
    var downloadsAutomatically: Bool { self == .automatic }

    var title: String {
        switch self {
        case .automatic: "Install Automatically"
        case .ask: "Ask Before Installing"
        case .manual: "Only When I Check"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            "Kagami checks once a day, downloads what it finds in the background, and installs it the next time it quits."
        case .ask:
            "Kagami checks once a day and asks before downloading anything."
        case .manual:
            "Kagami never looks for updates on its own. Check Now looks once."
        }
    }
}
