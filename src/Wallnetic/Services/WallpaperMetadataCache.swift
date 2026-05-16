import Foundation
import AppKit
import SQLite3

/// SQLite metadata cache for fast wallpaper search & filtering (#115).
///
/// **Role:** secondary read-side index. The authoritative store is still
/// `WallpaperMetadataStore` + the on-disk Library directory; this cache is a
/// best-effort denormalised mirror that fuels search/filter queries. If the
/// cache file is missing or corrupt we rebuild it from `WallpaperManager`
/// on next launch — losing the cache is never user-visible data loss.
///
/// **Threading:** uses an internal serial queue so callers can fire writes
/// from any thread without races. All sqlite3 calls happen on that queue.
///
/// **Failure policy:** every write is wrapped in do-or-log. If SQLite is in
/// a bad state the in-memory `WallpaperManager.wallpapers` array still
/// works; the next library reload will rebuild the cache.
final class WallpaperMetadataCache {
    static let shared = WallpaperMetadataCache()

    private let queue = DispatchQueue(label: "com.wallnetic.metadata-cache", qos: .utility)
    private var db: OpaquePointer?
    private var isOpen: Bool { db != nil }

    private init() {
        queue.sync { open() }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Lifecycle

    private func open() {
        let dbURL = applicationSupportURL()
            .appendingPathComponent("Wallnetic", isDirectory: true)
            .appendingPathComponent("metadata.sqlite")

        do {
            try FileManager.default.createDirectory(
                at: dbURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            Log.cache.error("Failed to create cache dir: \(String(describing: error), privacy: .public)")
            return
        }

        let path = dbURL.path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            // L1: path contains /Users/<name>/... — keep at .private.
            Log.cache.error("sqlite3_open_v2 failed for \(path, privacy: .private)")
            if handle != nil { sqlite3_close(handle) }
            return
        }
        db = handle

        // WAL mode for concurrent reads + better crash resilience
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA foreign_keys=ON;")

        applyMigrations()
    }

    private func applyMigrations() {
        // Schema v1
        let create = """
        CREATE TABLE IF NOT EXISTS wallpapers (
            key            TEXT PRIMARY KEY,
            name           TEXT NOT NULL,
            custom_title   TEXT,
            path           TEXT NOT NULL UNIQUE,
            type           TEXT NOT NULL DEFAULT 'video',
            tags_json      TEXT NOT NULL DEFAULT '[]',
            color_hex      TEXT,
            hue            INTEGER,
            saturation     INTEGER,
            width          INTEGER,
            height         INTEGER,
            duration       REAL,
            filesize       INTEGER NOT NULL DEFAULT 0,
            favourite      INTEGER NOT NULL DEFAULT 0,
            mtime          INTEGER NOT NULL DEFAULT 0,
            date_added     REAL NOT NULL DEFAULT 0
        );
        """
        exec(create)
        exec("CREATE INDEX IF NOT EXISTS idx_wallpapers_favourite ON wallpapers(favourite);")
        exec("CREATE INDEX IF NOT EXISTS idx_wallpapers_color    ON wallpapers(color_hex);")
        exec("CREATE INDEX IF NOT EXISTS idx_wallpapers_name     ON wallpapers(name);")
        exec("CREATE INDEX IF NOT EXISTS idx_wallpapers_mtime    ON wallpapers(mtime);")

        // schema_version for future migrations
        exec("CREATE TABLE IF NOT EXISTS schema (version INTEGER NOT NULL);")
        exec("INSERT INTO schema (version) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema);")
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            Log.cache.error("sqlite3_exec failed (\(rc, privacy: .public)): \(msg, privacy: .public)")
            return false
        }
        return true
    }

    // MARK: - Public API (Writes)

    /// Insert or update one wallpaper.
    func upsert(_ wallpaper: Wallpaper) {
        queue.async { [weak self] in
            self?.unsafeUpsert(wallpaper)
        }
    }

    /// Bulk replace — rebuilds the table to match an authoritative set.
    /// Used after `WallpaperManager.loadWallpapers()` to drop stale rows.
    func replaceAll(with wallpapers: [Wallpaper]) {
        queue.async { [weak self] in
            guard let self, self.isOpen else { return }
            self.exec("BEGIN IMMEDIATE TRANSACTION;")
            self.exec("DELETE FROM wallpapers;")
            for wp in wallpapers {
                self.unsafeUpsert(wp)
            }
            self.exec("COMMIT;")
        }
    }

    /// Remove a wallpaper by id.
    func delete(id: UUID) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "DELETE FROM wallpapers WHERE key=?;", -1, &stmt, nil) == SQLITE_OK else {
                Log.cache.error("prepare DELETE failed: \(self.lastError, privacy: .public)")
                return
            }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.cache.error("DELETE failed: \(self.lastError, privacy: .public)")
            }
        }
    }

    /// Drop rows whose `path` is not present in `currentPaths` — used after
    /// a library rescan to discard rows for files that disappeared.
    /// L4: deletes run inside a single transaction so a crash mid-prune
    /// leaves the cache atomically consistent.
    func pruneMissing(currentPaths: Set<String>) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT path FROM wallpapers;", -1, &stmt, nil) == SQLITE_OK else {
                sqlite3_finalize(stmt)
                return
            }
            var toDelete: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 0) {
                    let path = String(cString: cstr)
                    if !currentPaths.contains(path) { toDelete.append(path) }
                }
            }
            sqlite3_finalize(stmt)

            guard !toDelete.isEmpty else { return }

            self.exec("BEGIN IMMEDIATE TRANSACTION;")
            for path in toDelete {
                var d: OpaquePointer?
                if sqlite3_prepare_v2(db, "DELETE FROM wallpapers WHERE path=?;", -1, &d, nil) == SQLITE_OK {
                    sqlite3_bind_text(d, 1, path, -1, SQLITE_TRANSIENT)
                    _ = sqlite3_step(d)
                }
                sqlite3_finalize(d)
            }
            self.exec("COMMIT;")
        }
    }

    // MARK: - Public API (Reads)

    /// Returns wallpaper *ids* matching the search query in name/custom_title/tags.
    /// Ordered by score (exact name match > contains > tag-contains > fuzzy).
    /// Synchronous because callers display results inline.
    func searchIds(query: String) -> [UUID] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return queue.sync {
            guard let db = self.db else { return [] }
            let like = "%\(trimmed.lowercased())%"
            let sql = """
            SELECT key,
                   (CASE WHEN lower(coalesce(custom_title, name)) = ? THEN 100
                         WHEN lower(coalesce(custom_title, name)) LIKE ? THEN 70
                         ELSE 0 END) +
                   (CASE WHEN lower(tags_json) LIKE ? THEN 50 ELSE 0 END) AS score
              FROM wallpapers
             WHERE score > 0
             ORDER BY score DESC, name ASC;
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                Log.cache.error("prepare SELECT search failed: \(self.lastError, privacy: .public)")
                return []
            }
            let exact = trimmed.lowercased()
            sqlite3_bind_text(stmt, 1, exact, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, like, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, like, -1, SQLITE_TRANSIENT)

            var ids: [UUID] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 0),
                   let uuid = UUID(uuidString: String(cString: cstr)) {
                    ids.append(uuid)
                }
            }
            return ids
        }
    }

    /// Returns ids of wallpapers in the given color category.
    func idsByColorCategory(_ category: ColorCategory) -> [UUID] {
        return queue.sync {
            guard let db = self.db else { return [] }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT key, color_hex FROM wallpapers WHERE color_hex IS NOT NULL;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

            var ids: [UUID] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let keyCstr = sqlite3_column_text(stmt, 0),
                    let hexCstr = sqlite3_column_text(stmt, 1),
                    let uuid = UUID(uuidString: String(cString: keyCstr))
                else { continue }
                let hex = String(cString: hexCstr)
                if let color = NSColor(hex: hex), ColorCategory.from(color: color) == category {
                    ids.append(uuid)
                }
            }
            return ids
        }
    }

    /// P1-5: async wrapper so call sites on MainActor never block on
    /// SQLite even when the disk is slow. Internally hops to the
    /// service's serial queue.
    ///
    /// DUSUK-1: continuation is always resumed exactly once — both
    /// branches of the `guard` resume before returning. The singleton
    /// queue outlives the process, so there's no practical leak risk;
    /// the [weak self] guard exists only to handle the test-teardown
    /// path where `makeInMemoryForTesting()` instances dealloc.
    func asyncSearchIds(query: String) async -> [UUID] {
        let q = query
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: self.unsafeSearchIds(query: q))
            }
        }
    }

    /// Body of `searchIds` factored out so both sync (legacy) and async
    /// paths reuse the SQL.
    private func unsafeSearchIds(query: String) -> [UUID] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let db = self.db else { return [] }
        let like = "%\(trimmed.lowercased())%"
        let sql = """
        SELECT key,
               (CASE WHEN lower(coalesce(custom_title, name)) = ? THEN 100
                     WHEN lower(coalesce(custom_title, name)) LIKE ? THEN 70
                     ELSE 0 END) +
               (CASE WHEN lower(tags_json) LIKE ? THEN 50 ELSE 0 END) AS score
          FROM wallpapers
         WHERE score > 0
         ORDER BY score DESC, name ASC;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        let exact = trimmed.lowercased()
        sqlite3_bind_text(stmt, 1, exact, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, like, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, like, -1, SQLITE_TRANSIENT)
        var ids: [UUID] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cstr = sqlite3_column_text(stmt, 0),
               let uuid = UUID(uuidString: String(cString: cstr)) {
                ids.append(uuid)
            }
        }
        return ids
    }

    func count() -> Int {
        return queue.sync {
            guard let db = self.db else { return 0 }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM wallpapers;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    // MARK: - Internals

    /// Must run on `queue`.
    private func unsafeUpsert(_ wallpaper: Wallpaper) {
        guard let db else { return }

        let mtime = (try? FileManager.default.attributesOfItem(atPath: wallpaper.url.path))?[.modificationDate] as? Date
        let tagsJSON = (try? String(data: JSONEncoder().encode(wallpaper.tags), encoding: .utf8)) ?? "[]"

        var hue: Int32 = -1
        var sat: Int32 = -1
        if let hex = wallpaper.dominantColorHex, let color = NSColor(hex: hex) {
            let rgb = color.usingColorSpace(.sRGB) ?? color
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            rgb.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            hue = Int32(h * 360)
            sat = Int32(s * 100)
        }

        let sql = """
        INSERT INTO wallpapers (key, name, custom_title, path, type, tags_json, color_hex, hue, saturation,
                                width, height, duration, filesize, favourite, mtime, date_added)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(key) DO UPDATE SET
            name=excluded.name,
            custom_title=excluded.custom_title,
            path=excluded.path,
            tags_json=excluded.tags_json,
            color_hex=excluded.color_hex,
            hue=excluded.hue,
            saturation=excluded.saturation,
            width=excluded.width,
            height=excluded.height,
            duration=excluded.duration,
            filesize=excluded.filesize,
            favourite=excluded.favourite,
            mtime=excluded.mtime;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.cache.error("prepare UPSERT failed: \(self.lastError, privacy: .public)")
            return
        }

        sqlite3_bind_text(stmt, 1, wallpaper.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, wallpaper.name, -1, SQLITE_TRANSIENT)
        if let custom = wallpaper.customTitle {
            sqlite3_bind_text(stmt, 3, custom, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, wallpaper.url.path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, "video", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, tagsJSON, -1, SQLITE_TRANSIENT)
        if let hex = wallpaper.dominantColorHex {
            sqlite3_bind_text(stmt, 7, hex, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_bind_int(stmt, 8, hue)
        sqlite3_bind_int(stmt, 9, sat)

        if let res = wallpaper.resolution {
            sqlite3_bind_int(stmt, 10, Int32(res.width))
            sqlite3_bind_int(stmt, 11, Int32(res.height))
        } else {
            sqlite3_bind_null(stmt, 10)
            sqlite3_bind_null(stmt, 11)
        }

        if let dur = wallpaper.duration {
            sqlite3_bind_double(stmt, 12, dur)
        } else {
            sqlite3_bind_null(stmt, 12)
        }

        sqlite3_bind_int64(stmt, 13, wallpaper.fileSize)
        sqlite3_bind_int(stmt, 14, wallpaper.isFavorite ? 1 : 0)
        sqlite3_bind_int64(stmt, 15, Int64(mtime?.timeIntervalSince1970 ?? 0))
        sqlite3_bind_double(stmt, 16, wallpaper.dateAdded.timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            Log.cache.error("UPSERT step failed: \(self.lastError, privacy: .public)")
        }
    }

    private var lastError: String {
        guard let db else { return "no db" }
        return String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Test Support

    #if DEBUG
    /// In-memory database for unit tests. Not exposed in Release.
    static func makeInMemoryForTesting() -> WallpaperMetadataCache {
        let instance = WallpaperMetadataCache(inMemory: true)
        return instance
    }

    private convenience init(inMemory: Bool) {
        self.init()
        guard inMemory else { return }
        queue.sync {
            if let db { sqlite3_close(db) }
            self.db = nil
            var handle: OpaquePointer?
            if sqlite3_open(":memory:", &handle) == SQLITE_OK, let handle {
                self.db = handle
                applyMigrations()
            }
        }
    }
    #endif
}

// SQLITE_TRANSIENT helper — required for Swift bindings to copy strings.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
