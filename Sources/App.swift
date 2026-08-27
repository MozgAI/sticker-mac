import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Сюда попадают файлы, открытые двойным кликом или брошенные на значок в Dock.
final class Inbox: ObservableObject {
    static let shared = Inbox()
    @Published var url: URL?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ app: NSApplication, open urls: [URL]) {
        if let u = urls.first { Inbox.shared.url = u }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

@main
struct StickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("Sticker") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
