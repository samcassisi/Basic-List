//
//  Basic_ListApp.swift
//  Fable
//
//  Created by Sam Cassisi on 28/2/2026.
//

import SwiftUI
import AppIntents

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        windowScene.windows.forEach { $0.backgroundColor = .clear }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

@main
struct Basic_ListApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = TodoStore.shared

    init() {
        BasicListShortcutsProvider.updateAppShortcutParameters()
        TodoStore.shared.purgeOldArchivedItems()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
