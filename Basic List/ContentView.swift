//
//  ContentView.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var store: TodoStore
    @State private var newItemTitle: String = ""
    @State private var archiveTimers: [UUID: Task<Void, Never>] = [:]
    @State private var highlightedItemID: UUID?
    @State private var highlightVisible: Bool = false
    @State private var showNewListSheet: Bool = false
    @State private var newListName: String = ""
    @State private var showListSettings: Bool = false
    @State private var renameListName: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var csvExportURL: URL?
    @State private var showShareSheet: Bool = false
    @State private var showCSVImporter: Bool = false
    @State private var editingItemID: UUID?
    @State private var editingItemTitle: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isEditingFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                todoList

                inputBar
            }
            .onTapGesture {
                isTextFieldFocused = false
                commitEdit()
            }
            .navigationTitle(store.selectedList.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    listSwitcherMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    trailingToolbarItems
                }
            }
            .onOpenURL { url in
                guard url.scheme == "basiclist" else { return }
                if url.host == "new" {
                    isTextFieldFocused = true
                } else if url.host == "item",
                          let idString = url.pathComponents.dropFirst().first,
                          let uuid = UUID(uuidString: idString) {
                    highlightedItemID = uuid
                    highlightVisible = true
                    Task {
                        try? await Task.sleep(for: .seconds(0.5))
                        await MainActor.run {
                            highlightVisible = false
                        }
                        try? await Task.sleep(for: .seconds(2))
                        await MainActor.run {
                            highlightedItemID = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewListSheet) {
                newListSheet
            }
            .sheet(isPresented: $showListSettings) {
                listSettingsSheet
            }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                csvExportURL = nil
            }) {
                if let url = csvExportURL {
                    ShareSheet(items: [url])
                }
            }
            .onChange(of: showListSettings) { _, isShowing in
                if !isShowing, csvExportURL != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showShareSheet = true
                    }
                }
            }
            .fileImporter(
                isPresented: $showCSVImporter,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                importCSV(result: result)
            }
        }
    }

    // MARK: - List Switcher Menu

    private var listSwitcherMenu: some View {
        Menu {
            ForEach(store.lists) { list in
                Button {
                    store.selectedListID = list.id
                } label: {
                    if list.id == store.selectedListID {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
    }

    // MARK: - Trailing Toolbar Items

    private var trailingToolbarItems: some View {
        HStack(spacing: 8) {
            Button {
                showNewListSheet = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())

            Button {
                let text = store.activeItems.map(\.title).joined(separator: "\n")
                UIPasteboard.general.string = text
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())

            Button {
                renameListName = store.selectedList.name
                showListSettings = true
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
        }
    }

    // MARK: - Todo List

    private var todoList: some View {
        List {
            ForEach(store.activeItems) { item in
                activeRow(item: item)
            }
            .onMove { source, destination in
                store.moveActive(from: source, to: destination)
            }
            .deleteDisabled(true)

            if store.selectedList.showArchived && !store.archivedItems.isEmpty {
                Section {
                    ForEach(store.archivedItems) { item in
                        archivedRow(item: item)
                    }
                    .moveDisabled(true)
                    .deleteDisabled(true)
                } header: {
                    HStack {
                        Text("Archived")
                        Spacer()
                        Button {
                            withAnimation {
                                store.deleteAllArchived()
                            }
                        } label: {
                            Text("Delete All")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .contentMargins(.bottom, 80, for: .scrollContent)
    }

    // MARK: - Row Views

    @ViewBuilder
    private func activeRow(item: TodoItem) -> some View {
        let row = HStack(spacing: 12) {
            Button {
                withAnimation {
                    store.toggleCompleted(id: item.id)
                }
                if store.selectedList.items.first(where: { $0.id == item.id })?.isCompleted == true {
                    scheduleArchive(for: item.id)
                } else {
                    cancelArchive(for: item.id)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            if editingItemID == item.id {
                TextField("Item name", text: $editingItemTitle)
                    .textFieldStyle(.plain)
                    .focused($isEditingFocused)
                    .onSubmit {
                        commitEdit()
                    }
            } else {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                Spacer()
            }
        }

        let tappableRow = row
            .contentShape(Rectangle())
            .onTapGesture {
                guard editingItemID != item.id else { return }
                editingItemID = item.id
                editingItemTitle = item.title
                isEditingFocused = true
            }

        if highlightedItemID == item.id {
            tappableRow.listRowBackground(
                Color.accentColor
                    .opacity(highlightVisible ? 0.2 : 0)
                    .animation(.easeOut(duration: 1.5), value: highlightVisible)
            )
        } else {
            tappableRow
        }
    }

    private func archivedRow(item: TodoItem) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation {
                    store.unarchive(id: item.id)
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .strikethrough()
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation {
                    store.deleteItem(id: item.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("New item...", text: $newItemTitle)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit(addItem)

            Button(action: addItem) {
                Image(systemName: "plus")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
            .disabled(newItemTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.capsule)
        .glassEffect(in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    // MARK: - New List Sheet

    private var newListSheet: some View {
        NewListSheet(listName: $newListName, isPresented: $showNewListSheet, onCreate: createList)
    }

    // MARK: - List Settings Sheet

    private var listSettingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("List name", text: $renameListName)
                            .textFieldStyle(.plain)
                            .onSubmit(renameCurrentList)

                        Button(action: renameCurrentList) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderless)
                        .disabled(renameListName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || renameListName.trimmingCharacters(in: .whitespaces) == store.selectedList.name)
                    }
                } header: {
                    Text("Rename List")
                }

                Section {
                    Button {
                        exportCSV()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export as CSV")
                        }
                    }

                    Button {
                        showListSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showCSVImporter = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import from CSV")
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { store.selectedList.addToBottom },
                        set: { _ in store.toggleAddToBottom() }
                    )) {
                        HStack {
                            Image(systemName: "arrow.down.to.line")
                            Text("Add New Items to Bottom")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { store.selectedList.showArchived },
                        set: { _ in withAnimation { store.toggleShowArchived() } }
                    )) {
                        HStack {
                            Image(systemName: "archivebox")
                            Text("Show Archived")
                        }
                    }
                }

                if store.selectedList.isDefault {
                    Section {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "xmark.bin")
                                Text("Clear List")
                            }
                        }
                        .confirmationDialog(
                            "Clear all items?",
                            isPresented: $showClearConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Clear All", role: .destructive) {
                                store.clearSelectedList()
                                showListSettings = false
                            }
                        } message: {
                            Text("This will permanently remove all items from this list.")
                        }
                    }
                } else {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete List")
                            }
                        }
                        .confirmationDialog(
                            "Delete \"\(store.selectedList.name)\"?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                let id = store.selectedListID
                                showListSettings = false
                                store.deleteList(id: id)
                            }
                        } message: {
                            Text("This will permanently delete the list and all its items.")
                        }
                    }
                }
            }
            .navigationTitle("List Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showListSettings = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func commitEdit() {
        guard let id = editingItemID else { return }
        store.updateItemTitle(id: id, title: editingItemTitle)
        editingItemID = nil
        editingItemTitle = ""
    }

    private func addItem() {
        let trimmed = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            store.addItem(title: trimmed)
        }
        newItemTitle = ""
        isTextFieldFocused = true
    }

    private func createList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.addList(name: trimmed)
        newListName = ""
        showNewListSheet = false
    }

    private func renameCurrentList() {
        let trimmed = renameListName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.renameList(id: store.selectedListID, to: trimmed)
        showListSettings = false
    }

    private func scheduleArchive(for id: UUID) {
        archiveTimers[id]?.cancel()
        archiveTimers[id] = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    store.archive(id: id)
                }
                archiveTimers.removeValue(forKey: id)
            }
        }
    }

    private func cancelArchive(for id: UUID) {
        archiveTimers[id]?.cancel()
        archiveTimers.removeValue(forKey: id)
    }

    private func importCSV(result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = contents.components(separatedBy: .newlines)

        for line in lines.dropFirst().reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse CSV: "Title",Completed
            var title = trimmed
            var isCompleted = false

            if trimmed.hasPrefix("\"") {
                // Find closing quote (handle escaped quotes)
                let afterQuote = trimmed.dropFirst()
                if let endIndex = afterQuote.range(of: "\",") {
                    title = String(afterQuote[afterQuote.startIndex..<endIndex.lowerBound])
                        .replacingOccurrences(of: "\"\"", with: "\"")
                    let remainder = String(afterQuote[endIndex.upperBound...])
                    isCompleted = remainder.trimmingCharacters(in: .whitespaces).lowercased() == "true"
                }
            } else if let commaIndex = trimmed.lastIndex(of: ",") {
                title = String(trimmed[trimmed.startIndex..<commaIndex])
                let completed = String(trimmed[trimmed.index(after: commaIndex)...])
                isCompleted = completed.trimmingCharacters(in: .whitespaces).lowercased() == "true"
            }

            guard !title.isEmpty else { continue }
            store.addItem(title: title)
            if isCompleted {
                if let item = store.activeItems.first(where: { $0.title == title && !$0.isCompleted }) {
                    store.toggleCompleted(id: item.id)
                }
            }
        }
    }

    private func exportCSV() {
        let list = store.selectedList
        var csv = "Title,Completed\n"
        for item in list.items {
            let title = item.title.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(title)\",\(item.isCompleted)\n"
        }

        let fileName = "\(list.name).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            csvExportURL = tempURL
            showListSettings = false
        } catch {
            // Export failed silently
        }
    }
}

// MARK: - Share Sheet

struct NewListSheet: View {
    @Binding var listName: String
    @Binding var isPresented: Bool
    var onCreate: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    TextField("List name", text: $listName)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit(onCreate)

                    Button(action: onCreate) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                    .disabled(listName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(in: .capsule)

                Spacer()
            }
            .padding()
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        listName = ""
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let store = TodoStore()
    store.lists = [
        TodoList(id: TodoList.defaultID, name: "To Do", items: [
            TodoItem(title: "Buy groceries"),
            TodoItem(title: "Walk the dog"),
            TodoItem(title: "Read a book", isCompleted: true),
            TodoItem(title: "Call dentist"),
            TodoItem(title: "Clean the kitchen"),
            TodoItem(title: "Reply to emails", isCompleted: true, isArchived: true),
            TodoItem(title: "Fix leaky tap", isCompleted: true, isArchived: true),
        ]),
        TodoList(id: UUID(), name: "Work", items: [
            TodoItem(title: "Review pull request"),
            TodoItem(title: "Update documentation"),
            TodoItem(title: "Team standup"),
        ]),
    ]
    return ContentView(store: store)
}
