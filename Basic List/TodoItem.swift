//
//  TodoItem.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import Foundation

struct TodoItem: Identifiable, Codable, Sendable {
    var id = UUID()
    var title: String
    var isCompleted: Bool = false
    var isArchived: Bool = false
    var archivedDate: Date?
    var completedDate: Date?

    nonisolated init(id: UUID = UUID(), title: String, isCompleted: Bool = false, isArchived: Bool = false, archivedDate: Date? = nil, completedDate: Date? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.isArchived = isArchived
        self.archivedDate = archivedDate
        self.completedDate = completedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        archivedDate = try container.decodeIfPresent(Date.self, forKey: .archivedDate)
        completedDate = try container.decodeIfPresent(Date.self, forKey: .completedDate)
    }
}
