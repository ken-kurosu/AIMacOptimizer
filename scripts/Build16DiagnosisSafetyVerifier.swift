import Foundation

@main
struct Build16DiagnosisSafetyVerifier {
    static func main() {
        precondition(DiagnosisBulkRepairPolicy.requiresManualHandling(
            path: "/Users/test/Library/Developer/CoreSimulator"
        ))
        precondition(DiagnosisBulkRepairPolicy.requiresManualHandling(
            path: "/Users/test/Library/Developer/CoreSimulator/Devices/device-id/data"
        ))
        precondition(!DiagnosisBulkRepairPolicy.requiresManualHandling(
            path: "/Users/test/Library/Developer/Xcode/DerivedData"
        ))
        print("PASS: CoreSimulatorは一括修復不可、案内のみ")
    }
}
