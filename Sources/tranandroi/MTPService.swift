import Foundation
import CLibMTP

enum MTPConnectionResult {
    case connected(ConnectedAndroidDevice)
    case noDeviceFound
    case lockedByProcess(String)
    case openFailed(String)
}

final class MTPProgressContext {
    let handler: (UInt64, UInt64) -> Void
    init(handler: @escaping (UInt64, UInt64) -> Void) {
        self.handler = handler
    }
}

private let mtpProgressBridge: LIBMTP_progressfunc_t = { sent, total, dataPtr in
    guard let dataPtr = dataPtr else { return 0 }
    let context = Unmanaged<MTPProgressContext>.fromOpaque(dataPtr).takeUnretainedValue()
    context.handler(sent, total)
    return 0
}

final class MTPService: @unchecked Sendable {
    static let shared = MTPService()
    static let rootParentId: UInt32 = 0xffffffff // LIBMTP_FILES_AND_FOLDERS_ROOT

    private let queue = DispatchQueue(label: "com.lamud.tranandroi.mtpQueue", qos: .userInitiated)
    private var isInitialized = false
    private var activeDevice: UnsafeMutablePointer<LIBMTP_mtpdevice_t>?
    private var thumbnailCache = NSCache<NSNumber, NSData>()

    private init() {
        thumbnailCache.countLimit = 400
    }

    func checkConflictingProcesses() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            var conflicts: Set<String> = []
            for line in output.components(separatedBy: .newlines) {
                if line.contains("OpenMTP.app/Contents/MacOS/OpenMTP") {
                    conflicts.insert("OpenMTP")
                } else if line.contains("Android File Transfer") {
                    conflicts.insert("Android File Transfer")
                } else if line.contains("MacDroid") {
                    conflicts.insert("MacDroid")
                } else if line.contains("SmartSwitch") {
                    conflicts.insert("Samsung Smart Switch")
                }
            }
            return Array(conflicts).sorted()
        } catch {
            return []
        }
    }

    func closeConflictingProcesses() {
        let targets = ["OpenMTP", "Android File Transfer", "ptpcamerad"]
        for name in targets {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            p.arguments = [name]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func killPTPCameraDaemonSilently() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["-9", "ptpcamerad"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    func connect() async -> MTPConnectionResult {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: .openFailed("Service deallocated"))
                    return
                }
                let result = self.connectSync()
                continuation.resume(returning: result)
            }
        }
    }

    private func connectSync() -> MTPConnectionResult {
        if !isInitialized {
            LIBMTP_Init()
            isInitialized = true
        }

        if let existing = activeDevice {
            LIBMTP_Release_Device(existing)
            activeDevice = nil
        }

        killPTPCameraDaemonSilently()

        var rawDevicesPtr: UnsafeMutablePointer<LIBMTP_raw_device_t>?
        var numDevices: Int32 = 0

        let detectErr = LIBMTP_Detect_Raw_Devices(&rawDevicesPtr, &numDevices)
        defer {
            if let ptr = rawDevicesPtr {
                free(ptr)
            }
        }

        if detectErr == LIBMTP_ERROR_NO_DEVICE_ATTACHED || numDevices <= 0 || rawDevicesPtr == nil {
            let conflicts = checkConflictingProcesses()
            if !conflicts.isEmpty {
                return .lockedByProcess(conflicts.joined(separator: ", "))
            }
            return .noDeviceFound
        }

        guard let rawDevices = rawDevicesPtr else {
            return .noDeviceFound
        }

        guard let device = LIBMTP_Open_Raw_Device_Uncached(&rawDevices[0]) else {
            let conflicts = checkConflictingProcesses()
            if !conflicts.isEmpty {
                return .lockedByProcess(conflicts.joined(separator: ", "))
            }
            return .openFailed("ไม่สามารถเปิด USB MTP ได้ กรุณาปลดล็อกหน้าจอมือถือ และเลือกโหมด USB เป็น Transferring files (หรือปิดแอปที่แย่ง USB เช่น OpenMTP)")
        }

        self.activeDevice = device
        _ = LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED)

        let manufacturer = readCStringAndFree(LIBMTP_Get_Manufacturername(device)) ?? "Samsung"
        let model = readCStringAndFree(LIBMTP_Get_Modelname(device)) ?? "Android Device"
        let friendly = readCStringAndFree(LIBMTP_Get_Friendlyname(device)) ?? ""
        let serial = readCStringAndFree(LIBMTP_Get_Serialnumber(device)) ?? ""

        let storages = readStoragesSync(from: device)
        let info = ConnectedAndroidDevice(
            manufacturer: manufacturer,
            modelName: model,
            friendlyName: friendly,
            serialNumber: serial,
            storages: storages
        )
        return .connected(info)
    }

    func disconnect() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                if let dev = self?.activeDevice {
                    LIBMTP_Release_Device(dev)
                    self?.activeDevice = nil
                }
                continuation.resume()
            }
        }
    }

    func refreshStorages() async -> [StorageVolume] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: [])
                    return
                }
                _ = LIBMTP_Get_Storage(dev, LIBMTP_STORAGE_SORTBY_NOTSORTED)
                let list = self.readStoragesSync(from: dev)
                continuation.resume(returning: list)
            }
        }
    }

    private func readStoragesSync(from device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) -> [StorageVolume] {
        var result: [StorageVolume] = []
        var cursor = device.pointee.storage
        while let current = cursor {
            let storage = current.pointee
            let desc: String
            if let descPtr = storage.StorageDescription {
                desc = String(cString: descPtr)
            } else {
                desc = "Internal Shared Storage"
            }
            let volume = StorageVolume(
                id: storage.id,
                description: desc.isEmpty ? "Internal Shared Storage" : desc,
                maxCapacity: storage.MaxCapacity,
                freeSpace: storage.FreeSpaceInBytes
            )
            result.append(volume)
            cursor = storage.next
        }
        return result
    }

    func listDirectory(storageId: UInt32, parentId: UInt32) async -> [FileItem] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: [])
                    return
                }
                let items = self.listDirectorySync(device: dev, storageId: storageId, parentId: parentId)
                continuation.resume(returning: items)
            }
        }
    }

    private func listDirectorySync(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>,
        storageId: UInt32,
        parentId: UInt32
    ) -> [FileItem] {
        var items: [FileItem] = []
        var currentPtr = LIBMTP_Get_Files_And_Folders(device, storageId, parentId)
        while let ptr = currentPtr {
            let entry = ptr.pointee
            let nextPtr = entry.next
            let name = entry.filename != nil ? String(cString: entry.filename) : "Untitled"
            let isFolder = (entry.filetype == LIBMTP_FILETYPE_FOLDER)
            let modDate = Date(timeIntervalSince1970: TimeInterval(entry.modificationdate))

            let item = FileItem(
                id: "android-\(entry.storage_id)-\(entry.item_id)",
                domain: .android,
                name: name,
                isFolder: isFolder,
                size: entry.filesize,
                modificationDate: modDate,
                storageId: entry.storage_id,
                itemId: entry.item_id,
                parentId: entry.parent_id,
                localURL: nil
            )
            items.append(item)
            LIBMTP_destroy_file_t(ptr)
            currentPtr = nextPtr
        }
        return items
    }

    func resolvePath(storageId: UInt32, pathComponents: [String]) async -> [(name: String, folderId: UInt32)]? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: nil)
                    return
                }
                var currentParent = MTPService.rootParentId
                var trail: [(name: String, folderId: UInt32)] = []

                for segment in pathComponents {
                    let listing = self.listDirectorySync(device: dev, storageId: storageId, parentId: currentParent)
                    if let match = listing.first(where: { $0.isFolder && $0.name.caseInsensitiveCompare(segment) == .orderedSame }) {
                        trail.append((name: match.name, folderId: match.itemId))
                        currentParent = match.itemId
                    } else {
                        continuation.resume(returning: nil)
                        return
                    }
                }
                continuation.resume(returning: trail)
            }
        }
    }

    func fetchThumbnail(for item: FileItem) async -> Data? {
        let key = NSNumber(value: item.itemId)
        if let cached = thumbnailCache.object(forKey: key) {
            return Data(referencing: cached)
        }
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: nil)
                    return
                }
                var dataPtr: UnsafeMutablePointer<UInt8>?
                var size: UInt32 = 0
                let ret = LIBMTP_Get_Thumbnail(dev, item.itemId, &dataPtr, &size)
                if ret == 0, let ptr = dataPtr, size > 0 {
                    let data = Data(bytes: ptr, count: Int(size))
                    free(ptr)
                    self.thumbnailCache.setObject(data as NSData, forKey: key)
                    continuation.resume(returning: data)
                } else {
                    if let ptr = dataPtr { free(ptr) }
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func downloadItem(
        _ item: FileItem,
        toDirectory destinationFolder: URL,
        progress: @escaping @Sendable (UInt64, UInt64) -> Void
    ) async -> Result<URL, Error> {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: .failure(NSError(domain: "MTP", code: -1, userInfo: [NSLocalizedDescriptionKey: "ไม่ได้เชื่อมต่ออุปกรณ์ Android"])))
                    return
                }
                do {
                    let outURL = try self.downloadItemRecursiveSync(
                        device: dev,
                        item: item,
                        toDirectory: destinationFolder,
                        progress: progress
                    )
                    continuation.resume(returning: .success(outURL))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    private func downloadItemRecursiveSync(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>,
        item: FileItem,
        toDirectory destinationFolder: URL,
        progress: @escaping (UInt64, UInt64) -> Void
    ) throws -> URL {
        let targetURL = destinationFolder.appendingPathComponent(item.name)

        if item.isFolder {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            let children = listDirectorySync(device: device, storageId: item.storageId, parentId: item.itemId)
            for child in children {
                _ = try downloadItemRecursiveSync(device: device, item: child, toDirectory: targetURL, progress: progress)
            }
            return targetURL
        } else {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
            }
            let ctx = MTPProgressContext(handler: progress)
            let unmanaged = Unmanaged.passUnretained(ctx)
            let res = targetURL.path.withCString { cPath in
                LIBMTP_Get_File_To_File(device, item.itemId, cPath, mtpProgressBridge, unmanaged.toOpaque())
            }
            if res != 0 {
                throw NSError(domain: "MTP", code: Int(res), userInfo: [NSLocalizedDescriptionKey: "ดาวน์โหลดไฟล์ '\(item.name)' ไม่สำเร็จ"])
            }
            return targetURL
        }
    }

    func uploadLocalURL(
        _ sourceURL: URL,
        storageId: UInt32,
        parentId: UInt32,
        progress: @escaping @Sendable (UInt64, UInt64) -> Void
    ) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: .failure(NSError(domain: "MTP", code: -1, userInfo: [NSLocalizedDescriptionKey: "ไม่ได้เชื่อมต่ออุปกรณ์ Android"])))
                    return
                }
                do {
                    try self.uploadRecursiveSync(
                        device: dev,
                        sourceURL: sourceURL,
                        storageId: storageId,
                        parentId: parentId,
                        progress: progress
                    )
                    continuation.resume(returning: .success(()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    private func uploadRecursiveSync(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>,
        sourceURL: URL,
        storageId: UInt32,
        parentId: UInt32,
        progress: @escaping (UInt64, UInt64) -> Void
    ) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            throw NSError(domain: "MTP", code: -2, userInfo: [NSLocalizedDescriptionKey: "ไม่พบไฟล์ต้นทาง \(sourceURL.lastPathComponent)"])
        }

        if isDir.boolValue {
            let folderName = sourceURL.lastPathComponent
            let newFolderId = createFolderSync(device: device, name: folderName, storageId: storageId, parentId: parentId)
            let targetFolderId: UInt32
            if newFolderId != 0 {
                targetFolderId = newFolderId
            } else {
                // Check if folder already exists
                let existing = listDirectorySync(device: device, storageId: storageId, parentId: parentId)
                if let match = existing.first(where: { $0.isFolder && $0.name == folderName }) {
                    targetFolderId = match.itemId
                } else {
                    throw NSError(domain: "MTP", code: -3, userInfo: [NSLocalizedDescriptionKey: "ไม่สามารถสร้างโฟลเดอร์ '\(folderName)' บน Android ได้"])
                }
            }

            let contents = try FileManager.default.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for childURL in contents {
                try uploadRecursiveSync(
                    device: device,
                    sourceURL: childURL,
                    storageId: storageId,
                    parentId: targetFolderId,
                    progress: progress
                )
            }
        } else {
            let attrs = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()

            guard let genfile = LIBMTP_new_file_t() else {
                throw NSError(domain: "MTP", code: -4, userInfo: [NSLocalizedDescriptionKey: "ไม่สามารถจองหน่วยความจำสำหรับส่งไฟล์"])
            }
            defer {
                LIBMTP_destroy_file_t(genfile)
            }

            genfile.pointee.filesize = fileSize
            genfile.pointee.filename = strdup(sourceURL.lastPathComponent)
            genfile.pointee.modificationdate = time_t(modDate.timeIntervalSince1970)
            genfile.pointee.filetype = mapFileType(for: sourceURL.pathExtension.lowercased())
            genfile.pointee.parent_id = parentId
            genfile.pointee.storage_id = storageId

            let ctx = MTPProgressContext(handler: progress)
            let unmanaged = Unmanaged.passUnretained(ctx)
            let res = sourceURL.path.withCString { cPath in
                LIBMTP_Send_File_From_File(device, cPath, genfile, mtpProgressBridge, unmanaged.toOpaque())
            }
            if res != 0 {
                throw NSError(domain: "MTP", code: Int(res), userInfo: [NSLocalizedDescriptionKey: "อัปโหลดไฟล์ '\(sourceURL.lastPathComponent)' ไม่สำเร็จ"])
            }
        }
    }

    func createFolder(name: String, storageId: UInt32, parentId: UInt32) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: false)
                    return
                }
                let newId = self.createFolderSync(device: dev, name: name, storageId: storageId, parentId: parentId)
                continuation.resume(returning: newId != 0)
            }
        }
    }

    private func createFolderSync(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>,
        name: String,
        storageId: UInt32,
        parentId: UInt32
    ) -> UInt32 {
        let cStr = strdup(name)
        defer { free(cStr) }
        guard let validCStr = cStr else { return 0 }
        return LIBMTP_Create_Folder(device, validCStr, parentId, storageId)
    }

    func deleteItem(_ item: FileItem) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: false)
                    return
                }
                let res = LIBMTP_Delete_Object(dev, item.itemId)
                continuation.resume(returning: res == 0)
            }
        }
    }

    func renameItem(_ item: FileItem, newName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let dev = self.activeDevice else {
                    continuation.resume(returning: false)
                    return
                }
                let cStr = strdup(newName)
                defer { free(cStr) }
                guard let validCStr = cStr else {
                    continuation.resume(returning: false)
                    return
                }
                let res = LIBMTP_Set_Object_Filename(dev, item.itemId, validCStr)
                continuation.resume(returning: res == 0)
            }
        }
    }

    private func mapFileType(for ext: String) -> LIBMTP_filetype_t {
        switch ext {
        case "jpg", "jpeg": return LIBMTP_FILETYPE_JPEG
        case "png": return LIBMTP_FILETYPE_PNG
        case "gif": return LIBMTP_FILETYPE_GIF
        case "bmp": return LIBMTP_FILETYPE_BMP
        case "mp3": return LIBMTP_FILETYPE_MP3
        case "m4a": return LIBMTP_FILETYPE_M4A
        case "wav": return LIBMTP_FILETYPE_WAV
        case "flac": return LIBMTP_FILETYPE_FLAC
        case "ogg": return LIBMTP_FILETYPE_OGG
        case "mp4": return LIBMTP_FILETYPE_MP4
        case "mov": return LIBMTP_FILETYPE_QT
        case "avi": return LIBMTP_FILETYPE_AVI
        case "txt", "md", "log": return LIBMTP_FILETYPE_TEXT
        case "html", "htm": return LIBMTP_FILETYPE_HTML
        case "xml": return LIBMTP_FILETYPE_XML
        default: return LIBMTP_FILETYPE_UNKNOWN
        }
    }

    private func readCStringAndFree(_ ptr: UnsafeMutablePointer<CChar>?) -> String? {
        guard let ptr = ptr else { return nil }
        let str = String(cString: ptr)
        free(ptr)
        return str
    }
}
