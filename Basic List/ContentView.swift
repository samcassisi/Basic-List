//
//  ContentView.swift
//  Basic List
//
//  Created by Sam Cassisi on 28/2/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: TodoStore
    @State private var newItemTitle: String = ""
    @State private var archiveTimers: [UUID: Task<Void, Never>] = [:]
    @State private var highlightedItemID: UUID?
    @State private var highlightVisible: Bool = false
    @State private var showNewListSheet: Bool = false
    @State private var showListManager: Bool = false
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
    @State private var isInsertingNewItem: Bool = false
    @State private var collapsingItemIDs: Set<UUID> = []
    @State private var isHandlingDeepLink: Bool = false
    @State private var dragTargetItemID: UUID?
    
    

    var body: some View {
        NavigationStack {
            TabView(selection: $store.selectedListID) {
                ForEach(store.lists) { list in
                    ZStack(alignment: .bottom) {
                        todoList(for: list)

                        inputBar
                    }
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                    .onTapGesture {
                        isTextFieldFocused = false
                        isEditingFocused = false
                        commitEdit()
                    }
                    .tag(list.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(store.selectedList.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(store.selectedList.name)
                        .font(.title2.bold())
                        .frame(maxHeight: .infinity)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    trailingToolbarItems
                }
            }
            .onAppear {
                resumeArchiveTimers()
            }
            .onChange(of: store.selectedListID) { _, _ in
                guard !isHandlingDeepLink else { return }
                isTextFieldFocused = false
                isEditingFocused = false
                commitEdit()
            }
            .onChange(of: isEditingFocused) { _, focused in
                if !focused && !isInsertingNewItem { commitEdit() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                commitEdit()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                resumeArchiveTimers()
            }
            .onOpenURL { url in
                guard url.scheme == "basiclist" else { return }
                if url.host == "new" {
                    if let idString = url.pathComponents.dropFirst().first,
                       let uuid = UUID(uuidString: idString),
                       store.lists.contains(where: { $0.id == uuid }) {
                        store.selectedListID = uuid
                    }
                    isTextFieldFocused = true
                } else if url.host == "list",
                          let idString = url.pathComponents.dropFirst().first,
                          let uuid = UUID(uuidString: idString) {
                    if store.lists.contains(where: { $0.id == uuid }) {
                        store.selectedListID = uuid
                    }
                } else if url.host == "item" {
                    let components = url.pathComponents.dropFirst()
                    let uuids = components.compactMap { UUID(uuidString: $0) }
                    var listID: UUID?
                    var itemID: UUID?
                    if uuids.count == 2 {
                        // basiclist://item/{listID}/{itemID}
                        listID = uuids[0]
                        itemID = uuids[1]
                    } else if let uuid = uuids.first {
                        // basiclist://item/{itemID} (legacy)
                        itemID = uuid
                    }
                    // Find the item across all lists
                    if let itemID {
                        let targetList = store.lists.first(where: { list in
                            list.id == listID || list.items.contains(where: { $0.id == itemID })
                        })
                        if let targetList,
                           let item = targetList.items.first(where: { $0.id == itemID }) {
                            isEditingFocused = false
                            commitEdit()
                            isHandlingDeepLink = true
                            store.selectedListID = targetList.id
                            editingItemID = itemID
                            editingItemTitle = item.title
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isEditingFocused = true
                                isHandlingDeepLink = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewListSheet) {
                newListSheet
            }
            .sheet(isPresented: $showListManager) {
                listManagerSheet
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

    // MARK: - Trailing Toolbar Items

    private var trailingToolbarItems: some View {
        HStack(spacing: 8) {
            Button {
                showListManager = true
            } label: {
                Image(systemName: "list.bullet")
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

    private func todoList(for list: TodoList) -> some View {
        let activeItems = list.items.filter { !$0.isArchived || collapsingItemIDs.contains($0.id) }
        let archivedItems = list.items.filter { $0.isArchived }

        return ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(activeItems) { item in
                    if collapsingItemIDs.contains(item.id) {
                        Color.clear
                            .frame(height: 0)
                    } else {
                        HStack(spacing: 0) {
                            activeRowContent(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if editingItemID != item.id {
                                Image(systemName: "line.3.horizontal")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 12)
                                    .frame(maxHeight: .infinity)
                                    .contentShape(Rectangle())
                                    .draggable(item) {
                                        Text(item.title)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                    }
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, editingItemID == item.id ? 16 : 4)
                        .padding(.vertical, 12)
                        .glassEffect(in: .rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.accentColor.opacity(
                                    highlightedItemID == item.id && highlightVisible ? 0.2 : 0
                                ))
                                .animation(.easeOut(duration: 1.5), value: highlightVisible)
                                .allowsHitTesting(false)
                        )
                        .padding(.horizontal)
                        .dropDestination(for: TodoItem.self) { items, _ in
                            guard let dragged = items.first,
                                  dragged.id != item.id else { return false }
                            let targetIndex = activeItems.firstIndex(where: { $0.id == item.id }) ?? 0
                            withAnimation(.easeInOut(duration: 0.3)) {
                                store.moveActiveItem(id: dragged.id, toIndex: targetIndex)
                            }
                            return true
                        } isTargeted: { isTargeted in
                            dragTargetItemID = isTargeted ? item.id : nil
                        }
                        .overlay(alignment: .top) {
                            if dragTargetItemID == item.id {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor)
                                    .frame(height: 3)
                                    .padding(.horizontal, 20)
                                    .offset(y: -6)
                                    .transition(.opacity)
                            }
                        }
                    }
                }

                if list.showArchived && !archivedItems.isEmpty {
                    archivedSectionView(items: archivedItems)
                }

                Color.clear.frame(height: 80)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Archived Section

    @ViewBuilder
    private func archivedSectionView(items: [TodoItem]) -> some View {
        HStack {
            Text("Archived")
                .font(.headline)
                .foregroundStyle(.secondary)
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
        .padding(.horizontal, 20)
        .padding(.top, 16)

        ForEach(items) { item in
            archivedRow(item: item)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: .rect(cornerRadius: 14))
                .padding(.horizontal)
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func activeRowContent(item: TodoItem) -> some View {
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
                        let currentID = editingItemID
                        let wasEmpty = editingItemTitle.trimmingCharacters(in: .whitespaces).isEmpty
                        isInsertingNewItem = !wasEmpty
                        commitEdit()
                        if !wasEmpty, let currentID {
                            let newID = withAnimation { store.insertItem(after: currentID) }
                            editingItemID = newID
                            editingItemTitle = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isEditingFocused = true
                                isInsertingNewItem = false
                            }
                        } else {
                            isInsertingNewItem = false
                        }
                    }

                Button {
                    isEditingFocused = false
                    commitEdit()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            } else {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                Spacer()
            }
        }

        let otherLists = store.lists.filter { $0.id != store.selectedListID }

        row
            .contentShape(Rectangle())
            .onTapGesture {
                guard editingItemID != item.id else { return }
                commitEdit()
                editingItemID = item.id
                editingItemTitle = item.title
                isEditingFocused = true
            }
            .contextMenu {
                if !otherLists.isEmpty {
                    Menu {
                        ForEach(otherLists) { list in
                            Button {
                                withAnimation {
                                    store.moveItem(id: item.id, toList: list.id)
                                }
                            } label: {
                                Label(list.name, systemImage: "folder")
                            }
                        }
                    } label: {
                        Label("Move to List", systemImage: "arrow.right.doc.on.clipboard")
                    }
                }
                Button(role: .destructive) {
                    withAnimation {
                        store.deleteItem(id: item.id)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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
                .onChange(of: isTextFieldFocused) { _, focused in
                    if focused { commitEdit() }
                }

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

    // MARK: - List Manager Sheet

    private var listManagerSheet: some View {
        NavigationStack {
            List {
                ForEach(store.lists) { list in
                    Button {
                        store.selectedListID = list.id
                        showListManager = false
                    } label: {
                        HStack {
                            Text(list.name)
                                .foregroundStyle(list.id == store.selectedListID ? .blue : .primary)
                            Spacer()
                            if list.id == store.selectedListID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                    }
                    .contextMenu {
                        if !list.isDefault {
                            Button(role: .destructive) {
                                withAnimation {
                                    store.deleteList(id: list.id)
                                }
                            } label: {
                                Label("Delete List", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove { source, destination in
                    store.reorderLists(from: source, to: destination)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showListManager = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showListManager = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showNewListSheet = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

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
        let trimmed = editingItemTitle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            withAnimation { store.deleteItem(id: id) }
        } else {
            store.updateItemTitle(id: id, title: editingItemTitle)
        }
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

    private func resumeArchiveTimers() {
        // Cancel all existing timers — they may be stale from before backgrounding
        for (id, task) in archiveTimers {
            task.cancel()
            archiveTimers.removeValue(forKey: id)
        }

        // Reload fresh data and archive anything already past 3 seconds
        store.reload()
        store.archiveStaleCompletedItems()

        // Schedule timers for any remaining completed-but-not-archived items
        for item in store.selectedList.items where item.isCompleted && !item.isArchived {
            if let completedDate = item.completedDate {
                let remaining = max(2 - Date().timeIntervalSince(completedDate), 0)
                archiveTimers[item.id] = Task {
                    try? await Task.sleep(for: .seconds(remaining))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        collapseAndArchive(id: item.id)
                    }
                }
            } else {
                scheduleArchive(for: item.id)
            }
        }
    }

    private func scheduleArchive(for id: UUID) {
        archiveTimers[id]?.cancel()
        archiveTimers[id] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                collapseAndArchive(id: id)
            }
        }
    }

    private func collapseAndArchive(id: UUID) {
        // Step 1: Fade out the row content
        _ = withAnimation(.easeOut(duration: 0.3)) {
            collapsingItemIDs.insert(id)
        }
        // Step 2: After fade, archive the item (row is already zero-height placeholder, so removal is invisible)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            store.archive(id: id)
            collapsingItemIDs.remove(id)
            archiveTimers.removeValue(forKey: id)
        }
    }

    private func cancelArchive(for id: UUID) {
        archiveTimers[id]?.cancel()
        archiveTimers.removeValue(forKey: id)
        collapsingItemIDs.remove(id)
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
