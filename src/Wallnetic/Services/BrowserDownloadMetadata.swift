import Foundation

/// A scan result keeps its title even if the browser navigates before Download.
struct BrowserVideo: Identifiable {
    let url: URL
    let name: String
    var id: String { url.absoluteString }
}

enum BrowserDownloadMetadata {
    static func name(title: String? = nil, pageTitle: String? = nil, filename: String?) -> String {
        let normalize = WallpaperMetadataStore.normalizedImportedTitle
        if let title = normalize(title) { return title }
        if let title = normalize(pageTitle) { return title }
        let basename = ((filename ?? "") as NSString).lastPathComponent
        return normalize((basename as NSString).deletingPathExtension) ?? "Wallpaper"
    }

    static func videos(from result: Any?) -> [BrowserVideo] {
        guard let rows = result as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return rows.prefix(200).compactMap { row in
            guard let rawURL = row["url"] as? String,
                  let url = URL(string: rawURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  !(url.host?.isEmpty ?? true), seen.insert(url.absoluteString).inserted else { return nil }
            return BrowserVideo(url: url, name: name(title: row["title"] as? String,
                pageTitle: row["pageTitle"] as? String, filename: url.lastPathComponent))
        }
    }

    // Constant read-only script: page text is returned as data, never inserted
    // into JavaScript source. Keep the title together with each media URL.
    static let scanScript = #"""
    (() => {
        const videos = [];
        const bounded = value => typeof value === 'string' && value.length <= 4096 ? value : '';
        const pageTitle = bounded(document.title);
        const add = (raw, title, requireExtension) => {
            if (!raw || videos.length >= 200) return;
            try {
                const url = new URL(raw, document.baseURI);
                if (!['http:', 'https:'].includes(url.protocol)) return;
                if (requireExtension && !/\.(mp4|mov|m4v|webm|mkv)$/i.test(url.pathname)) return;
                videos.push({url: url.href, title: bounded(title), pageTitle});
            } catch (_) {}
        };
        const label = el => el.getAttribute('title') || el.getAttribute('aria-label') || '';
        document.querySelectorAll('video source, video').forEach(el => {
            const video = el.closest('video');
            add(el.src || el.currentSrc, label(el) || (video && label(video)), true);
        });
        document.querySelectorAll('a[href]').forEach(el => add(el.href, label(el), true));
        document.querySelectorAll('meta[property="og:video"]').forEach(el => add(el.content, '', false));
        return videos;
    })();
    """#
}
