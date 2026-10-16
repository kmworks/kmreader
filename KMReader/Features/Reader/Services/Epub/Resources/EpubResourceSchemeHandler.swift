import Foundation
import UniformTypeIdentifiers

nonisolated enum EpubResourceScheme {
  static let scheme = "kmreader-resource"
  static let host = "epub"
  static let virtualFontsPrefix = "__fonts__"

  static func url(for fileURL: URL, rootURL: URL) -> URL? {
    let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    let file = deletingFragment(from: fileURL).standardizedFileURL.resolvingSymlinksInPath()
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard file.path.hasPrefix(rootPath) || file.path == root.path else { return nil }

    let relativePath = file.path == root.path ? "" : String(file.path.dropFirst(rootPath.count))
    guard !relativePath.isEmpty else { return nil }
    return url(forRelativePath: relativePath)
  }

  static func url(forRelativePath relativePath: String) -> URL? {
    guard let safePath = EpubResourceSafeRelativePath(relativePath) else { return nil }
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path =
      "/"
      + safePath.split(separator: "/").map {
        String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
      }.joined(separator: "/")
    return components.url
  }

  static func fontURL(fileName: String) -> URL? {
    url(forRelativePath: "\(virtualFontsPrefix)/\(fileName)")
  }

  static func relativePath(from url: URL) -> String? {
    guard url.scheme == scheme, url.host == host else { return nil }
    let path = deletingFragment(from: url).path
    let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
    return EpubResourceSafeRelativePath(trimmed.removingPercentEncoding ?? trimmed)
  }

  private static func deletingFragment(from url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }
    components.fragment = nil
    return components.url ?? url
  }
}

nonisolated func EpubResourceSafeRelativePath(_ path: String) -> String? {
  let normalized = path.replacingOccurrences(of: "\\", with: "/")
  guard !normalized.isEmpty, !normalized.hasPrefix("/") else { return nil }
  var components: [String] = []
  for component in normalized.split(separator: "/", omittingEmptySubsequences: true) {
    let part = String(component)
    if part == "." { continue }
    guard part != ".." else { return nil }
    components.append(part)
  }
  guard !components.isEmpty else { return nil }
  return components.joined(separator: "/")
}

#if os(iOS) || os(macOS)
  import WebKit

  final class EpubResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let lock = NSLock()
    private var rootURL: URL?
    private var mediaTypesByRelativePath: [String: String] = [:]

    func configure(rootURL: URL?, mediaTypesByRelativePath: [String: String]) {
      lock.lock()
      self.rootURL = rootURL?.standardizedFileURL.resolvingSymlinksInPath()
      self.mediaTypesByRelativePath = mediaTypesByRelativePath
      lock.unlock()
    }

    private func configurationSnapshot() -> (rootURL: URL?, mediaTypesByRelativePath: [String: String]) {
      lock.lock()
      let snapshot = (rootURL, mediaTypesByRelativePath)
      lock.unlock()
      return snapshot
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
      guard let requestURL = urlSchemeTask.request.url,
        let relativePath = EpubResourceScheme.relativePath(from: requestURL)
      else {
        fail(urlSchemeTask, code: NSURLErrorBadURL)
        return
      }

      let configuration = configurationSnapshot()
      let fileURL: URL?
      if let fontFileName = fontFileName(from: relativePath) {
        fileURL = FontFileManager.resolveFontFile(named: fontFileName)
      } else {
        fileURL = epubFileURL(for: relativePath, rootURL: configuration.rootURL)
      }

      guard let fileURL else {
        fail(urlSchemeTask, code: NSURLErrorFileDoesNotExist)
        return
      }

      do {
        let data = try Data(contentsOf: fileURL)
        let mimeType = mediaType(
          for: relativePath, fileURL: fileURL, mediaTypesByRelativePath: configuration.mediaTypesByRelativePath)
        let response = URLResponse(
          url: requestURL,
          mimeType: mimeType,
          expectedContentLength: data.count,
          textEncodingName: isTextMediaType(mimeType) ? "utf-8" : nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
      } catch {
        urlSchemeTask.didFailWithError(error)
      }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func epubFileURL(for relativePath: String, rootURL: URL?) -> URL? {
      guard let rootURL else { return nil }

      let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
      let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
      guard candidate.path.hasPrefix(rootPath) || candidate.path == rootURL.path else { return nil }
      guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
      return candidate
    }

    private func fontFileName(from relativePath: String) -> String? {
      let prefix = EpubResourceScheme.virtualFontsPrefix + "/"
      guard relativePath.hasPrefix(prefix) else { return nil }
      let name = String(relativePath.dropFirst(prefix.count))
      guard !name.contains("/") else { return nil }
      return name
    }

    private func mediaType(for relativePath: String, fileURL: URL, mediaTypesByRelativePath: [String: String]) -> String
    {
      if let mappedType = mediaTypesByRelativePath[relativePath], !mappedType.isEmpty { return mappedType }
      return Self.mediaTypeForExtension(fileURL.pathExtension)
    }

    private func isTextMediaType(_ mediaType: String) -> Bool {
      mediaType.hasPrefix("text/")
        || mediaType == "application/xhtml+xml"
        || mediaType == "application/xml"
        || mediaType == "application/javascript"
        || mediaType == "image/svg+xml"
    }

    private func fail(_ task: WKURLSchemeTask, code: Int) {
      task.didFailWithError(NSError(domain: NSURLErrorDomain, code: code))
    }

    static func mediaTypeForExtension(_ pathExtension: String) -> String {
      switch pathExtension.lowercased() {
      case "xhtml", "xht": return "application/xhtml+xml"
      case "html", "htm": return "text/html"
      case "css": return "text/css"
      case "js", "mjs": return "application/javascript"
      case "jpg", "jpeg": return "image/jpeg"
      case "png": return "image/png"
      case "gif": return "image/gif"
      case "svg", "svgz": return "image/svg+xml"
      case "webp": return "image/webp"
      case "ttf": return "font/ttf"
      case "otf": return "font/otf"
      case "woff": return "font/woff"
      case "woff2": return "font/woff2"
      case "mp3": return "audio/mpeg"
      case "m4a": return "audio/mp4"
      case "aac": return "audio/aac"
      case "oga", "ogg": return "audio/ogg"
      case "wav": return "audio/wav"
      case "mp4", "m4v": return "video/mp4"
      case "webm": return "video/webm"
      case "ogv": return "video/ogg"
      case "xml", "opf", "ncx": return "application/xml"
      default:
        if let type = UTType(filenameExtension: pathExtension),
          let mimeType = type.preferredMIMEType
        {
          return mimeType
        }
        return "application/octet-stream"
      }
    }
  }
#endif
