//
//  TodoList.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import Foundation

struct TodoList: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var items: [TodoItem]
    var showArchived: Bool = false
    var addToBottom: Bool = false

    /// The fixed ID for the default "To Do" list.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Whether this is the protected default list.
    var isDefault: Bool { id == Self.defaultID }

    static func makeDefault(items: [TodoItem] = []) -> TodoList {
        TodoList(id: defaultID, name: "To Do", items: items)
    }

    nonisolated init(id: UUID, name: String, items: [TodoItem], showArchived: Bool = false, addToBottom: Bool = false) {
        self.id = id
        self.name = name
        self.items = items
        self.showArchived = showArchived
        self.addToBottom = addToBottom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([TodoItem].self, forKey: .items)
        showArchived = try container.decodeIfPresent(Bool.self, forKey: .showArchived) ?? false
        addToBottom = try container.decodeIfPresent(Bool.self, forKey: .addToBottom) ?? false
    }
}
