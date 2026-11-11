import Foundation

/// Grande famille d'un fichier, d'après son extension (pour les filtres d'affichage).
public enum FileKind: String, CaseIterable, Sendable {
    case video
    case audio
    case image
    case archive
    case document
    case other

    public var title: String {
        switch self {
        case .video: "Vidéos"
        case .audio: "Audio"
        case .image: "Images"
        case .archive: "Archives et images disque"
        case .document: "Documents"
        case .other: "Autres"
        }
    }

    public var symbol: String {
        switch self {
        case .video: "film"
        case .audio: "music.note"
        case .image: "photo"
        case .archive: "archivebox"
        case .document: "doc.richtext"
        case .other: "doc"
        }
    }

    private static let byExtension: [String: FileKind] = {
        var table: [String: FileKind] = [:]
        let groups: [(FileKind, [String])] = [
            (.video, ["mov", "mp4", "m4v", "mkv", "avi", "wmv", "webm", "mpg", "mpeg", "3gp", "mts", "m2ts", "braw", "prores"]),
            (.audio, ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "alac", "caf", "m4b"]),
            (.image, ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp", "raw", "cr2", "cr3",
                      "nef", "arw", "dng", "raf", "orf", "psd", "svg", "avif"]),
            (.archive, ["zip", "dmg", "iso", "img", "pkg", "mpkg", "xip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar",
                        "zst", "sparseimage", "sparsebundle", "ipa", "apk", "aab", "jar"]),
            (.document, ["pdf", "doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "txt", "rtf",
                         "md", "csv", "epub", "odt", "ods"]),
        ]
        for (kind, extensions) in groups {
            for ext in extensions { table[ext] = kind }
        }
        return table
    }()

    /// Famille d'un chemin, d'après son extension (insensible à la casse).
    public static func of(_ path: String) -> FileKind {
        let ext = (path as NSString).pathExtension.lowercased()
        return byExtension[ext] ?? .other
    }
}
