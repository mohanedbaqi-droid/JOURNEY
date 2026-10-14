import Foundation
@main struct ESPDiagnosticTests {
    static func main() {
        func packet(_ seq: UInt32, _ i: Int, _ n: Int, _ hex: String) -> ESPDiagnosticChunk {
            ESPDiagnosticChunk(ds: seq, di: i, dn: n, dx: hex)
        }
        var a=ESPDiagnosticAssembler()
        precondition(a.accept(packet(1, 1, 2, "A7")) == nil)
        precondition(a.accept(packet(1, 1, 2, "A7")) == nil) // duplicate never completes missing chunk
        precondition(a.accept(packet(1, 0, 2, "D8")) == "ا") // UTF-8 split across BLE packets
        var b=ESPDiagnosticAssembler()
        precondition(b.accept(packet(2, 0, 2, "41")) == nil)
        precondition(b.accept(packet(2, 1, 3, "42")) == nil) // mismatched total rejected
        precondition(b.accept(packet(2, 1, 2, "GG")) == nil)
        precondition(b.accept(packet(2, 1, 2, "42")) == "AB")
        precondition(b.accept(packet(3, 0, 2, "43")) == nil) // new report clears previous pieces
        precondition(b.accept(packet(3, 1, 2, "44")) == "CD")
        precondition(b.accept(packet(4, 0, 513, "41")) == nil)
        precondition(b.accept(packet(4, 0, 1, String(repeating: "41", count: 49))) == nil)
        precondition(ESPDiagnosticAssembler.logCursor(in: "status\nLOG_END=123\nlog") == 123)
        precondition(ESPDiagnosticAssembler.logCursor(in: "no cursor") == nil)
        print("ESP diagnostic chunk checks passed")
    }
}
