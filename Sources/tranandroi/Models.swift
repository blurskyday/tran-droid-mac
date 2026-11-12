import Foundation
import SwiftUI

enum FinderViewMode: String, CaseIterable, Identifiable {
    case icons = "Icons"
    case list = "List"
    case columns = "Columns"
    case gallery = "Gallery"

    var id: String { rawValue }

    var titleThai: String {
        switch self {
        case .icons: return "ไอคอน (Icons)"
        case .list: return "รายการ (List)"
        case .columns: return "คอลัมน์ (Columns)"
        case .gallery: return "แกลเลอรี (Gallery)"
        }
    }

    var symbolName: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        case .gallery: return "squares.below.rectangle"
        }
    }
}

enum SortField: String, CaseIterable, Identifiable {
    case name = "Name"
    case dateModified = "Date Modified"
    case size = "Size"
    case kind = "Kind"

    var id: String { rawValue }

    var labelThai: String {
        switch self {
        case .name: return "ชื่อ (Name)"
        case .dateModified: return "วันที่แก้ไข (Date Modified)"
        case .size: return "ขนาด (Size)"
        case .kind: return "ชนิด (Kind)"
        }
    }
}

struct StorageVolume: Identifiable, Hashable {
    let id: UInt32
    let description: String
    let maxCapacity: UInt64
    let freeSpace: UInt64

    var usedSpace: UInt64 {
        maxCapacity > freeSpace ? (maxCapacity - freeSpace) : 0
    }

    var usedFraction: Double {
        guard maxCapacity > 0 else { return 0 }
        return Double(usedSpace) / Double(maxCapacity)
    }

    var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: Int64(freeSpace), countStyle: .file)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(maxCapacity), countStyle: .file)
    }

    var formattedSummary: String {
        "\(formattedFree) available of \(formattedTotal)"
    }
}

struct ConnectedAndroidDevice: Equatable {
    let manufacturer: String
    let modelName: String
    let friendlyName: String
    let serialNumber: String
    let storages: [StorageVolume]

    var displayName: String {
        if !friendlyName.isEmpty && friendlyName != "???" {
            return friendlyName
        }
        if !modelName.isEmpty {
            return "\(manufacturer) \(modelName)".trimmingCharacters(in: .whitespaces)
        }
        return "Samsung Galaxy (Android)"
    }
}

enum FileDomain: Hashable {
    case android
    case mac
}

struct FileItem: Identifiable, Hashable {
    let id: String
    let domain: FileDomain
    let name: String
    let isFolder: Bool
    let size: UInt64
    let modificationDate: Date

    // Android MTP fields
    let storageId: UInt32
    let itemId: UInt32
    let parentId: UInt32

    // Mac local URL
    let localURL: URL?

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var isImage: Bool {
        guard !isFolder else { return false }
        return ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff", "dng", "raw"].contains(fileExtension)
    }

    var isVideo: Bool {
        guard !isFolder else { return false }
        return ["mp4", "mov", "mkv", "avi", "webm", "m4v", "3gp"].contains(fileExtension)
    }

    var isAudio: Bool {
        guard !isFolder else { return false }
        return ["mp3", "m4a", "wav", "flac", "aac", "ogg"].contains(fileExtension)
    }

    var isTextOrCode: Bool {
        guard !isFolder else { return false }
        return ["txt", "md", "json", "xml", "csv", "log", "html", "css", "js", "py", "swift", "sh", "yml", "yaml"].contains(fileExtension)
    }

    var kindDescription: String {
        if isFolder { return "Folder" }
        switch fileExtension {
        case "jpg", "jpeg": return "JPEG Image"
        case "png": return "PNG Image"
        case "heic", "heif": return "HEIF Image"
        case "gif": return "GIF Image"
        case "webp": return "WebP Image"
        case "dng", "raw": return "RAW Image"
        case "mp4": return "MPEG-4 Movie"
        case "mov": return "QuickTime Movie"
        case "mkv": return "Matroska Video"
        case "mp3": return "MP3 Audio"
        case "m4a": return "Apple MPEG-4 Audio"
        case "wav": return "WAV Audio"
        case "flac": return "FLAC Audio"
        case "pdf": return "PDF Document"
        case "zip", "rar", "7z", "tar", "gz": return "Archive"
        case "apk", "aab": return "Android Package"
        case "doc", "docx": return "Word Document"
        case "xls", "xlsx": return "Excel Spreadsheet"
        case "ppt", "pptx": return "PowerPoint Presentation"
        case "txt": return "Plain Text Document"
        case "": return "Document"
        default: return "\(fileExtension.uppercased()) File"
        }
    }

    var symbolName: String {
        if isFolder {
            switch name.lowercased() {
            case "dcim", "camera", "pictures": return "folder.fill"
            case "download", "downloads": return "folder.fill.badge.person.crop"
            case "movies", "video", "videos": return "folder.fill"
            case "music", "audio", "ringtones": return "folder.fill"
            default: return "folder.fill"
            }
        }
        if isImage { return "photo.fill" }
        if isVideo { return "film.fill" }
        if isAudio { return "music.note" }
        switch fileExtension {
        case "pdf": return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "apk": return "shippingbox.fill"
        case "txt", "md", "json", "log": return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    var iconColor: Color {
        if isFolder {
            // Classic macOS Finder sky-blue folder color
            return Color(red: 0.25, green: 0.66, blue: 0.96)
        }
        if isImage { return .purple }
        if isVideo { return .orange }
        if isAudio { return .pink }
        switch fileExtension {
        case "pdf": return .red
        case "apk": return .green
        case "zip", "rar", "7z": return .brown
        default: return .secondary
        }
    }

    var formattedSize: String {
        if isFolder { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}

struct BreadcrumbStep: Identifiable, Hashable {
    let id: String
    let title: String
    let domain: FileDomain
    let storageId: UInt32
    let folderId: UInt32
    let macURL: URL?
}

enum SidebarTarget: Hashable, Identifiable {
    case androidStorage(storageId: UInt32, name: String)
    case androidQuickFolder(name: String, pathComponents: [String], icon: String)
    case macFolder(name: String, url: URL, icon: String)

    var id: String {
        switch self {
        case .androidStorage(let sid, _):
            return "android-storage-\(sid)"
        case .androidQuickFolder(let name, _, _):
            return "android-quick-\(name)"
        case .macFolder(let name, let url, _):
            return "mac-\(name)-\(url.path)"
        }
    }
}

struct TransferStatus: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var sentBytes: UInt64
    var totalBytes: UInt64
    var isRunning: Bool

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(sentBytes) / Double(totalBytes))
    }
}
