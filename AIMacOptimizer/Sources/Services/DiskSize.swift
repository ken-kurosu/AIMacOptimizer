import Foundation
import Darwin

/// ディスクの「実占有量（物理割当サイズ）」を測る共通ユーティリティ。
///
/// 論理サイズ（`.size` / `attributesOfItem[.size]`）ではなく、
/// `URLResourceValues.totalFileAllocatedSize` を使う。これにより
/// APFS圧縮・スパースファイル・クローン・ハードリンクなどで生じる
/// 「論理サイズ ≫ 実際にディスクを使っている量」の乖離を避け、
/// 「削除して実際に空く量」に近い値（`du` と整合）を返す。
///
/// 監査指摘（削除容量の乖離: 表示544MB vs 実削除32MB）への対策として、
/// StorageAnalyzer / MemoryOptimizer など各所の容量計算をこの実装へ統一する。
enum DiskSize {

    /// 1ファイル/シンボリックリンクでない1エントリの実占有量（bytes）。
    static func fileAllocatedBytes(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
    }

    /// パス（ファイルまたはディレクトリ）の実占有量（bytes）。
    /// ディレクトリは再帰的に合算。シンボリックリンクは二重計上を避けるためスキップ。
    static func allocatedBytes(atPath path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        let url = URL(fileURLWithPath: path)
        if !isDir.boolValue { return fileAllocatedBytes(url) }

        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let en = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let f as URL in en {
            guard let v = try? f.resourceValues(forKeys: keys) else { continue }
            if v.isSymbolicLink == true { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// パスの実占有量（MB）。
    static func allocatedMB(atPath path: String) -> Double {
        Double(allocatedBytes(atPath: path)) / (1024 * 1024)
    }

    /// ボリュームの空き容量（bytes）。削除の前後で差を取ると「実際に増えた空き容量」を測れる。
    /// APFSローカルスナップショットが残っている場合など、削除しても即座には増えないことがある点に注意。
    static func volumeFreeBytes(forPath path: String = NSHomeDirectory()) -> Int64 {
        // URLResourceValues は同じ URL の容量値を短時間キャッシュし、削除直後でも
        // 古い空き容量を返すことがある。前後差の実測では同期的な statfs を優先する。
        var fileSystem = statfs()
        if statfs(path, &fileSystem) == 0 {
            return Int64(fileSystem.f_bavail) * Int64(fileSystem.f_bsize)
        }
        let url = URL(fileURLWithPath: path)
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = v.volumeAvailableCapacityForImportantUsage {
            return Int64(free)
        }
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let free = v.volumeAvailableCapacity {
            return Int64(free)
        }
        return 0
    }
}
