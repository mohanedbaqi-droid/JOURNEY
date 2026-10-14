import Foundation

struct ESPDiagnosticChunk: Decodable {
    let ds: UInt32
    let di: Int
    let dn: Int
    let dx: String
}

struct ESPDiagnosticAssembler {
    private var sequence: UInt32?
    private var count = 0
    private var chunks: [Int: Data] = [:]
    mutating func accept(_ packet: ESPDiagnosticChunk) -> String? {
        guard (1...512).contains(packet.dn), (0..<packet.dn).contains(packet.di),
              !packet.dx.isEmpty, packet.dx.utf8.count <= 96, packet.dx.utf8.count % 2 == 0 else { return nil }
        let bytes = Array(packet.dx.utf8)
        var decoded = Data()
        func nibble(_ b: UInt8) -> UInt8? {
            switch b { case 48...57: return b-48; case 65...70: return b-55; case 97...102: return b-87; default: return nil }
        }
        for i in stride(from: 0, to: bytes.count, by: 2) {
            guard let high=nibble(bytes[i]), let low=nibble(bytes[i+1]) else { return nil }
            decoded.append(high*16+low)
        }
        if sequence != packet.ds { sequence=packet.ds; count=packet.dn; chunks=[:] }
        guard count == packet.dn else { return nil }
        chunks[packet.di] = decoded
        guard chunks.count == count else { return nil }
        var report = Data()
        for i in 0..<count { guard let part=chunks[i] else { return nil }; report.append(part) }
        return String(data: report, encoding: .utf8)
    }
}

extension ESPDiagnosticAssembler {
    static func logCursor(in report: String) -> UInt32? {
        report.components(separatedBy: "\n").first(where: { $0.hasPrefix("LOG_END=") }).flatMap { UInt32($0.dropFirst(8)) }
    }
}
