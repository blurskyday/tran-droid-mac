import Foundation
import SwiftUI
import AppKit

struct MillerColumnLevel: Identifiable {
    let id: String
    let title: String
    let domain: FileDomain
    let storageId: UInt32
    let folderId: UInt32
    let macURL: URL?
    var items: [FileItem]
    var selectedItemId: String?
}

@MainActor
final class AppViewModel: ObservableObject {
    // Device & Connection State
    @Published var connectedDevice: ConnectedAndroidDevice?
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?
    @Published var lockedByAppName: String?

    // Finder View Settings
    @Published var viewMode: FinderViewMode = .icons
    @Published var iconGridSize: Double = 84.0
    @Published var sortField: SortField = .name
    @Published var sortAscending: Bool = true
    @Published var searchText: String = ""
    @Published var showHiddenFiles: Bool = false
    @Published var showPathBar: Bool = true
    @Published var showStatusBar: Bool = true
    @Published var showInspectorPane: Bool = false
    @Published var showDualPaneMacSplit: Bool = false
    @Published var isDropTargeted: Bool = false

    // Active Browser State (Primary Pane)
    @Published var activeDomain: FileDomain = .android
    @Published var activeStorageId: UInt32 = 0
    @Published var activeFolderId: UInt32 = MTPService.rootParentId
    @Published var activeMacURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var breadcrumbs: [BreadcrumbStep] = []

    @Published var items: [FileItem] = []
    @Published var isLoadingFolder: Bool = false
    @Published var selectedItemIds: Set<String> = []
    @Published var selectedSidebarId: String? = "android-quick-DCIM"

    // Miller Columns State
    @Published var columnLevels: [MillerColumnLevel] = []

    // Secondary Mac Pane (for Dual-Pane Split Mode: Mac <-> Android)
    @Published var macPaneURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var macPaneItems: [FileItem] = []
    @Published var macPaneSelectedIds: Set<String> = []

    // Navigation History
    private var backStack: [[BreadcrumbStep]] = []
    private var forwardStack: [[BreadcrumbStep]] = []
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    // Transfers & Dialogs
    @Published var transferStatus: TransferStatus?
    @Published var statusBannerMessage: String?
    @Published var showNewFolderSheet: Bool = false
    @Published var newFolderName: String = "untitled folder"
    @Published var itemToRename: FileItem?
    @Published var renameText: String = ""
    @Published var previewImage: NSImage?
    @Published var thumbnails: [UInt32: NSImage] = [:]

    let androidQuickFolders: [(name: String, path: [String], icon: String)] = [
        ("Internal Storage", [], "internaldrive.fill"),
        ("Camera (S25 Ultra)", ["DCIM", "Camera"], "camera.fill"),
        ("DCIM", ["DCIM"], "photo.on.rectangle.angled"),
        ("Pictures", ["Pictures"], "photo.fill"),
        ("Download", ["Download"], "arrow.down.circle.fill"),
        ("Movies", ["Movies"], "film.fill"),
        ("Music", ["Music"], "music.note"),
        ("Documents", ["Documents"], "doc.fill")
    ]

    var macQuickFolders: [(name: String, url: URL, icon: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("Desktop", home.appendingPathComponent("Desktop"), "menubar.dock.rectangle"),
            ("Downloads", home.appendingPathComponent("Downloads"), "arrow.down.circle"),
            ("Documents", home.appendingPathComponent("Documents"), "doc"),
            ("Pictures", home.appendingPathComponent("Pictures"), "photo"),
            ("Movies", home.appendingPathComponent("Movies"), "film"),
            ("Home (\(NSUserName()))", home, "house")
        ]
    }

    init() {
        loadMacPaneDirectory(url: macPaneURL)
        Task {
            await connectAndroidDevice()
        }
    }

    var filteredAndSortedItems: [FileItem] {
        sortAndFilter(rawItems: items)
    }

    func sortAndFilter(rawItems: [FileItem]) -> [FileItem] {
        let filtered = rawItems.filter { item in
            if !showHiddenFiles && item.name.hasPrefix(".") {
                return false
            }
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                return item.name.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }

        return filtered.sorted { a, b in
            // Folders always on top like macOS Finder "Keep folders on top"
            if a.isFolder != b.isFolder {
                return a.isFolder && !b.isFolder
            }
            let comparison: ComparisonResult
            switch sortField {
            case .name:
                comparison = a.name.localizedStandardCompare(b.name)
            case .dateModified:
                if a.modificationDate == b.modificationDate {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = a.modificationDate < b.modificationDate ? .orderedAscending : .orderedDescending
                }
            case .size:
                if a.size == b.size {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = a.size < b.size ? .orderedAscending : .orderedDescending
                }
            case .kind:
                comparison = a.kindDescription.localizedStandardCompare(b.kindDescription)
            }
            return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
        }
    }

    var primarySelectedItem: FileItem? {
        guard let firstId = selectedItemIds.first else { return nil }
        return items.first(where: { $0.id == firstId })
    }

    var selectedItems: [FileItem] {
        items.filter { selectedItemIds.contains($0.id) }
    }

    var currentFolderTitle: String {
        breadcrumbs.last?.title ?? (connectedDevice?.displayName ?? "tranandroi")
    }

    var activeStorageVolume: StorageVolume? {
        guard let dev = connectedDevice else { return nil }
        return dev.storages.first(where: { $0.id == activeStorageId }) ?? dev.storages.first
    }

    // MARK: - Device Connection

    func connectAndroidDevice() async {
        isConnecting = true
        connectionError = nil
        lockedByAppName = nil

        let result = await MTPService.shared.connect()
        isConnecting = false

        switch result {
        case .connected(let device):
            self.connectedDevice = device
            if let firstStorage = device.storages.first {
                self.activeStorageId = firstStorage.id
                await openAndroidStorageRoot(storage: firstStorage, recordHistory: false)
            }
        case .noDeviceFound:
            self.connectedDevice = nil
            self.connectionError = "ไม่พบมือถือ Android ที่เชื่อมต่อผ่านสาย USB (กรุณาเสียบสายและเลือกโหมด Transferring files)"
        case .lockedByProcess(let appName):
            self.connectedDevice = nil
            self.lockedByAppName = appName
            self.connectionError = "พอร์ต USB ของมือถือถูกใช้งานอยู่โดยแอป \(appName) (ระบบ MTP อนุญาตให้เปิดได้ทีละแอป)"
        case .openFailed(let message):
            self.connectedDevice = nil
            self.connectionError = message
        }
    }

    func unlockUSBAndReconnect() async {
        isConnecting = true
        connectionError = nil
        await Task.detached {
            MTPService.shared.closeConflictingProcesses()
        }.value
        await connectAndroidDevice()
    }

    // MARK: - Navigation

    func openAndroidStorageRoot(storage: StorageVolume, recordHistory: Bool = true) async {
        if recordHistory && !breadcrumbs.isEmpty {
            pushHistory()
        }
        activeDomain = .android
        activeStorageId = storage.id
        activeFolderId = MTPService.rootParentId
        let rootStep = BreadcrumbStep(
            id: "android-root-\(storage.id)",
            title: storage.description,
            domain: .android,
            storageId: storage.id,
            folderId: MTPService.rootParentId,
            macURL: nil
        )
        breadcrumbs = [rootStep]
        await reloadCurrentDirectory(resetColumnsToRoot: true)
    }

    func openAndroidQuickFolder(name: String, pathComponents: [String]) async {
        guard let device = connectedDevice,
              let storage = device.storages.first(where: { $0.id == activeStorageId }) ?? device.storages.first else {
            await connectAndroidDevice()
            return
        }

        if pathComponents.isEmpty {
            await openAndroidStorageRoot(storage: storage)
            return
        }

        isLoadingFolder = true
        if !breadcrumbs.isEmpty {
            pushHistory()
        }

        activeDomain = .android
        activeStorageId = storage.id
        let rootStep = BreadcrumbStep(
            id: "android-root-\(storage.id)",
            title: storage.description,
            domain: .android,
            storageId: storage.id,
            folderId: MTPService.rootParentId,
            macURL: nil
        )

        if let resolved = await MTPService.shared.resolvePath(storageId: storage.id, pathComponents: pathComponents),
           let last = resolved.last {
            var newCrumbs = [rootStep]
            for step in resolved {
                newCrumbs.append(
                    BreadcrumbStep(
                        id: "android-\(storage.id)-\(step.folderId)",
                        title: step.name,
                        domain: .android,
                        storageId: storage.id,
                        folderId: step.folderId,
                        macURL: nil
                    )
                )
            }
            breadcrumbs = newCrumbs
            activeFolderId = last.folderId
            await reloadCurrentDirectory(resetColumnsToRoot: true)
        } else {
            isLoadingFolder = false
            showStatusMessage("ไม่พบโฟลเดอร์ \(pathComponents.joined(separator: "/")) บนอุปกรณ์")
            await openAndroidStorageRoot(storage: storage, recordHistory: false)
        }
    }

    func openMacFolder(url: URL, recordHistory: Bool = true) {
        if recordHistory && !breadcrumbs.isEmpty {
            pushHistory()
        }
        activeDomain = .mac
        activeMacURL = url

        var crumbs: [BreadcrumbStep] = []
        var current = url.standardizedFileURL
        var chain: [URL] = []
        while current.path != "/" {
            chain.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        for u in chain.reversed() {
            crumbs.append(
                BreadcrumbStep(
                    id: "mac-\(u.path)",
                    title: u.lastPathComponent.isEmpty ? "Macintosh HD" : u.lastPathComponent,
                    domain: .mac,
                    storageId: 0,
                    folderId: 0,
                    macURL: u
                )
            )
        }
        breadcrumbs = crumbs
        Task {
            await reloadCurrentDirectory(resetColumnsToRoot: true)
        }
    }

    func enterFolder(_ item: FileItem) {
        guard item.isFolder else {
            openOrPreviewFile(item)
            return
        }
        pushHistory()
        if item.domain == .android {
            activeDomain = .android
            activeStorageId = item.storageId
            activeFolderId = item.itemId
            breadcrumbs.append(
                BreadcrumbStep(
                    id: "android-\(item.storageId)-\(item.itemId)",
                    title: item.name,
                    domain: .android,
                    storageId: item.storageId,
                    folderId: item.itemId,
                    macURL: nil
                )
            )
            Task {
                await reloadCurrentDirectory(resetColumnsToRoot: false)
            }
        } else if let url = item.localURL {
            openMacFolder(url: url, recordHistory: false)
        }
    }

    func navigateToBreadcrumb(_ step: BreadcrumbStep) {
        guard let idx = breadcrumbs.firstIndex(of: step) else { return }
        if idx == breadcrumbs.count - 1 { return }
        pushHistory()
        breadcrumbs = Array(breadcrumbs.prefix(through: idx))
        applyTopBreadcrumb(resetColumnsToRoot: true)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(breadcrumbs)
        breadcrumbs = previous
        updateHistoryButtons()
        applyTopBreadcrumb(resetColumnsToRoot: true)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(breadcrumbs)
        breadcrumbs = next
        updateHistoryButtons()
        applyTopBreadcrumb(resetColumnsToRoot: true)
    }

    private func pushHistory() {
        backStack.append(breadcrumbs)
        forwardStack.removeAll()
        updateHistoryButtons()
    }

    private func updateHistoryButtons() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    private func applyTopBreadcrumb(resetColumnsToRoot: Bool) {
        guard let top = breadcrumbs.last else { return }
        activeDomain = top.domain
        if top.domain == .android {
            activeStorageId = top.storageId
            activeFolderId = top.folderId
        } else if let url = top.macURL {
            activeMacURL = url
        }
        Task {
            await reloadCurrentDirectory(resetColumnsToRoot: resetColumnsToRoot)
        }
    }

    // MARK: - Loading Directories & Miller Columns

    func reloadCurrentDirectory(resetColumnsToRoot: Bool = false) async {
        isLoadingFolder = true
        selectedItemIds.removeAll()
        previewImage = nil

        if activeDomain == .android {
            let loaded = await MTPService.shared.listDirectory(storageId: activeStorageId, parentId: activeFolderId)
            self.items = loaded
            isLoadingFolder = false

            if resetColumnsToRoot || columnLevels.isEmpty {
                columnLevels = [
                    MillerColumnLevel(
                        id: "col-0-\(activeStorageId)-\(activeFolderId)",
                        title: currentFolderTitle,
                        domain: .android,
                        storageId: activeStorageId,
                        folderId: activeFolderId,
                        macURL: nil,
                        items: sortAndFilter(rawItems: loaded),
                        selectedItemId: nil
                    )
                ]
            }

            // Load image thumbnails in background for visible images
            Task {
                for item in loaded.prefix(60) where item.isImage {
                    if thumbnails[item.itemId] == nil {
                        if let data = await MTPService.shared.fetchThumbnail(for: item),
                           let img = NSImage(data: data) {
                            self.thumbnails[item.itemId] = img
                        }
                    }
                }
            }
        } else {
            let loaded = readLocalDirectory(url: activeMacURL)
            self.items = loaded
            isLoadingFolder = false

            if resetColumnsToRoot || columnLevels.isEmpty {
                columnLevels = [
                    MillerColumnLevel(
                        id: "col-0-mac-\(activeMacURL.path)",
                        title: activeMacURL.lastPathComponent,
                        domain: .mac,
                        storageId: 0,
                        folderId: 0,
                        macURL: activeMacURL,
                        items: sortAndFilter(rawItems: loaded),
                        selectedItemId: nil
                    )
                ]
            }
        }
    }

    func selectItemInMillerColumn(columnIndex: Int, item: FileItem) {
        guard columnIndex < columnLevels.count else { return }
        columnLevels[columnIndex].selectedItemId = item.id
        selectedItemIds = [item.id]

        // Trim columns to the right of columnIndex
        if columnLevels.count > columnIndex + 1 {
            columnLevels.removeSubrange((columnIndex + 1)..<columnLevels.count)
        }

        if item.isFolder {
            Task {
                if item.domain == .android {
                    let children = await MTPService.shared.listDirectory(storageId: item.storageId, parentId: item.itemId)
                    let newLevel = MillerColumnLevel(
                        id: "col-\(columnIndex + 1)-\(item.itemId)",
                        title: item.name,
                        domain: .android,
                        storageId: item.storageId,
                        folderId: item.itemId,
                        macURL: nil,
                        items: sortAndFilter(rawItems: children),
                        selectedItemId: nil
                    )
                    self.columnLevels.append(newLevel)
                    self.items = children
                    self.activeFolderId = item.itemId
                } else if let url = item.localURL {
                    let children = readLocalDirectory(url: url)
                    let newLevel = MillerColumnLevel(
                        id: "col-\(columnIndex + 1)-mac-\(url.path)",
                        title: item.name,
                        domain: .mac,
                        storageId: 0,
                        folderId: 0,
                        macURL: url,
                        items: sortAndFilter(rawItems: children),
                        selectedItemId: nil
                    )
                    self.columnLevels.append(newLevel)
                    self.items = children
                    self.activeMacURL = url
                }
            }
        } else {
            loadPreviewIfNeeded(for: item)
        }
    }

    func loadPreviewIfNeeded(for item: FileItem) {
        previewImage = nil
        if item.domain == .mac, let url = item.localURL, item.isImage {
            previewImage = NSImage(contentsOf: url)
        } else if item.domain == .android, item.isImage {
            if let thumb = thumbnails[item.itemId] {
                previewImage = thumb
            } else {
                Task {
                    if let data = await MTPService.shared.fetchThumbnail(for: item),
                       let img = NSImage(data: data) {
                        self.thumbnails[item.itemId] = img
                        if self.primarySelectedItem?.id == item.id {
                            self.previewImage = img
                        }
                    }
                }
            }
        }
    }

    func readLocalDirectory(url: URL) -> [FileItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: showHiddenFiles ? [] : [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { fileURL in
            let res = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = res?.isDirectory ?? false
            let size = UInt64(res?.fileSize ?? 0)
            let modDate = res?.contentModificationDate ?? Date()
            return FileItem(
                id: "mac-\(fileURL.path)",
                domain: .mac,
                name: fileURL.lastPathComponent,
                isFolder: isDir,
                size: size,
                modificationDate: modDate,
                storageId: 0,
                itemId: 0,
                parentId: 0,
                localURL: fileURL
            )
        }
    }

    func loadMacPaneDirectory(url: URL) {
        macPaneURL = url
        macPaneItems = sortAndFilter(rawItems: readLocalDirectory(url: url))
        macPaneSelectedIds.removeAll()
    }

    // MARK: - File Actions (Download, Upload, New Folder, Rename, Delete, Quick Look)

    func openOrPreviewFile(_ item: FileItem) {
        if item.domain == .mac, let url = item.localURL {
            NSWorkspace.shared.open(url)
            return
        }

        // Download Android file to temporary preview directory and open with default macOS app
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("tranandroi_preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        Task {
            transferStatus = TransferStatus(
                title: "กำลังเปิดไฟล์ \(item.name)...",
                subtitle: "ดาวน์โหลดชั่วคราวเพื่อเปิดบน Mac",
                sentBytes: 0,
                totalBytes: max(item.size, 1),
                isRunning: true
            )
            let result = await MTPService.shared.downloadItem(item, toDirectory: tempDir) { [weak self] sent, total in
                Task { @MainActor in
                    self?.transferStatus?.sentBytes = sent
                    self?.transferStatus?.totalBytes = max(total, 1)
                }
            }
            transferStatus = nil
            switch result {
            case .success(let localURL):
                NSWorkspace.shared.open(localURL)
            case .failure(let error):
                showStatusMessage(error.localizedDescription)
            }
        }
    }

    func downloadSelectedAndroidItemsToMacPrompt() {
        let targets = selectedItems.filter { $0.domain == .android }
        guard !targets.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = "เลือกโฟลเดอร์บน Mac ที่ต้องการบันทึกไฟล์"
        panel.prompt = "บันทึกที่นี่"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = macPaneURL

        if panel.runModal() == .OK, let destFolder = panel.url {
            downloadAndroidItems(targets, toMacDirectory: destFolder)
        }
    }

    func downloadAndroidItems(_ targets: [FileItem], toMacDirectory destFolder: URL) {
        guard !targets.isEmpty else { return }
        Task {
            for (index, item) in targets.enumerated() {
                transferStatus = TransferStatus(
                    title: "กำลังคัดลอกไป Mac (\(index + 1)/\(targets.count)): \(item.name)",
                    subtitle: "ปลายทาง: \(destFolder.lastPathComponent)",
                    sentBytes: 0,
                    totalBytes: max(item.size, 1),
                    isRunning: true
                )
                let res = await MTPService.shared.downloadItem(item, toDirectory: destFolder) { [weak self] sent, total in
                    Task { @MainActor in
                        self?.transferStatus?.sentBytes = sent
                        self?.transferStatus?.totalBytes = max(total, 1)
                    }
                }
                if case .failure(let err) = res {
                    showStatusMessage(err.localizedDescription)
                }
            }
            transferStatus = nil
            showStatusMessage("คัดลอก \(targets.count) รายการไปยัง '\(destFolder.lastPathComponent)' บน Mac เรียบร้อยแล้ว")
            loadMacPaneDirectory(url: macPaneURL)
            if activeDomain == .mac {
                await reloadCurrentDirectory()
            }
        }
    }

    func uploadFromMacPrompt() {
        guard connectedDevice != nil else {
            showStatusMessage("กรุณาเชื่อมต่อมือถือ Android ก่อนอัปโหลดไฟล์")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "เลือกไฟล์หรือโฟลเดอร์จาก Mac เพื่อส่งเข้า Android"
        panel.prompt = "ส่งเข้า Android"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = macPaneURL

        if panel.runModal() == .OK {
            uploadLocalURLsToCurrentAndroidFolder(panel.urls)
        }
    }

    func uploadSelectedMacPaneItemsToAndroid() {
        let selectedURLs = macPaneItems
            .filter { macPaneSelectedIds.contains($0.id) }
            .compactMap { $0.localURL }
        guard !selectedURLs.isEmpty else { return }
        uploadLocalURLsToCurrentAndroidFolder(selectedURLs)
    }

    func uploadLocalURLsToCurrentAndroidFolder(_ urls: [URL]) {
        guard !urls.isEmpty, connectedDevice != nil else { return }
        let targetStorage = activeStorageId
        let targetParent = activeDomain == .android ? activeFolderId : MTPService.rootParentId

        Task {
            for (index, url) in urls.enumerated() {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let fsize = (attrs?[.size] as? NSNumber)?.uint64Value ?? 1
                transferStatus = TransferStatus(
                    title: "กำลังส่งเข้า Android (\(index + 1)/\(urls.count)): \(url.lastPathComponent)",
                    subtitle: "ปลายทาง: \(currentFolderTitle)",
                    sentBytes: 0,
                    totalBytes: max(fsize, 1),
                    isRunning: true
                )
                let res = await MTPService.shared.uploadLocalURL(
                    url,
                    storageId: targetStorage,
                    parentId: targetParent
                ) { [weak self] sent, total in
                    Task { @MainActor in
                        self?.transferStatus?.sentBytes = sent
                        self?.transferStatus?.totalBytes = max(total, 1)
                    }
                }
                if case .failure(let err) = res {
                    showStatusMessage(err.localizedDescription)
                }
            }
            transferStatus = nil
            let updatedStorages = await MTPService.shared.refreshStorages()
            if let dev = connectedDevice {
                connectedDevice = ConnectedAndroidDevice(
                    manufacturer: dev.manufacturer,
                    modelName: dev.modelName,
                    friendlyName: dev.friendlyName,
                    serialNumber: dev.serialNumber,
                    storages: updatedStorages
                )
            }
            showStatusMessage("ส่งไฟล์ \(urls.count) รายการเข้า Android เรียบร้อยแล้ว")
            if activeDomain == .android {
                await reloadCurrentDirectory()
            }
        }
    }

    func createNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showNewFolderSheet = false

        Task {
            if activeDomain == .android {
                let ok = await MTPService.shared.createFolder(
                    name: trimmed,
                    storageId: activeStorageId,
                    parentId: activeFolderId
                )
                if ok {
                    showStatusMessage("สร้างโฟลเดอร์ '\(trimmed)' เรียบร้อยแล้ว")
                    await reloadCurrentDirectory()
                } else {
                    showStatusMessage("ไม่สามารถสร้างโฟลเดอร์ '\(trimmed)' ได้")
                }
            } else {
                let newURL = activeMacURL.appendingPathComponent(trimmed)
                do {
                    try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
                    await reloadCurrentDirectory()
                } catch {
                    showStatusMessage(error.localizedDescription)
                }
            }
        }
    }

    func beginRename(_ item: FileItem) {
        itemToRename = item
        renameText = item.name
    }

    func confirmRename() {
        guard let item = itemToRename else { return }
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        itemToRename = nil
        guard !newName.isEmpty, newName != item.name else { return }

        Task {
            if item.domain == .android {
                let ok = await MTPService.shared.renameItem(item, newName: newName)
                if ok {
                    showStatusMessage("เปลี่ยนชื่อเป็น '\(newName)' เรียบร้อยแล้ว")
                    await reloadCurrentDirectory()
                } else {
                    showStatusMessage("เปลี่ยนชื่อไม่สำเร็จ")
                }
            } else if let url = item.localURL {
                let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
                do {
                    try FileManager.default.moveItem(at: url, to: dest)
                    await reloadCurrentDirectory()
                } catch {
                    showStatusMessage(error.localizedDescription)
                }
            }
        }
    }

    func deleteSelectedItems() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "ยืนยันการลบ \(targets.count) รายการ?"
        alert.informativeText = "รายการที่ลบจาก Android MTP จะถูกลบออกจากเครื่องทันทีและไม่สามารถกู้คืนจาก Trash ได้"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "ลบ (Delete)")
        alert.addButton(withTitle: "ยกเลิก")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            for item in targets {
                if item.domain == .android {
                    _ = await MTPService.shared.deleteItem(item)
                } else if let url = item.localURL {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            }
            showStatusMessage("ลบ \(targets.count) รายการเรียบร้อยแล้ว")
            await reloadCurrentDirectory()
        }
    }

    func showStatusMessage(_ msg: String) {
        statusBannerMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.statusBannerMessage == msg {
                self.statusBannerMessage = nil
            }
        }
    }
}
