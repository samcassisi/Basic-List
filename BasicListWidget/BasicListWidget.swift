//
//  BasicListWidget.swift
//  BasicListWidget
//
//  Created by Sam Cassisi on 28/2/2026.
//

import WidgetKit
import SwiftUI
import AppIntents

struct TodoEntry: TimelineEntry {
    let date: Date
    let items: [TodoItem]
    let listName: String
}

struct TodoProvider: AppIntentTimelineProvider {
    typealias Entry = TodoEntry
    typealias Intent = SelectListIntent

    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: .now, items: [
            TodoItem(title: "Sample task 1"),
            TodoItem(title: "Sample task 2"),
            TodoItem(title: "Sample task 3"),
        ], listName: "To Do")
    }

    func snapshot(for configuration: SelectListIntent, in context: Context) async -> TodoEntry {
        let listID = configuration.list?.id ?? TodoList.defaultID
        let list = TodoStore.loadList(id: listID) ?? TodoList.makeDefault()
        let items = list.items.filter { !$0.isArchived }
        return TodoEntry(date: .now, items: items, listName: list.name)
    }

    func timeline(for configuration: SelectListIntent, in context: Context) async -> Timeline<TodoEntry> {
        let listID = configuration.list?.id ?? TodoList.defaultID
        let list = TodoStore.loadList(id: listID) ?? TodoList.makeDefault()
        let items = list.items.filter { !$0.isArchived }
        let entry = TodoEntry(date: .now, items: items, listName: list.name)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

struct TodoWidgetRowView: View {
    let item: TodoItem

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleTodoIntent(id: item.id)) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                    .font(.system(size: 15))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .invalidatableContent()

            Link(destination: URL(string: "basiclist://item/\(item.id.uuidString)")!) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct BasicListWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.showsWidgetContainerBackground) var showsBackground
    var entry: TodoEntry

    var body: some View {
        let itemCount: Int = switch family {
        case .systemMedium: 4
        case .systemLarge: 9
        default: 4
        }
        let displayItems = Array(entry.items.prefix(itemCount))

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(entry.listName)
                    .font(.title3.bold())
                Spacer()
                if showsBackground {
                    Link(destination: URL(string: "basiclist://new")!) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                } else {
                    Button(intent: AddItemIntent()) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)

            if displayItems.isEmpty {
                Spacer()
                Text("No tasks yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(displayItems) { item in
                        TodoWidgetRowView(item: item)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct BasicListWidget: Widget {
    let kind: String = "BasicListWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectListIntent.self, provider: TodoProvider()) { entry in
            BasicListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("To Do List")
        .description("View and check off your to-do items.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("Small", as: .systemSmall) {
    BasicListWidget()
} timeline: {
    TodoEntry(date: .now, items: [
        TodoItem(title: "Buy groceries"),
        TodoItem(title: "Walk the dog"),
        TodoItem(title: "Read a book"),
    ], listName: "To Do")
}

#Preview("Medium", as: .systemMedium) {
    BasicListWidget()
} timeline: {
    TodoEntry(date: .now, items: [
        TodoItem(title: "Buy groceries"),
        TodoItem(title: "Walk the dog"),
        TodoItem(title: "Read a book"),
        TodoItem(title: "Call dentist"),
    ], listName: "To Do")
}

#Preview("Large", as: .systemLarge) {
    BasicListWidget()
} timeline: {
    TodoEntry(date: .now, items: (1...9).map { TodoItem(title: "Task \($0)") }, listName: "To Do")
}
