import Foundation

@main
struct Build16DiskVerifier {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw VerificationError("usage: Build16DiskVerifier <fixture-directory>")
        }

        let directory = CommandLine.arguments[1]
        let regular = URL(fileURLWithPath: directory).appendingPathComponent("regular-32mb.bin").path
        let sparse = URL(fileURLWithPath: directory).appendingPathComponent("sparse-512mb.bin").path
        let fm = FileManager.default

        let regularLogical = try logicalBytes(regular)
        let sparseLogical = try logicalBytes(sparse)
        guard regularLogical == 32 * 1024 * 1024 else {
            throw VerificationError("regular fixture logical size is \(regularLogical) bytes")
        }
        guard sparseLogical == 512 * 1024 * 1024 else {
            throw VerificationError("sparse fixture logical size is \(sparseLogical) bytes")
        }

        let regularAllocated = DiskSize.allocatedBytes(atPath: regular)
        let sparseAllocated = DiskSize.allocatedBytes(atPath: sparse)
        let displayedBytes = regularAllocated + sparseAllocated
        guard displayedBytes > 0 else { throw VerificationError("allocated size was zero") }
        guard sparseAllocated < 16 * 1024 * 1024 else {
            throw VerificationError("sparse fixture unexpectedly occupies \(sparseAllocated) bytes")
        }

        let freeBefore = DiskSize.volumeFreeBytes(forPath: directory)
        try fm.removeItem(atPath: regular)
        try fm.removeItem(atPath: sparse)
        sync()
        Thread.sleep(forTimeInterval: 1)
        let freeAfter = DiskSize.volumeFreeBytes(forPath: directory)
        let freedBytes = max(0, freeAfter - freeBefore)
        let errorRatio = abs(Double(freedBytes - displayedBytes)) / Double(displayedBytes)

        eprint("regular logical=\(regularLogical) allocated=\(regularAllocated)")
        eprint("sparse  logical=\(sparseLogical) allocated=\(sparseAllocated)")
        let errorPercent = String(format: "%.2f", errorRatio * 100)
        eprint("displayed=\(displayedBytes) actualFreeIncrease=\(freedBytes) error=\(errorPercent)%")

        guard errorRatio <= 0.05 else {
            throw VerificationError("displayed and actual freed size differ by more than 5%")
        }
        eprint("PASS: 表示予定容量と実空き増加が±5%以内")
    }

    private static func logicalBytes(_ path: String) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        guard let value = attrs[.size] as? NSNumber else {
            throw VerificationError("logical size unavailable: \(path)")
        }
        return value.int64Value
    }

    private static func eprint(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

private struct VerificationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
