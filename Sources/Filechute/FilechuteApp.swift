import SwiftUI

@main
struct FilechuteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands {
            CommandGroup(replacing: .textEditing) {}
        }
    }
}

struct RootView: View {
    @State private var storeManager: StoreManager?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let storeManager {
                ContentView(storeManager: storeManager)
            } else if let loadError {
                ContentUnavailableView(
                    "Failed to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Initializing...")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            guard storeManager == nil else { return }
            do {
                let appSupport = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first!
                let storeRoot = appSupport
                    .appendingPathComponent("dev.wincent.Filechute")
                    .appendingPathComponent("stores")
                    .appendingPathComponent("default")
                let manager = try StoreManager(storeRoot: storeRoot)
                try await manager.refresh()
                self.storeManager = manager
            } catch {
                self.loadError = error.localizedDescription
            }
        }
    }
}
