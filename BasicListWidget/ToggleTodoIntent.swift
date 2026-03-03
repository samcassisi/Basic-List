//
//  ToggleTodoIntent.swift
//  BasicListWidget
//
//  Created by Sam Cassisi on 28/2/2026.
//

import AppIntents
import WidgetKit

struct ToggleTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Todo"
    static var description: IntentDescription = "Marks a todo item as completed"

    @Parameter(title: "Todo ID")
    var todoID: String

    init() {}

    init(id: UUID) {
        self.todoID = id.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: todoID) else { return .result() }
        var lists = TodoStore.loadLists()

        // Archive any stale completed items first
        let cutoff = Date().addingTimeInterval(-3)
        for i in lists.indices {
            for j in lists[i].items.indices {
                let item = lists[i].items[j]
                if item.isCompleted && !item.isArchived,
                   let completedDate = item.completedDate,
                   completedDate < cutoff {
                    lists[i].items[j].isArchived = true
                    lists[i].items[j].archivedDate = Date()
                }
            }
        }

        for listIndex in lists.indices {
            if let itemIndex = lists[listIndex].items.firstIndex(where: { $0.id == uuid }) {
                lists[listIndex].items[itemIndex].isCompleted.toggle()
                if lists[listIndex].items[itemIndex].isCompleted {
                    lists[listIndex].items[itemIndex].completedDate = Date()
                } else {
                    lists[listIndex].items[itemIndex].completedDate = nil
                    lists[listIndex].items[itemIndex].isArchived = false
                    lists[listIndex].items[itemIndex].archivedDate = nil
                }
                TodoStore.saveLists(lists)
                WidgetCenter.shared.reloadAllTimelines()
                break
            }
        }
        return .result()
    }
}
