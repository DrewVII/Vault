import SwiftUI

/// Application entry point.
///
/// At launch:
/// 1. Instantiate the `Store` (loads `store.json` from Application Support).
/// 2. Seed default categories and a Checking account if the store is empty.
/// 3. Apply any recurring transactions that are due (idempotent).
/// 4. Hand the store to the SwiftUI view tree via `.environmentObject`.
@main
struct VaultApp: App {
    @StateObject private var store: Store

    init() {
        let store = Store()
        SeedData.bootstrapIfNeeded(store)
        RecurrenceEngine.applyDue(store)
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(scheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // Remove the default "New" menu item — Vault has no "documents".
            CommandGroup(replacing: .newItem) {}
        }

        // macOS-standard ⌘, settings window.
        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 460, height: 380)
        }
    }

    // MARK: - Appearance preference

    @AppStorage("vault.colorScheme") private var schemeRaw: String = "system"

    /// Resolves the user's preferred appearance setting.
    /// `nil` means "follow the system" — SwiftUI's default behaviour.
    private var scheme: ColorScheme? {
        switch schemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
