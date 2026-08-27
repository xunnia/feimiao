import Foundation

/// 交易附件的本地文件边界。
///
/// 数据库只保存相对文件名，备份时可以稳定地把 receipts 目录整体打包；
/// 不保存 Photos 的临时 URL，避免系统回收临时资源后账单出现死链接。
enum AttachmentStore {
    static let directoryName = "receipts"

    static func save(data: Data, fileExtension: String = "jpg") throws -> String {
        let directory = try receiptsDirectory()
        let name = "\(UUID().uuidString).\(fileExtension.lowercased())"
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return name
    }

    static func url(for relativePath: String) -> URL? {
        let normalizedPath = normalize(relativePath)
        guard !normalizedPath.isEmpty else { return nil }
        guard isSafeRelativePath(normalizedPath) else { return nil }
        guard let directory = try? receiptsDirectory() else { return nil }
        return directory.appendingPathComponent(normalizedPath, isDirectory: false)
    }

    /// Returns all managed attachment paths, including asset media nested under
    /// `asset_media/`. The relative path is part of the backup contract.
    static func allRelativePaths() throws -> [String] {
        let directory = try receiptsDirectory()
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
            let relativePath = url.path.hasPrefix(prefix)
                ? String(url.path.dropFirst(prefix.count))
                : url.lastPathComponent
            return isSafeRelativePath(relativePath) ? relativePath : nil
        }.sorted()
    }

    static func writeImported(data: Data, relativePath: String) throws {
        let normalizedPath = normalize(relativePath)
        guard isSafeRelativePath(normalizedPath) else {
            throw AttachmentStoreError.unsafePath
        }
        guard let url = url(for: normalizedPath) else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// 将已在临时目录完成校验的附件安装到正式目录。
    /// 由备份导入使用，避免在数据库尚未提交时暴露半成品文件。
    static func installImportedFile(at sourceURL: URL, relativePath: String) throws {
        let normalizedPath = normalize(relativePath)
        guard isSafeRelativePath(normalizedPath), url(for: normalizedPath) != nil else {
            throw AttachmentStoreError.unsafePath
        }
        let data = try Data(contentsOf: sourceURL)
        try writeImported(data: data, relativePath: normalizedPath)
    }

    static func remove(_ relativePath: String) {
        guard let url = url(for: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 用于判断同一附件是否仍被其他账单引用，兼容 `foo.jpg` 和
    /// Android 备份常见的 `receipts/foo.jpg` 两种存储写法。
    static func canonicalRelativePath(_ relativePath: String) -> String {
        normalize(relativePath)
    }

    private static func receiptsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("\\"), !path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func normalize(_ path: String) -> String {
        path.hasPrefix("receipts/") ? String(path.dropFirst("receipts/".count)) : path
    }
}

enum AttachmentStoreError: LocalizedError {
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .unsafePath: return "备份附件路径不安全。"
        }
    }
}
