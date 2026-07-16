import Foundation

/// Resizes YouTube image URLs.
///
/// YT's image hosts (`yt3.googleusercontent.com`, `lh3.googleusercontent.com`)
/// serve any size from one URL: the trailing `=w60-h60-l90-rj` is a request
/// parameter, not part of the image's identity. The play history stores
/// whatever the player bar happened to be showing, which is a 60px thumbnail —
/// fine for a 24px status-bar icon, mud when blown up into a 150pt tile.
///
/// Rewriting on read rather than on write means the ~800 rows already in the
/// database get sharp covers too, with no migration.
enum YTImageURL {
    /// Requests `size`×`size` from a YT image URL.
    ///
    /// Only URLs that already carry a size suffix are touched. Other YT image
    /// forms (`i.ytimg.com/vi/<id>/hqdefault.jpg`) don't take one and would
    /// 404 if we appended it, so they're returned unchanged.
    static func resized(_ url: String?, to size: Int) -> String? {
        guard let url, !url.isEmpty else { return nil }
        guard let suffixStart = sizeSuffixStart(in: url) else { return url }
        return url[url.startIndex..<suffixStart] + "=w\(size)-h\(size)-l90-rj"
    }

    /// Index of the `=` that begins a trailing size suffix, or nil if there
    /// isn't one.
    ///
    /// The suffix is lowercase letters, digits and dashes running to the end of
    /// the string. Image ids are mixed-case and can contain `=` padding, so
    /// requiring lowercase is what keeps this from eating part of an id — the
    /// same rule the JS bridge's `smallerCover` uses.
    private static func sizeSuffixStart(in url: String) -> String.Index? {
        guard let equals = url.lastIndex(of: "=") else { return nil }
        let suffix = url[url.index(after: equals)...]
        guard !suffix.isEmpty else { return nil }
        let allowed = suffix.allSatisfy { $0.isLowercase && $0.isASCII || $0.isNumber || $0 == "-" }
        guard allowed, suffix.hasPrefix("w") else { return nil }
        return equals
    }
}
