import SwiftUI

struct PunisherBrandMark: View {
    var size: CGFloat = 48
    var showWordmark: Bool = false

    var body: some View {
        if showWordmark {
            HStack(spacing: 10) {
                Image("PunisherMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: .red.opacity(0.35), radius: 12)
                VStack(alignment: .leading, spacing: -2) {
                    Text("PUNISHER")
                        .font(.system(size: size * 0.33, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .red], startPoint: .top, endPoint: .bottom)
                        )
                    Text("DRIVE")
                        .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .cyan], startPoint: .top, endPoint: .bottom)
                        )
                }
            }
        } else {
            Image("PunisherMark")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .red.opacity(0.30), radius: 10)
                .shadow(color: .cyan.opacity(0.18), radius: 8)
        }
    }
}

struct PunisherWordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            Text("PUNISHER")
                .foregroundStyle(.red)
            Text("DRIVE")
                .foregroundStyle(.cyan)
        }
        .font(.system(size: 22, weight: .black, design: .rounded))
        .italic()
        .tracking(0.8)
    }
}
