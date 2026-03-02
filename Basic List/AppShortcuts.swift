//
//  AppShortcuts.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import AppIntents

struct BasicListShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddItemIntent(),
            phrases: [
                "Open \(.applicationName) and add item",
                "Use \(.applicationName) to add item",
                "In \(.applicationName) create item",
            ],
            shortTitle: "Add Item",
            systemImageName: "plus.circle"
        )
    }
}
