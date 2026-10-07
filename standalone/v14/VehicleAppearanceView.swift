import SwiftUI

struct VehicleAppearanceView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @Environment(\.dismiss) private var dismiss

    let vehicle: GarageVehicle

    @State private var selectedHex: String
    @State private var governorateCode: String
    @State private var plateLetter: String
    @State private var plateNumber: String

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
        _governorateCode = State(initialValue: vehicle.vehiclePlateGovernorateCode)
        _plateLetter = State(initialValue: vehicle.vehiclePlateLetter)
        _plateNumber = State(initialValue: vehicle.vehiclePlateNumber)
    }

    private var formattedPlate: String {
        IraqPlateData.formatted(code: governorateCode, letter: plateLetter, number: plateNumber)
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
                        garage.updateAppearance(
                            vehicle,
                            colorHex: selectedHex,
                            governorateCode: governorateCode,
                            plateLetter: plateLetter,
                            plateNumber: plateNumber
                        )
                        dismiss()
                    } label: {
                        Label(pdt("save_appearance"), systemImage: "checkmark.circle.fill")
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
                    .disabled(plateNumber.isEmpty)
                    .opacity(plateNumber.isEmpty ? 0.55 : 1)
                }
                .padding(16)
            }
        }
        .navigationTitle(pdt("appearance"))
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
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.06), .white.opacity(0.025), .cyan.opacity(0.055)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(
                        LinearGradient(colors: [.red.opacity(0.28), .cyan.opacity(0.28)], startPoint: .leading, endPoint: .trailing)
                    ))

                if let profile = vehicle.profile {
                    VehicleAssetImage(
                        profile: profile,
                        colorHex: selectedHex,
                        maxHeight: 210,
                        plateText: formattedPlate
                    )
                    .padding(.horizontal, 4)
                }
            }
            .frame(height: 220)

            if !plateNumber.isEmpty {
                IraqiPlateView(
                    governorateCode: governorateCode,
                    letter: plateLetter,
                    number: plateNumber
                )
                .frame(width: 230, height: 42)
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08)))
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(pdt("vehicle_color"), systemImage: "paintpalette.fill")
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
        VStack(alignment: .leading, spacing: 14) {
            Label(pdt("iraqi_plate"), systemImage: "rectangle.and.pencil.and.ellipsis")
                .font(.headline)
                .foregroundStyle(.red)

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pdt("governorate")).font(.caption).foregroundStyle(.secondary)
                        Menu {
                            ForEach(IraqPlateData.governorates) { item in
                                Button("\(item.code) • \(item.nameAR)") {
                                    governorateCode = item.code
                                }
                            }
                        } label: {
                            HStack {
                                Text("\(governorateCode) • \(IraqPlateData.governorateName(for: governorateCode))")
                                    .font(.subheadline.bold())
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption.bold())
                                    .foregroundStyle(.cyan)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 48)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.cyan.opacity(0.22)))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(pdt("letter")).font(.caption).foregroundStyle(.secondary)
                        Menu {
                            ForEach(IraqPlateData.serialLetters, id: \.self) { letter in
                                Button(letter) { plateLetter = letter }
                            }
                        } label: {
                            HStack {
                                Text(plateLetter)
                                    .font(.system(.title3, design: .monospaced).bold())
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 12)
                            .frame(width: 92, height: 48)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.red.opacity(0.22)))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(pdt("number_6"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("123456", text: $plateNumber)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.13)))
                        .onChange(of: plateNumber) { _, newValue in
                            let normalized = IraqPlateData.normalizeNumber(newValue)
                            if normalized != newValue { plateNumber = normalized }
                        }
                }
            }

            HStack {
                Text(pdt("final_format"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedPlate.isEmpty ? "XX A XXXXXX" : formattedPlate)
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(.white)
            }

            Text(pd("رمز المحافظة والحرف اختيارات جاهزة، وإنت تكتب الرقم فقط.","Governorate and letter are selectable; you only enter the number.","پارێزگا و پیت هەڵبژاردەن؛ تۆ تەنها ژمارەکە دەنووسیت.","İl ve harf seçilir; yalnızca numarayı girersin.","استان و حرف انتخابی هستند؛ فقط شماره را وارد می‌کنید."))
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
