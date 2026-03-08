//
//  AddItemIntent.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import AppIntents

struct AddItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Item to List"
    static var description: IntentDescription = "Adds a new item to one of your lists"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item Name", requestValueDialog: "What would you like to add?")
    var itemName: String

    @Parameter(title: "List", requestValueDialog: "Which list?")
    var list: ListEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let listID = list.id
        var lists = TodoStore.loadLists()

        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else {
            return .result(dialog: "I couldn't find that list.")
        }

        let trimmed = itemName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Please provide an item name.")
        }

        lists[listIndex].items.insert(TodoItem(title: trimmed), at: 0)
        TodoStore.saveLists(lists)

        let listName = lists[listIndex].name
        return .result(dialog: "Added \"\(trimmed)\" to \(listName).")
    }
}
