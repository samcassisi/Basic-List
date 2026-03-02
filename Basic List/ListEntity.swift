//
//  ListEntity.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import AppIntents

struct ListEntity: AppEntity {
    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "List"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = ListEntityQuery()

    static var defaultEntity: ListEntity {
        ListEntity(id: TodoList.defaultID, name: "To Do")
    }
}

struct ListEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ListEntity] {
        let lists = TodoStore.loadLists()
        return identifiers.compactMap { id in
            lists.first(where: { $0.id == id }).map { ListEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [ListEntity] {
        TodoStore.loadLists().map { ListEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> ListEntity? {
        ListEntity.defaultEntity
    }
}
