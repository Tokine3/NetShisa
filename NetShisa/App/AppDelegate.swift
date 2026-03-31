import AppKit
import SwiftUI
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var appState: AppState?
    private var modelContainer: ModelContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let schema = Schema([
                ConnectivitySnapshot.self,
                ServiceResult.self,
                DNSResult.self,
                Incident.self,
                TracerouteResult.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        let state = AppState(modelContainer: modelContainer!)
        self.appState = state

        statusBarController = StatusBarController(appState: state)

        state.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopMonitoring()
    }

    /// 最後のウィンドウが閉じてもアプリを終了しない（メニューバーに常駐）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
