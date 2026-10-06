import Foundation
import SwiftUI

struct IraqGovernoratePlateCode: Identifiable, Hashable {
    let code: String
    let nameAR: String
    let nameEN: String
    var id: String { code }
}

enum IraqPlateData {
    static let governorates: [IraqGovernoratePlateCode] = [
        .init(code: "11", nameAR: "بغداد", nameEN: "Baghdad"),
        .init(code: "12", nameAR: "نينوى", nameEN: "Nineveh"),
        .init(code: "13", nameAR: "ميسان", nameEN: "Maysan"),
        .init(code: "14", nameAR: "البصرة", nameEN: "Basra"),
        .init(code: "15", nameAR: "الأنبار", nameEN: "Al Anbar"),
        .init(code: "16", nameAR: "القادسية", nameEN: "Al-Qadisiyyah"),
        .init(code: "17", nameAR: "المثنى", nameEN: "Muthanna"),
        .init(code: "18", nameAR: "بابل", nameEN: "Babil"),
        .init(code: "19", nameAR: "كربلاء", nameEN: "Karbala"),
        .init(code: "20", nameAR: "ديالى", nameEN: "Diyala"),
        .init(code: "21", nameAR: "السليمانية", nameEN: "Sulaymaniyah"),
        .init(code: "22", nameAR: "أربيل", nameEN: "Erbil"),
        .init(code: "23", nameAR: "حلبجة", nameEN: "Halabja"),
        .init(code: "24", nameAR: "دهوك", nameEN: "Duhok"),
        .init(code: "25", nameAR: "كركوك", nameEN: "Kirkuk"),
        .init(code: "26", nameAR: "صلاح الدين", nameEN: "Saladin"),
        .init(code: "27", nameAR: "ذي قار", nameEN: "Dhi Qar"),
        .init(code: "28", nameAR: "النجف", nameEN: "Najaf"),
        .init(code: "29", nameAR: "واسط", nameEN: "Wasit")
    ]

    // Letters listed by the 2025 Iraqi plate instructions. "J" is normalized to uppercase.
    static let serialLetters: [String] = ["A", "B", "J", "D", "R", "S", "T", "F", "K", "M", "N", "H", "W", "E", "Q", "L", "Z"]

    static func governorateName(for code: String) -> String {
        governorates.first(where: { $0.code == code })?.nameAR ?? code
    }

    static func normalizeNumber(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(6))
    }

    static func formatted(code: String, letter: String, number: String) -> String {
        let n = normalizeNumber(number)
        guard !code.isEmpty, !letter.isEmpty, !n.isEmpty else { return "" }
        return "\(code) \(letter.uppercased()) \(n)"
    }

    static func parse(_ text: String) -> (code: String, letter: String, number: String)? {
        let parts = text.uppercased().split(whereSeparator: { $0 == " " || $0 == "-" })
        guard parts.count >= 3 else { return nil }
        let code = String(parts[0])
        let letter = String(parts[1])
        let number = normalizeNumber(String(parts[2]))
        guard governorates.contains(where: { $0.code == code }),
              serialLetters.contains(letter),
              !number.isEmpty else { return nil }
        return (code, letter, number)
    }
}

struct IraqiPlateView: View {
    let governorateCode: String
    let letter: String
    let number: String
    var compact: Bool = false

    private var displayNumber: String {
        number.isEmpty ? "000000" : number
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("I")
                Text("R")
                Text("Q")
            }
            .font(.system(size: compact ? 5 : 8, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: compact ? 10 : 15)

            Rectangle()
                .fill(Color.black.opacity(0.65))
                .frame(width: 0.7)

            Text(governorateCode)
                .frame(width: compact ? 22 : 35)

            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 0.6)

            Text(letter.isEmpty ? "A" : letter)
                .frame(width: compact ? 18 : 28)

            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 0.6)

            Text(displayNumber)
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.55)
        }
        .font(.system(size: compact ? 8 : 13, weight: .black, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.vertical, compact ? 2 : 4)
        .padding(.horizontal, compact ? 3 : 5)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: compact ? 2 : 4).stroke(Color.black.opacity(0.72), lineWidth: compact ? 0.6 : 1))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 2 : 4))
        .environment(\.layoutDirection, .leftToRight)
    }
}
