//
//  Basic_ListApp.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import SwiftUI
import AppIntents

@main
struct Basic_ListApp: App {
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
