//
//  TodoStore.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import SwiftUI
import WidgetKit

@Observable
class TodoStore {
    static let shared = TodoStore()
    nonisolated static let appGroupID = "group.com.samcassisi.fable"

    private let defaults: UserDefaults
    private let listsKey = "todoLists"
    private let selectedListKey = "selectedListID"

    var lists: [TodoList] {
        didSet { save() }
    }

    var selectedListID: UUID {
        didSet {
            defaults.set(selectedListID.uuidString, forKey: selectedListKey)
        }
    }

    var activeItems: [TodoItem] {
        selectedList.items.filter { !$0.isArchived }
    }

    var archivedItems: [TodoItem] {
        selectedList.items.filter { $0.isArchived }
    }

    var selectedList: TodoList {
        lists.first(where: { $0.id == selectedListID })
            ?? lists.first
            ?? TodoList.makeDefault()
    }

    init() {
        let defaults = UserDefaults(suiteName: TodoStore.appGroupID) ?? .standard
        self.defaults = defaults

        // Try loading new multi-list format
        if let data = defaults.data(forKey: "todoLists"),
           let decoded = try? JSONDecoder().decode([TodoList].self, from: data),
           !decoded.isEmpty {
            self.lists = decoded
        }
        // Migration: convert old single-list data to new format
        else if let data = defaults.data(forKey: "todoItems"),
                let oldItems = try? JSONDecoder().decode([TodoItem].self, from: data) {
            self.lists = [TodoList.makeDefault(items: oldItems)]
        }
        // Fresh install
        else {
            self.lists = [TodoList.makeDefault()]
        }

        // Restore selected list
        if let savedID = defaults.string(forKey: "selectedListID"),
           let uuid = UUID(uuidString: savedID) {
            self.selectedListID = uuid
        } else {
            self.selectedListID = TodoList.defaultID
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(lists) {
            defaults.set(data, forKey: listsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Selected List Mutation Helper

    private func mutateSelectedList(_ body: (inout TodoList) -> Void) {
        guard let index = lists.firstIndex(where: { $0.id == selectedListID }) else { return }
        body(&lists[index])
    }

    // MARK: - Item Methods

    func addItem(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        mutateSelectedList { list in
            if list.addToBottom {
                let lastActiveIndex = list.items.lastIndex(where: { !$0.isArchived })
                let insertIndex = lastActiveIndex.map { $0 + 1 } ?? list.items.count
                list.items.insert(TodoItem(title: trimmed), at: insertIndex)
            } else {
                list.items.insert(TodoItem(title: trimmed), at: 0)
            }
        }
    }

    @discardableResult
    func insertItem(after id: UUID) -> UUID {
        let newItem = TodoItem(title: "")
        mutateSelectedList { list in
            if let index = list.items.firstIndex(where: { $0.id == id }) {
                list.items.insert(newItem, at: index + 1)
            }
        }
        return newItem.id
    }

    func updateItemTitle(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        mutateSelectedList { list in
            guard let index = list.items.firstIndex(where: { $0.id == id }) else { return }
            list.items[index].title = trimmed
        }
    }

    func toggleCompleted(id: UUID) {
        mutateSelectedList { list in
            guard let index = list.items.firstIndex(where: { $0.id == id }) else { return }
            list.items[index].isCompleted.toggle()
            list.items[index].completedDate = list.items[index].isCompleted ? Date() : nil
        }
    }

    func archive(id: UUID) {
        mutateSelectedList { list in
            guard let index = list.items.firstIndex(where: { $0.id == id && $0.isCompleted }) else { return }
            list.items[index].isArchived = true
            list.items[index].archivedDate = Date()
        }
    }

    func unarchive(id: UUID) {
        mutateSelectedList { list in
            guard let index = list.items.firstIndex(where: { $0.id == id }) else { return }
            list.items[index].isCompleted = false
            list.items[index].isArchived = false
            list.items[index].archivedDate = nil
            list.items[index].completedDate = nil
        }
    }

    func deleteItem(id: UUID) {
        mutateSelectedList { list in
            list.items.removeAll { $0.id == id }
        }
    }

    func deleteAllArchived() {
        mutateSelectedList { list in
            list.items.removeAll { $0.isArchived }
        }
    }

    func moveItem(id: UUID, toList destinationListID: UUID) {
        guard let sourceIndex = lists.firstIndex(where: { $0.id == selectedListID }),
              let destIndex = lists.firstIndex(where: { $0.id == destinationListID }),
              sourceIndex != destIndex,
              let itemIndex = lists[sourceIndex].items.firstIndex(where: { $0.id == id }) else { return }
        let item = lists[sourceIndex].items.remove(at: itemIndex)
        lists[destIndex].items.insert(item, at: 0)
    }

    func moveActive(from source: IndexSet, to destination: Int) {
        mutateSelectedList { list in
            var active = list.items.filter { !$0.isArchived }
            let archived = list.items.filter { $0.isArchived }
            active.move(fromOffsets: source, toOffset: destination)
            list.items = active + archived
        }
    }

    // MARK: - List Management

    func addList(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let newList = TodoList(id: UUID(), name: trimmed, items: [])
        lists.append(newList)
        selectedListID = newList.id
    }

    func deleteList(id: UUID) {
        guard id != TodoList.defaultID else { return }
        lists.removeAll { $0.id == id }
        if selectedListID == id {
            selectedListID = TodoList.defaultID
        }
    }

    func clearSelectedList() {
        mutateSelectedList { list in
            list.items.removeAll()
        }
    }

    func toggleShowArchived() {
        mutateSelectedList { list in
            list.showArchived.toggle()
        }
    }

    func toggleAddToBottom() {
        mutateSelectedList { list in
            list.addToBottom.toggle()
        }
    }

    func reorderLists(from source: IndexSet, to destination: Int) {
        lists.move(fromOffsets: source, toOffset: destination)
    }

    func renameList(id: UUID, to newName: String) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].name = newName.trimmingCharacters(in: .whitespaces)
    }

    func archiveStaleCompletedItems() {
        let cutoff = Date().addingTimeInterval(-2)
        for index in lists.indices {
            for itemIndex in lists[index].items.indices {
                let item = lists[index].items[itemIndex]
                if item.isCompleted && !item.isArchived,
                   let completedDate = item.completedDate,
                   completedDate < cutoff {
                    lists[index].items[itemIndex].isArchived = true
                    lists[index].items[itemIndex].archivedDate = Date()
                }
            }
        }
    }

    func purgeOldArchivedItems() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date())!
        for index in lists.indices {
            lists[index].items.removeAll { item in
                item.isArchived && (item.archivedDate == nil || item.archivedDate! < cutoff)
            }
        }
    }

    func reload() {
        if let data = defaults.data(forKey: listsKey),
           let decoded = try? JSONDecoder().decode([TodoList].self, from: data),
           !decoded.isEmpty {
            lists = decoded
        }
    }

    // MARK: - Static Methods for Widget

    nonisolated static func loadLists() -> [TodoList] {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        if let data = defaults.data(forKey: "todoLists"),
           let decoded = try? JSONDecoder().decode([TodoList].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        // Migration fallback
        if let data = defaults.data(forKey: "todoItems"),
           let oldItems = try? JSONDecoder().decode([TodoItem].self, from: data) {
            let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            let migrated = [TodoList(id: defaultID, name: "To Do", items: oldItems)]
            saveLists(migrated)
            return migrated
        }
        let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        return [TodoList(id: defaultID, name: "To Do", items: [])]
    }

    nonisolated static func loadList(id: UUID) -> TodoList? {
        loadLists().first(where: { $0.id == id })
    }

    /// Archives stale completed items across all lists and persists the change.
    /// Intended for use by the widget extension process.
    nonisolated static func archiveStaleCompletedItemsStatic() {
        var lists = loadLists()
        let cutoff = Date().addingTimeInterval(-2)
        var changed = false
        for i in lists.indices {
            for j in lists[i].items.indices {
                let item = lists[i].items[j]
                if item.isCompleted && !item.isArchived,
                   let completedDate = item.completedDate,
                   completedDate < cutoff {
                    lists[i].items[j].isArchived = true
                    lists[i].items[j].archivedDate = Date()
                    changed = true
                }
            }
        }
        if changed {
            saveLists(lists)
        }
    }

    nonisolated static func saveLists(_ lists: [TodoList]) {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        if let data = try? JSONEncoder().encode(lists) {
            defaults.set(data, forKey: "todoLists")
        }
    }
}
