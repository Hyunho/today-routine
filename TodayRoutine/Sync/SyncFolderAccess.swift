import Foundation
@MainActor final class SyncFolderAccess {
    private let defaults: UserDefaults
    private let key: String
    private var held: URL?
    init(defaults: UserDefaults = .standard, key: String = "routine.sync.bookmark") { self.defaults = defaults; self.key = key }
    func connect(url: URL) throws {
        let started = url.startAccessingSecurityScopedResource()
        do {
            #if os(macOS)
            let data = try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
            #else
            let data = try url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil)
            #endif
            if let held { held.stopAccessingSecurityScopedResource() }
            held = started ? url:nil; defaults.set(data,forKey:key)
        } catch { if started { url.stopAccessingSecurityScopedResource() }; throw error }
    }
    func restore() throws -> URL? {
        guard let data = defaults.data(forKey:key) else { return nil }
        var stale = false
        #if os(macOS)
        let url: URL
        do {
            url = try URL(resolvingBookmarkData:data,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadCorruptFileError {
            // Local non-sandboxed builds can save ordinary bookmarks even when
            // creation requests a security scope. Resolve that same bookmark;
            // never substitute a stored path or bypass sandbox file permissions.
            url = try URL(resolvingBookmarkData:data,options:.withoutUI,relativeTo:nil,bookmarkDataIsStale:&stale)
        }
        #else
        let url = try URL(resolvingBookmarkData:data,options:.withoutUI,relativeTo:nil,bookmarkDataIsStale:&stale)
        #endif
        guard !stale else { throw SyncError.invalid("동기화 폴더 권한이 만료되었습니다. 같은 폴더를 다시 선택해 주세요.") }
        if let held { held.stopAccessingSecurityScopedResource() }
        held = url.startAccessingSecurityScopedResource() ? url:nil
        return url
    }
    func disconnect() { if let held { held.stopAccessingSecurityScopedResource() }; held = nil; defaults.removeObject(forKey:key) }
    deinit { held?.stopAccessingSecurityScopedResource() }
}
final class FileChangeMonitor: NSObject, NSFilePresenter {
    var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; return q }()
    private let changed: () -> Void
    init(url: URL, changed: @escaping () -> Void) { presentedItemURL = url; self.changed = changed; super.init(); NSFileCoordinator.addFilePresenter(self) }
    func presentedItemDidChange() { changed() }
    func presentedSubitemDidChange(at url: URL) { changed() }
    func presentedSubitemDidAppear(at url: URL) { changed() }
    func presentedItemDidMove(to newURL: URL) { changed() }
    func stop() { NSFileCoordinator.removeFilePresenter(self) }
    deinit { NSFileCoordinator.removeFilePresenter(self) }
}
