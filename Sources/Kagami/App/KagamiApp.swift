import SwiftUI

@main
struct KagamiApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Kagami", id: "main") {
            ContentView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Kagami") { AboutPanel.show() }
                Button("Check for Updates…") { appDelegate.updates.checkForUpdates() }
                    .disabled(!appDelegate.updates.isAvailable || !appDelegate.updates.canCheck)
            }
        }

        Settings {
            SettingsView(updates: appDelegate.updates)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = FlashModel()
    let updates = UpdateService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        updates.isBusy = { [model] in model.isWorking }
        model.onFinish = { [updates] in updates.flashDidFinish() }
        updates.start()
    }

    /// Closing the window mid-flash only hides it: the write carries on and the Dock icon brings it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !model.isWorking
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isWorking else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Kagami is still flashing a drive."
        alert.informativeText = model.isVerifying
            ? "The image is completely written. Quitting skips the rest of the verification and leaves the drive un-ejected."
            : "Quitting now leaves the drive only partially written, and it won't boot."
        alert.addButton(withTitle: "Keep Flashing")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
