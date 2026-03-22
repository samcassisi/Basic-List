//
//  ContentView.swift
//  Fable
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
    @State private var isTextFieldFocused: Bool = false
    @State private var isEditingFocused: Bool = false
    @State private var isInsertingNewItem: Bool = false
    @State private var collapsingItemIDs: Set<UUID> = []
    @State private var isHandlingDeepLink: Bool = false
    @State private var reorderDraggingID: UUID?
    @State private var reorderCurrentIndex: Int?
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var autoScrollTimer: Timer?
    @State private var scrollViewFrame: CGRect = .zero
    @State private var contentOriginY: CGFloat = 0
    @State private var autoScrollDirection: Int = 0
    @State private var listToDelete: UUID?
    @State private var keyboardHolderActive: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.clear

                KeyboardHolder(isActive: $keyboardHolderActive)
                    .frame(width: 0, height: 0)

                TabView(selection: $store.selectedListID) {
                    ForEach(store.lists) { list in
                        todoList(for: list)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    isTextFieldFocused = false
                                    isEditingFocused = false
                                    commitEdit()
                                }
                            )
                            .tag(list.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                inputBar
            }
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(store.selectedList.name)
                        .font(.title2.bold())
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
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
                guard url.scheme == "fable" else { return }
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
                        // fable://item/{listID}/{itemID}
                        listID = uuids[0]
                        itemID = uuids[1]
                    } else if let uuid = uuids.first {
                        // fable://item/{itemID} (legacy)
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

        return ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(activeItems.enumerated()), id: \.element.id) { index, item in
                        if collapsingItemIDs.contains(item.id) {
                            Color.clear
                                .frame(height: 0)
                        } else {
                            cardView(for: item, index: index, activeItems: activeItems, scrollProxy: scrollProxy)
                        }
                    }

                    if list.showArchived && !archivedItems.isEmpty {
                        archivedSectionView(items: archivedItems)
                    }

                    Color.clear.frame(height: 60)
                }
                .coordinateSpace(name: "reorderSpace")
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global).minY) { _, newY in
                                contentOriginY = newY
                            }
                            .onAppear {
                                contentOriginY = geo.frame(in: .global).minY
                            }
                    }
                )
            }
            .contentMargins(.top, 8)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            scrollViewFrame = geo.frame(in: .global)
                        }
                        .onChange(of: geo.frame(in: .global)) { _, frame in
                            scrollViewFrame = frame
                        }
                }
            )
        }
    }

    // MARK: - Card View

    private func cardView(for item: TodoItem, index: Int, activeItems: [TodoItem], scrollProxy: ScrollViewProxy) -> some View {
        let isDragging = reorderDraggingID == item.id

        return HStack(spacing: 0) {
            activeRowContent(item: item)
                .frame(maxWidth: .infinity, alignment: .leading)

            if editingItemID != item.id {
                if item.isCompleted {
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
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                } else {
                    Image(systemName: "line.3.horizontal")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            LongPressGesture(minimumDuration: 0.3)
                                .sequenced(before: DragGesture(coordinateSpace: .named("reorderSpace")))
                                .onChanged { value in
                                    switch value {
                                    case .second(true, let drag):
                                        if reorderDraggingID == nil {
                                            reorderDraggingID = item.id
                                            reorderCurrentIndex = index
                                        }
                                        if let drag = drag {
                                            updateReorderPosition(dragY: drag.location.y, activeItems: activeItems)
                                            let globalY = contentOriginY + drag.location.y
                                            updateAutoScroll(globalY: globalY, activeItems: activeItems, scrollProxy: scrollProxy)
                                        }
                                    default:
                                        break
                                    }
                                }
                                .onEnded { _ in
                                    finishReorder(activeItems: activeItems)
                                }
                        )
                }
            }
        }
        .id(item.id)
        .padding(.leading, 16)
        .padding(.trailing, editingItemID == item.id ? 16 : 4)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 14))
        .contentShape(.interaction, Rectangle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            let otherLists = store.lists.filter { $0.id != store.selectedListID }
            Button {
                withAnimation {
                    store.moveActiveItemToStart(id: item.id)
                }
            } label: {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
            Button {
                withAnimation {
                    store.moveActiveItemToEnd(id: item.id)
                }
            } label: {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
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
            Button {
                UIPasteboard.general.string = item.title
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                withAnimation {
                    store.deleteItem(id: item.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(
                    highlightedItemID == item.id && highlightVisible ? 0.2 : 0
                ))
                .animation(.easeOut(duration: 1.5), value: highlightVisible)
                .allowsHitTesting(false)
        )
        .opacity(isDragging ? 0.5 : 1.0)
        .padding(.horizontal)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        cardFrames[item.id] = geo.frame(in: .named("reorderSpace"))
                    }
                    .onChange(of: geo.frame(in: .named("reorderSpace"))) { _, frame in
                        cardFrames[item.id] = frame
                    }
            }
        )
        .overlay(alignment: .top) {
            if let targetIndex = reorderCurrentIndex,
               reorderDraggingID != nil,
               reorderDraggingID != item.id,
               targetIndex == index {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 20)
                    .offset(y: -6)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let targetIndex = reorderCurrentIndex,
               let draggingID = reorderDraggingID,
               draggingID != item.id,
               targetIndex == activeItems.count {
                // Show the bottom indicator on the last non-dragged item
                let lastNonDraggedIndex = activeItems.lastIndex(where: { $0.id != draggingID })
                if lastNonDraggedIndex == index {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(height: 3)
                        .padding(.horizontal, 20)
                        .offset(y: 6)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func updateReorderPosition(dragY: CGFloat, activeItems: [TodoItem]) {
        guard let draggedID = reorderDraggingID else { return }

        // Determine the target index by comparing the drag position against
        // the midpoints of all non-dragged cards. This gives us an index in
        // the original activeItems array (which still includes the dragged item).
        var newIndex: Int? = nil
        for (i, item) in activeItems.enumerated() {
            guard item.id != draggedID, let frame = cardFrames[item.id] else { continue }
            if dragY < frame.midY {
                newIndex = i
                break
            }
        }

        // If below all non-dragged items, target one past the last position
        // (meaning "insert after the last item")
        if newIndex == nil {
            newIndex = activeItems.count
        }

        if let idx = newIndex, reorderCurrentIndex != idx {
            reorderCurrentIndex = idx
        }
    }

    private func updateAutoScroll(globalY: CGFloat, activeItems: [TodoItem], scrollProxy: ScrollViewProxy) {
        let edgeZone: CGFloat = 60
        let topThreshold = scrollViewFrame.minY + edgeZone
        let bottomThreshold = scrollViewFrame.maxY - edgeZone

        if globalY > bottomThreshold {
            autoScrollDirection = 1
        } else if globalY < topThreshold {
            autoScrollDirection = -1
        } else {
            autoScrollDirection = 0
            stopAutoScroll()
            return
        }

        // Already have a timer running — it will pick up the latest direction
        guard autoScrollTimer == nil else { return }

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard let currentIndex = reorderCurrentIndex,
                  reorderDraggingID != nil,
                  autoScrollDirection != 0 else {
                stopAutoScroll()
                return
            }

            // Find the next non-dragged item in the scroll direction
            var targetIndex = currentIndex + autoScrollDirection
            while targetIndex >= 0, targetIndex < activeItems.count,
                  activeItems[targetIndex].id == reorderDraggingID {
                targetIndex += autoScrollDirection
            }
            guard targetIndex >= 0, targetIndex < activeItems.count else { return }

            let targetItem = activeItems[targetIndex]
            withAnimation(.easeInOut(duration: 0.15)) {
                scrollProxy.scrollTo(targetItem.id, anchor: autoScrollDirection > 0 ? .bottom : .top)
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func finishReorder(activeItems: [TodoItem]) {
        stopAutoScroll()
        guard let draggedID = reorderDraggingID,
              let targetIndex = reorderCurrentIndex,
              let sourceIndex = activeItems.firstIndex(where: { $0.id == draggedID }),
              sourceIndex != targetIndex else {
            reorderDraggingID = nil
            reorderCurrentIndex = nil
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            // targetIndex is either the index of the item the blue line is shown
            // above (meaning "insert before this item"), or activeItems.count
            // (meaning "insert after the last item"). move(fromOffsets:toOffset:)
            // handles both cases correctly.
            store.moveActive(from: IndexSet(integer: sourceIndex), to: targetIndex)
        }
        reorderDraggingID = nil
        reorderCurrentIndex = nil
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
                .id("archived-\(item.id)")
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func activeRowContent(item: TodoItem) -> some View {
        let textContent = Group {
            if editingItemID == item.id {
                NonResigningTextField(
                    placeholder: "Item name",
                    text: $editingItemTitle,
                    isFocused: $isEditingFocused,
                    onReturn: {
                        let currentID = editingItemID
                        let wasEmpty = editingItemTitle.trimmingCharacters(in: .whitespaces).isEmpty
                        isInsertingNewItem = !wasEmpty
                        if !wasEmpty {
                            // Transfer focus to hidden holder before the current text field is destroyed
                            keyboardHolderActive = true
                            isEditingFocused = false
                        }
                        commitEdit()
                        if !wasEmpty, let currentID {
                            let newID = withAnimation { store.insertItem(after: currentID) }
                            editingItemID = newID
                            editingItemTitle = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                keyboardHolderActive = false
                                isEditingFocused = true
                                isInsertingNewItem = false
                            }
                        } else {
                            isEditingFocused = false
                            isInsertingNewItem = false
                        }
                    }
                )
                .fixedSize(horizontal: false, vertical: true)

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
                Button {
                    guard editingItemID != item.id else { return }
                    commitEdit()
                    editingItemID = item.id
                    editingItemTitle = item.title
                    isEditingFocused = true
                } label: {
                    Text(item.title)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    Spacer()
                }
                .buttonStyle(.plain)
            }
        }

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

            textContent
        }

        row
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
            NonResigningTextField(
                placeholder: "New item...",
                text: $newItemTitle,
                isFocused: $isTextFieldFocused,
                onReturn: {
                    addItem()
                }
            )
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: isTextFieldFocused) { _, focused in
                if focused { commitEdit() }
            }

            Button {
                addItem()
                isTextFieldFocused = false
            } label: {
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !list.isDefault {
                            Button(role: .destructive) {
                                listToDelete = list.id
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        if !list.isDefault {
                            Button(role: .destructive) {
                                listToDelete = list.id
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
            .listStyle(.insetGrouped)
            .deleteDisabled(true)
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete this list?",
                isPresented: Binding(
                    get: { listToDelete != nil },
                    set: { if !$0 { listToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = listToDelete {
                        withAnimation {
                            store.deleteList(id: id)
                        }
                        listToDelete = nil
                    }
                }
            } message: {
                Text("This will permanently delete the list and all its items.")
            }
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

                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            renameCurrentList()
                        } label: {
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

/// A UITextField wrapper that fires `onReturn` without dismissing the keyboard.
struct NonResigningTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var onReturn: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.delegate = context.coordinator
        tf.font = .preferredFont(forTextStyle: .body)
        tf.adjustsFontForContentSizeCategory = true
        tf.returnKeyType = .default
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.required, for: .vertical)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.required, for: .vertical)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        if tf.text != text {
            tf.text = text
        }
        tf.placeholder = placeholder

        if isFocused && !tf.isFirstResponder {
            // Use async to avoid UIKit layout warnings
            DispatchQueue.main.async { tf.becomeFirstResponder() }
        } else if !isFocused && tf.isFirstResponder {
            tf.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NonResigningTextField

        init(_ parent: NonResigningTextField) {
            self.parent = parent
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }
    }
}

/// An invisible UITextField that can temporarily hold first responder to keep
/// the keyboard alive while swapping between visible text fields.
struct KeyboardHolder: UIViewRepresentable {
    @Binding var isActive: Bool

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.alpha = 0
        tf.isUserInteractionEnabled = false
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        if isActive && !tf.isFirstResponder {
            tf.isUserInteractionEnabled = true
            tf.becomeFirstResponder()
        } else if !isActive && tf.isFirstResponder {
            tf.resignFirstResponder()
            tf.isUserInteractionEnabled = false
        }
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
