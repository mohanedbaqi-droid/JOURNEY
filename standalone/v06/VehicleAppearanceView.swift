import SwiftUI

struct VehicleAppearanceView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @Environment(\.dismiss) private var dismiss

    let vehicle: GarageVehicle

    @State private var selectedHex: String
    @State private var plateText: String

    private let palette: [VehiclePaint] = [
        .init(name: "أبيض", hex: "#F2F2F2"),
        .init(name: "أسود", hex: "#161616"),
        .init(name: "فضي", hex: "#A8ADB3"),
        .init(name: "رمادي", hex: "#5C6268"),
        .init(name: "أحمر", hex: "#C91F28"),
        .init(name: "أزرق", hex: "#1D5FA7"),
        .init(name: "سماوي", hex: "#19AFC8"),
        .init(name: "أخضر", hex: "#276B49"),
        .init(name: "بيج", hex: "#C7B99A"),
        .init(name: "ذهبي", hex: "#B08A43")
    ]

    init(vehicle: GarageVehicle) {
        self.vehicle = vehicle
        _selectedHex = State(initialValue: vehicle.vehicleColorHex)
        _plateText = State(initialValue: vehicle.vehiclePlateText)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.055, green: 0.015, blue: 0.025), Color(red: 0.01, green: 0.065, blue: 0.085)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    previewCard
                    colorSection
                    plateSection

                    Button {
                        garage.updateAppearance(vehicle, colorHex: selectedHex, plateText: plateText)
                        dismiss()
                    } label: {
                        Label("حفظ شكل السيارة", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(colors: [.red, .cyan], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .navigationTitle("شكل السيارة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.94), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var previewCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vehicle.displayName).font(.headline)
                    if let profile = vehicle.profile {
                        Text("\(profile.make) \(profile.model) • \(String(vehicle.year))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Circle()
                    .fill(Color(hex: selectedHex))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.white.opacity(0.045))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(
                        LinearGradient(colors: [.red.opacity(0.28), .cyan.opacity(0.28)], startPoint: .leading, endPoint: .trailing)
                    ))

                VStack(spacing: 6) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 88, weight: .light))
                        .foregroundStyle(Color(hex: selectedHex))
                        .shadow(color: Color(hex: selectedHex).opacity(0.30), radius: 12)

                    Text(plateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "رقم السيارة" : plateText)
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black.opacity(0.55), lineWidth: 1))
                }
            }
            .frame(height: 180)

            Text("الصورة الفعلية للسيارة راح تستخدم نفس اللون والرقم المحفوظين.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08)))
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("لون السيارة", systemImage: "paintpalette.fill")
                .font(.headline)
                .foregroundStyle(.cyan)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                ForEach(palette) { paint in
                    Button {
                        selectedHex = paint.hex
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: paint.hex))
                                    .frame(width: 42, height: 42)
                                    .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
                                if selectedHex.caseInsensitiveCompare(paint.hex) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .black))
                                        .foregroundStyle(paint.hex == "#F2F2F2" ? .black : .white)
                                }
                            }
                            Text(paint.name)
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.cyan.opacity(0.16)))
    }

    private var plateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("رقم السيارة", systemImage: "rectangle.and.pencil.and.ellipsis")
                .font(.headline)
                .foregroundStyle(.red)

            TextField("مثال: 27A77884", text: $plateText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.red.opacity(0.24)))

            Text("ينكتب كنص على مكان لوحة السيارة داخل الصورة.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.red.opacity(0.16)))
    }
}

private struct VehiclePaint: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
