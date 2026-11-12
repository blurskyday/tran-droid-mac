import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 1. Icons View (Finder Grid Mode)

struct FinderIconsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        let items = vm.filteredAndSortedItems
        let cellWidth = max(vm.iconGridSize + 36, 96)
        let columns = [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth + 24), spacing: 14)]

        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { item in
                    FinderIconCell(
                        item: item,
                        iconSize: vm.iconGridSize,
                        isSelected: vm.selectedItemIds.contains(item.id),
                        thumbnail: item.domain == .android ? vm.thumbnails[item.itemId] : (item.isImage && item.localURL != nil ? NSImage(contentsOf: item.localURL!) : nil)
                    )
                    .onTapGesture(count: 2) {
                        vm.enterFolder(item)
                    }
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded {
                            let flags = NSApp.currentEvent?.modifierFlags ?? []
                            if flags.contains(.command) {
                                if vm.selectedItemIds.contains(item.id) {
                                    vm.selectedItemIds.remove(item.id)
                                } else {
                                    vm.selectedItemIds.insert(item.id)
                                }
                            } else {
                                vm.selectedItemIds = [item.id]
                            }
                            vm.loadPreviewIfNeeded(for: item)
                        }
                    )
                    .contextMenu {
                        FinderItemContextMenu(vm: vm, item: item)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onTapGesture {
            vm.selectedItemIds.removeAll()
        }
    }
}

struct FinderIconCell: View {
    let item: FileItem
    let iconSize: Double
    let isSelected: Bool
    let thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                    .frame(width: iconSize + 16, height: iconSize + 16)

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize - 4, height: iconSize - 4)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                } else {
                    Image(systemName: item.symbolName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize * 0.78, height: iconSize * 0.78)
                        .foregroundStyle(item.iconColor.gradient)
                }
            }

            Text(item.name)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )

            if !item.isFolder {
                Text(item.formattedSize)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - 2. List View (Finder Table Mode)

struct FinderListView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        let items = vm.filteredAndSortedItems

        VStack(spacing: 0) {
            // Finder Column Headers
            HStack(spacing: 0) {
                sortableHeader(title: "Name", field: .name)
                    .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 16)

                sortableHeader(title: "Date Modified", field: .dateModified)
                    .frame(width: 170, alignment: .leading)

                Divider().frame(height: 16)

                sortableHeader(title: "Size", field: .size)
                    .frame(width: 100, alignment: .trailing)

                Divider().frame(height: 16)

                sortableHeader(title: "Kind", field: .kind)
                    .frame(width: 150, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let isSelected = vm.selectedItemIds.contains(item.id)
                        HStack(spacing: 0) {
                            HStack(spacing: 8) {
                                if item.domain == .android, let thumb = vm.thumbnails[item.itemId] {
                                    Image(nsImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 18, height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                } else {
                                    Image(systemName: item.symbolName)
                                        .font(.system(size: 15))
                                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(item.iconColor.gradient))
                                        .frame(width: 20)
                                }
                                Text(item.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .foregroundStyle(isSelected ? .white : .primary)
                            }
                            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

                            Text(item.formattedDate)
                                .font(.system(size: 12))
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                                .frame(width: 170, alignment: .leading)

                            Text(item.formattedSize)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                                .frame(width: 100, alignment: .trailing)
                                .padding(.trailing, 8)

                            Text(item.kindDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                                .frame(width: 150, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(
                            isSelected
                            ? Color.accentColor
                            : (index.isMultiple(of: 2) ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .alternatingContentBackgroundColors.last ?? .controlBackgroundColor))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            vm.enterFolder(item)
                        }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded {
                                let flags = NSApp.currentEvent?.modifierFlags ?? []
                                if flags.contains(.command) {
                                    if vm.selectedItemIds.contains(item.id) {
                                        vm.selectedItemIds.remove(item.id)
                                    } else {
                                        vm.selectedItemIds.insert(item.id)
                                    }
                                } else {
                                    vm.selectedItemIds = [item.id]
                                }
                                vm.loadPreviewIfNeeded(for: item)
                            }
                        )
                        .contextMenu {
                            FinderItemContextMenu(vm: vm, item: item)
                        }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func sortableHeader(title: String, field: SortField) -> some View {
        Button {
            if vm.sortField == field {
                vm.sortAscending.toggle()
            } else {
                vm.sortField = field
                vm.sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: vm.sortField == field ? .semibold : .regular))
                    .foregroundStyle(.primary)
                if vm.sortField == field {
                    Image(systemName: vm.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. Columns View (Finder Miller Columns Mode)

struct FinderColumnsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 0) {
                ForEach(Array(vm.columnLevels.enumerated()), id: \.element.id) { colIdx, column in
                    VStack(spacing: 0) {
                        HStack {
                            Text(column.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(column.items.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Color(nsColor: .windowBackgroundColor))

                        Divider()

                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(column.items) { item in
                                    let isSelected = (column.selectedItemId == item.id)
                                    HStack(spacing: 7) {
                                        Image(systemName: item.symbolName)
                                            .font(.system(size: 14))
                                            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(item.iconColor.gradient))
                                            .frame(width: 18)

                                        Text(item.name)
                                            .font(.system(size: 12.5))
                                            .lineLimit(1)
                                            .foregroundStyle(isSelected ? .white : .primary)

                                        Spacer()

                                        if item.isFolder {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(isSelected ? Color.accentColor : Color.clear)
                                    )
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        if !item.isFolder {
                                            vm.openOrPreviewFile(item)
                                        } else {
                                            vm.enterFolder(item)
                                        }
                                    }
                                    .simultaneousGesture(
                                        TapGesture(count: 1).onEnded {
                                            vm.selectItemInMillerColumn(columnIndex: colIdx, item: item)
                                        }
                                    )
                                    .contextMenu {
                                        FinderItemContextMenu(vm: vm, item: item)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(width: 235)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()
                }

                // Rightmost Finder Preview Column when a file is selected
                if let selected = vm.primarySelectedItem, !selected.isFolder {
                    FinderInspectorPreviewPane(vm: vm, item: selected)
                        .frame(width: 280)
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - 4. Gallery View (Finder Gallery + Filmstrip Mode)

struct FinderGalleryView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        let items = vm.filteredAndSortedItems
        let activeItem = vm.primarySelectedItem ?? items.first

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Hero Stage Area
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)

                    if let item = activeItem {
                        VStack(spacing: 14) {
                            if let preview = vm.previewImage {
                                Image(nsImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 520, maxHeight: 360)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .shadow(radius: 8)
                            } else if item.domain == .android, let thumb = vm.thumbnails[item.itemId] {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 420, maxHeight: 320)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .shadow(radius: 6)
                            } else {
                                Image(systemName: item.symbolName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 110, height: 110)
                                    .foregroundStyle(item.iconColor.gradient)
                            }

                            Text(item.name)
                                .font(.headline)
                            Text("\(item.kindDescription) • \(item.formattedSize)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                    } else {
                        Text("ไม่มีรายการในโฟลเดอร์นี้")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Bottom Filmstrip Scroller
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 10) {
                        ForEach(items) { item in
                            let isSelected = (activeItem?.id == item.id)
                            VStack(spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                                        )

                                    if item.domain == .android, let thumb = vm.thumbnails[item.itemId] {
                                        Image(nsImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 56, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Image(systemName: item.symbolName)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 34, height: 34)
                                            .foregroundStyle(item.iconColor.gradient)
                                    }
                                }
                                Text(item.name)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .frame(width: 68)
                            }
                            .onTapGesture(count: 2) {
                                vm.enterFolder(item)
                            }
                            .simultaneousGesture(
                                TapGesture(count: 1).onEnded {
                                    vm.selectedItemIds = [item.id]
                                    vm.loadPreviewIfNeeded(for: item)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(height: 104)
                .background(Color(nsColor: .windowBackgroundColor))
            }

            if let item = activeItem {
                Divider()
                FinderInspectorPreviewPane(vm: vm, item: item)
                    .frame(width: 270)
            }
        }
    }
}

// MARK: - Finder Right Inspector / Preview Pane

struct FinderInspectorPreviewPane: View {
    @ObservedObject var vm: AppViewModel
    let item: FileItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 10) {
                    if let preview = vm.previewImage {
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 3)
                    } else if item.domain == .android, let thumb = vm.thumbnails[item.itemId] {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: item.symbolName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .foregroundStyle(item.iconColor.gradient)
                            .padding(.vertical, 8)
                    }

                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)

                    Text("\(item.kindDescription) — \(item.formattedSize)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Information")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    infoRow(label: "Location", value: item.domain == .android ? "Android MTP" : "Mac Local")
                    infoRow(label: "Kind", value: item.kindDescription)
                    infoRow(label: "Size", value: item.formattedSize)
                    infoRow(label: "Modified", value: item.formattedDate)
                }

                Divider()

                VStack(spacing: 8) {
                    Button {
                        vm.enterFolder(item)
                    } label: {
                        Label(item.isFolder ? "เปิดโฟลเดอร์" : "เปิดดูไฟล์ (Quick Look / Open)", systemImage: item.isFolder ? "folder" : "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)

                    if item.domain == .android {
                        Button {
                            vm.downloadAndroidItems([item], toMacDirectory: vm.macPaneURL)
                        } label: {
                            Label("คัดลอกลง Mac (\(vm.macPaneURL.lastPathComponent))", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            vm.downloadSelectedAndroidItemsToMacPrompt()
                        } label: {
                            Label("บันทึกไปที่โฟลเดอร์อื่นบน Mac...", systemImage: "folder.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            vm.beginRename(item)
                        } label: {
                            Label("เปลี่ยนชื่อ", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }

                        Button(role: .destructive) {
                            vm.selectedItemIds = [item.id]
                            vm.deleteSelectedItems()
                        } label: {
                            Label("ลบ", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Context Menu

struct FinderItemContextMenu: View {
    @ObservedObject var vm: AppViewModel
    let item: FileItem

    var body: some View {
        Button {
            vm.enterFolder(item)
        } label: {
            Label(item.isFolder ? "เปิดโฟลเดอร์ (Open)" : "เปิดไฟล์ (Open on Mac)", systemImage: "arrow.up.forward.app")
        }

        if item.domain == .android {
            Divider()
            Button {
                vm.downloadAndroidItems([item], toMacDirectory: vm.macPaneURL)
            } label: {
                Label("คัดลอกลง Mac (\(vm.macPaneURL.lastPathComponent))", systemImage: "arrow.down.doc")
            }

            Button {
                vm.selectedItemIds = [item.id]
                vm.downloadSelectedAndroidItemsToMacPrompt()
            } label: {
                Label("คัดลอกลง Mac (เลือกโฟลเดอร์ปลายทาง...)", systemImage: "folder")
            }
        } else if let url = item.localURL {
            Divider()
            Button {
                vm.uploadLocalURLsToCurrentAndroidFolder([url])
            } label: {
                Label("ส่งเข้ามือถือ Android (\(vm.currentFolderTitle))", systemImage: "iphone.and.arrow.forward")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("แสดงใน Finder ของ Mac", systemImage: "macwindow")
            }
        }

        Divider()

        Button {
            vm.beginRename(item)
        } label: {
            Label("เปลี่ยนชื่อ (Rename...)", systemImage: "pencil")
        }

        Button(role: .destructive) {
            vm.selectedItemIds = [item.id]
            vm.deleteSelectedItems()
        } label: {
            Label("ลบ (Delete)", systemImage: "trash")
        }
    }
}

// MARK: - Dual-Pane Mac Companion Split View (Mac <-> Android Fast Transfer)

struct MacCompanionSplitPane: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar for Mac Split Pane
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(.blue)
                Text("Mac: \(vm.macPaneURL.lastPathComponent)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Menu {
                    ForEach(vm.macQuickFolders, id: \.name) { folder in
                        Button {
                            vm.loadMacPaneDirectory(url: folder.url)
                        } label: {
                            Label(folder.name, systemImage: folder.icon)
                        }
                    }
                } label: {
                    Label("โฟลเดอร์ลัด", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .controlSize(.small)

                Button {
                    let parent = vm.macPaneURL.deletingLastPathComponent()
                    if parent.path != vm.macPaneURL.path {
                        vm.loadMacPaneDirectory(url: parent)
                    }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("ขึ้นไปโฟลเดอร์แม่บน Mac")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Quick Transfer Action Bar between Android and Mac
            HStack(spacing: 10) {
                Button {
                    let androidSelected = vm.selectedItems.filter { $0.domain == .android }
                    vm.downloadAndroidItems(androidSelected, toMacDirectory: vm.macPaneURL)
                } label: {
                    Label("ดึงจาก Android มาที่ Mac นี้ →", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(vm.selectedItems.filter { $0.domain == .android }.isEmpty)

                Button {
                    vm.uploadSelectedMacPaneItemsToAndroid()
                } label: {
                    Label("← ส่งจาก Mac นี้เข้า Android", systemImage: "arrow.left.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.macPaneSelectedIds.isEmpty || vm.connectedDevice == nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.06))

            Divider()

            // Mac Files List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.macPaneItems.enumerated()), id: \.element.id) { index, item in
                        let isSelected = vm.macPaneSelectedIds.contains(item.id)
                        HStack(spacing: 8) {
                            Image(systemName: item.symbolName)
                                .font(.system(size: 14))
                                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(item.iconColor.gradient))
                                .frame(width: 18)

                            Text(item.name)
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? .white : .primary)

                            Spacer()

                            Text(item.formattedSize)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 25)
                        .background(
                            isSelected
                            ? Color.accentColor
                            : (index.isMultiple(of: 2) ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor).opacity(0.5))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if item.isFolder, let url = item.localURL {
                                vm.loadMacPaneDirectory(url: url)
                            } else if let url = item.localURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded {
                                let flags = NSApp.currentEvent?.modifierFlags ?? []
                                if flags.contains(.command) {
                                    if vm.macPaneSelectedIds.contains(item.id) {
                                        vm.macPaneSelectedIds.remove(item.id)
                                    } else {
                                        vm.macPaneSelectedIds.insert(item.id)
                                    }
                                } else {
                                    vm.macPaneSelectedIds = [item.id]
                                }
                            }
                        )
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HStack {
                Text("Mac Path: \(vm.macPaneURL.path)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("เปิดใน Finder") {
                    NSWorkspace.shared.open(vm.macPaneURL)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
