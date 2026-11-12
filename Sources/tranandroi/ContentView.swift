import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        NavigationSplitView {
            FinderSidebarView(vm: vm)
                .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 290)
        } detail: {
            VStack(spacing: 0) {
                // Status / Notification Banner if present
                if let banner = vm.statusBannerMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(banner)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button {
                            vm.statusBannerMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.12))
                    Divider()
                }

                // Active File Transfer Progress Bar
                if let transfer = vm.transferStatus {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(transfer.title)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text("\(Int(transfer.progress * 100))%")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: transfer.progress)
                            .progressViewStyle(.linear)
                        Text(transfer.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    Divider()
                }

                // Main Content Area (with optional Dual-Pane Mac Split View and Right Inspector)
                HSplitView {
                    ZStack {
                        if vm.activeDomain == .android && vm.connectedDevice == nil {
                            AndroidConnectionEmptyStateView(vm: vm)
                        } else if vm.isLoadingFolder {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("กำลังโหลดข้อมูลโฟลเดอร์...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .controlBackgroundColor))
                        } else {
                            Group {
                                switch vm.viewMode {
                                case .icons:
                                    FinderIconsView(vm: vm)
                                case .list:
                                    FinderListView(vm: vm)
                                case .columns:
                                    FinderColumnsView(vm: vm)
                                case .gallery:
                                    FinderGalleryView(vm: vm)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(vm.isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 3)
                                    .padding(4)
                            )
                            .onDrop(of: [.fileURL], isTargeted: $vm.isDropTargeted) { providers in
                                handleDroppedFiles(providers: providers)
                            }
                        }
                    }
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

                    if vm.showDualPaneMacSplit {
                        MacCompanionSplitPane(vm: vm)
                            .frame(minWidth: 310, idealWidth: 360, maxWidth: 480)
                    }

                    if vm.showInspectorPane, let selected = vm.primarySelectedItem {
                        FinderInspectorPreviewPane(vm: vm, item: selected)
                            .frame(minWidth: 250, idealWidth: 270, maxWidth: 310)
                    }
                }

                // Finder Path Bar
                if vm.showPathBar && !vm.breadcrumbs.isEmpty {
                    Divider()
                    FinderPathBarView(vm: vm)
                }

                // Finder Status Bar
                if vm.showStatusBar {
                    Divider()
                    FinderStatusBarView(vm: vm)
                }
            }
            .navigationTitle(vm.currentFolderTitle)
            .navigationSubtitle(
                vm.activeDomain == .android
                ? (vm.connectedDevice?.displayName ?? "ไม่ได้เชื่อมต่อ Android")
                : "Mac — \(vm.activeMacURL.path)"
            )
            .searchable(text: $vm.searchText, placement: .toolbar, prompt: "ค้นหาใน \(vm.currentFolderTitle)")
            .toolbar {
                // Navigation Back / Forward
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        vm.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!vm.canGoBack)
                    .help("ย้อนกลับ (Back)")

                    Button {
                        vm.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!vm.canGoForward)
                    .help("ไปข้างหน้า (Forward)")
                }

                // Finder 4 View Modes Switcher (Icons, List, Columns, Gallery)
                ToolbarItem(placement: .principal) {
                    Picker("มุมมอง (View)", selection: $vm.viewMode) {
                        ForEach(FinderViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.symbolName)
                                .help(mode.titleThai)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    .help("สลับรูปแบบมุมมองแบบ Finder (Icons, List, Columns, Gallery)")
                }

                // Sort & Actions
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("เรียงตาม (Sort By)", selection: $vm.sortField) {
                            ForEach(SortField.allCases) { field in
                                Text(field.labelThai).tag(field)
                            }
                        }
                        Divider()
                        Toggle("เรียงจากน้อยไปมาก (Ascending)", isOn: $vm.sortAscending)
                        Toggle("แสดงไฟล์ที่ซ่อนอยู่ (Show Hidden Files)", isOn: $vm.showHiddenFiles)
                    } label: {
                        Label("เรียงลำดับ", systemImage: "arrow.up.arrow.down")
                    }
                    .help("เรียงลำดับไฟล์")

                    Button {
                        vm.uploadFromMacPrompt()
                    } label: {
                        Label("ส่งไฟล์เข้า Android", systemImage: "square.and.arrow.down")
                    }
                    .disabled(vm.connectedDevice == nil)
                    .help("เลือกไฟล์หรือโฟลเดอร์จาก Mac ส่งเข้ามือถือ Android")

                    Button {
                        vm.downloadSelectedAndroidItemsToMacPrompt()
                    } label: {
                        Label("คัดลอกลง Mac", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.selectedItems.filter { $0.domain == .android }.isEmpty)
                    .help("คัดลอกไฟล์ที่เลือกจาก Android ลงเครื่อง Mac")

                    Button {
                        vm.newFolderName = "untitled folder"
                        vm.showNewFolderSheet = true
                    } label: {
                        Label("โฟลเดอร์ใหม่", systemImage: "folder.badge.plus")
                    }
                    .help("สร้างโฟลเดอร์ใหม่ (⌘⇧N)")

                    Button {
                        Task {
                            if vm.activeDomain == .android && vm.connectedDevice == nil {
                                await vm.connectAndroidDevice()
                            } else {
                                await vm.reloadCurrentDirectory()
                            }
                        }
                    } label: {
                        Label("รีเฟรช", systemImage: "arrow.clockwise")
                    }
                    .help("รีเฟรชข้อมูล (⌘R)")

                    Button {
                        vm.showDualPaneMacSplit.toggle()
                    } label: {
                        Label("หน้าต่างคู่ Mac ↔ Android", systemImage: "rectangle.split.2x1")
                    }
                    .help("เปิด/ปิด หน้าต่างคู่ Mac ↔ Android เพื่อโอนไฟล์ข้ามฝั่งอย่างรวดเร็ว")

                    Button {
                        vm.showInspectorPane.toggle()
                    } label: {
                        Label("ดูรายละเอียด (Inspector)", systemImage: "info.circle")
                    }
                    .help("เปิด/ปิด แถบข้อมูลไฟล์ด้านขวา")
                }
            }
        }
        .sheet(isPresented: $vm.showNewFolderSheet) {
            NewFolderDialogView(vm: vm)
        }
        .sheet(item: $vm.itemToRename) { item in
            RenameDialogView(vm: vm, item: item)
        }
    }

    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        guard vm.activeDomain == .android, vm.connectedDevice != nil else { return false }
        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            collectedURLs.append(url)
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !collectedURLs.isEmpty {
                vm.uploadLocalURLsToCurrentAndroidFolder(collectedURLs)
            }
        }
        return true
    }
}

// MARK: - Finder Left Sidebar

struct FinderSidebarView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        List(selection: $vm.selectedSidebarId) {
            Section("Android Device (USB MTP)") {
                if let dev = vm.connectedDevice {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dev.displayName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .lineLimit(1)
                                Text(dev.modelName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await vm.connectAndroidDevice() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("เชื่อมต่อใหม่")
                        }

                        if let vol = vm.activeStorageVolume {
                            ProgressView(value: vol.usedFraction)
                                .tint(vol.usedFraction > 0.85 ? .orange : .blue)
                            Text(vol.formattedSummary)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    ForEach(dev.storages) { storage in
                        Button {
                            vm.selectedSidebarId = "storage-\(storage.id)"
                            Task { await vm.openAndroidStorageRoot(storage: storage) }
                        } label: {
                            Label(storage.description, systemImage: "internaldrive.fill")
                        }
                        .buttonStyle(.plain)
                        .tag("storage-\(storage.id)")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(vm.lockedByAppName != nil ? Color.orange : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(vm.lockedByAppName != nil ? "USB ถูกล็อกโดย \(vm.lockedByAppName!)" : "ยังไม่ได้เชื่อมต่อมือถือ")
                                .font(.system(size: 11.5, weight: .medium))
                        }

                        if let lockedApp = vm.lockedByAppName {
                            Button {
                                Task { await vm.unlockUSBAndReconnect() }
                            } label: {
                                Label("ปิด \(lockedApp) แล้วเชื่อมต่อ", systemImage: "bolt.horizontal.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        } else {
                            Button {
                                Task { await vm.connectAndroidDevice() }
                            } label: {
                                Label("ค้นหามือถือ Android", systemImage: "cable.connector")
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Android Favorites") {
                ForEach(vm.androidQuickFolders, id: \.name) { fav in
                    Button {
                        vm.selectedSidebarId = "android-quick-\(fav.name)"
                        Task {
                            await vm.openAndroidQuickFolder(name: fav.name, pathComponents: fav.path)
                        }
                    } label: {
                        Label(fav.name, systemImage: fav.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag("android-quick-\(fav.name)")
                }
            }

            Section("Mac Favorites") {
                ForEach(vm.macQuickFolders, id: \.name) { folder in
                    Button {
                        vm.selectedSidebarId = "mac-quick-\(folder.name)"
                        vm.openMacFolder(url: folder.url)
                    } label: {
                        Label(folder.name, systemImage: folder.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag("mac-quick-\(folder.name)")
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Empty / Locked USB Connection State View

struct AndroidConnectionEmptyStateView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: vm.lockedByAppName != nil ? "lock.trianglebadge.exclamationmark.fill" : "iphone.and.arrow.forward")
                .font(.system(size: 56))
                .foregroundStyle(vm.lockedByAppName != nil ? Color.orange.gradient : Color.accentColor.gradient)

            Text(vm.lockedByAppName != nil
                 ? "พอร์ต USB กำลังถูกใช้งานโดย \(vm.lockedByAppName!)"
                 : "เชื่อมต่อมือถือ Android (เช่น Galaxy S25 Ultra)")
                .font(.title2.bold())

            if let err = vm.connectionError {
                Text(err)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("1. เสียบสาย USB เข้ากับ Mac และปลดล็อกหน้าจอมือถือ", systemImage: "1.circle.fill")
                Label("2. ปัดแถบแจ้งเตือนบนมือถือ เลือกโหมด USB เป็น 'Transferring files / Android Auto'", systemImage: "2.circle.fill")
                Label("3. หากเปิดแอป OpenMTP หรือ Image Capture ค้างไว้ ให้กดปุ่มปลดล็อกด้านล่างเพื่อสลับมาใช้ tranandroi", systemImage: "3.circle.fill")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )

            HStack(spacing: 12) {
                if let lockedApp = vm.lockedByAppName {
                    Button {
                        Task { await vm.unlockUSBAndReconnect() }
                    } label: {
                        Label("ปิด \(lockedApp) และเชื่อมต่อ tranandroi ทันที", systemImage: "bolt.fill")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                }

                Button {
                    Task { await vm.connectAndroidDevice() }
                } label: {
                    Label(vm.isConnecting ? "กำลังเชื่อมต่อ..." : "ลองเชื่อมต่อใหม่ (Refresh USB)", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.isConnecting)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Finder Bottom Path Bar & Status Bar

struct FinderPathBarView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Image(systemName: vm.activeDomain == .android ? "iphone" : "laptopcomputer")
                    .font(.system(size: 11))
                    .foregroundStyle(vm.activeDomain == .android ? .green : .blue)

                ForEach(Array(vm.breadcrumbs.enumerated()), id: \.element.id) { idx, crumb in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        vm.navigateToBreadcrumb(crumb)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: idx == 0 ? "internaldrive.fill" : "folder.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(idx == 0 ? .secondary : Color(red: 0.25, green: 0.66, blue: 0.96))
                            Text(crumb.title)
                                .font(.system(size: 11.5, weight: idx == vm.breadcrumbs.count - 1 ? .semibold : .regular))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FinderStatusBarView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        let count = vm.filteredAndSortedItems.count
        let selCount = vm.selectedItemIds.count

        HStack {
            Text("ลากไฟล์จาก Finder มาวางในหน้าต่างนี้เพื่อส่งเข้า Android ได้ทันที")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Spacer()

            HStack(spacing: 6) {
                Text(selCount > 0 ? "\(selCount) of \(count) selected" : "\(count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if vm.activeDomain == .android, let vol = vm.activeStorageVolume {
                    Text("• \(vol.formattedFree) available")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if vm.viewMode == .icons {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Slider(value: $vm.iconGridSize, in: 56...140)
                        .frame(width: 90)
                        .controlSize(.mini)
                    Image(systemName: "photo")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Dialog Sheets (New Folder & Rename)

struct NewFolderDialogView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("สร้างโฟลเดอร์ใหม่ (New Folder)")
                .font(.headline)

            TextField("ชื่อโฟลเดอร์", text: $vm.newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit {
                    vm.createNewFolder()
                }

            HStack {
                Spacer()
                Button("ยกเลิก") {
                    vm.showNewFolderSheet = false
                }
                Button("สร้าง (Create)") {
                    vm.createNewFolder()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

struct RenameDialogView: View {
    @ObservedObject var vm: AppViewModel
    let item: FileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("เปลี่ยนชื่อ '\(item.name)'")
                .font(.headline)

            TextField("ชื่อใหม่", text: $vm.renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit {
                    vm.confirmRename()
                }

            HStack {
                Spacer()
                Button("ยกเลิก") {
                    vm.itemToRename = nil
                }
                Button("บันทึก") {
                    vm.confirmRename()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}
