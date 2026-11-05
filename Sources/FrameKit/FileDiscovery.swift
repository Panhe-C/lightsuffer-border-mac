import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
import UniformTypeIdentifiers

/// Finds the pictures of the files and folders the user opened.
public enum FileDiscovery {
    /// The file extensions the app opens.
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "heic", "heif", "png", "tif", "tiff",
    ]

    /// The pictures of a file or a folder.
    ///
    /// A folder is searched recursively; hidden files and hidden folders are
    /// skipped. The result is sorted, so that a batch always runs in the same
    /// order.
    public static func discover(_ url: URL) -> [URL] {
        var found: [URL] = []
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return found
        }
        if isDirectory.boolValue {
            found = pictures(in: url)
        } else if isPicture(url) {
            found = [url]
        }
        return found
    }

    /// The pictures of a list of files and folders.
    public static func discover(paths: [String]) -> [URL] {
        var found: [URL] = []
        for path in paths {
            found.append(contentsOf: discover(URL(fileURLWithPath: path)))
        }
        return unique(found)
    }

    /// The pictures of a list of files and folders.
    public static func discover(urls: [URL]) -> [URL] {
        var found: [URL] = []
        for url in urls {
            found.append(contentsOf: discover(url))
        }
        return unique(found)
    }

    /// The pictures of a folder and its subfolders.
    public static func pictures(in directory: URL) -> [URL] {
        var found: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return found
        }
        for case let url as URL in enumerator {
            if isPicture(url) {
                found.append(url)
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Is the file a picture the app can open?
    public static func isPicture(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }

    /// The uniform type identifier of a file (from its extension).
    public static func uniformTypeIdentifier(of url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        return type.identifier
    }

    /// Removes the duplicates of a list of files.
    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }
}
#endif
