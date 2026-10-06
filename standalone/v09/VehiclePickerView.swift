import SwiftUI

struct VehiclePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var garage: VehicleProfileStore

    var title: String = pdt("add_car")

    @State private var make = ""
    @State private var model = ""
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var nickname = ""

    private var models: [String] { VehicleCatalog.models(for: make) }
    private var candidateYears: [Int] {
        Array(Set(VehicleCatalog.profiles(make: make, model: model).flatMap(\.years))).sorted(by: >)
    }
    private var matched: VehicleProfile? { VehicleCatalog.match(make: make, model: model, year: year) }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.015, green: 0.035, blue: 0.07), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VStack(spacing: 8) {
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 54))
                                .foregroundStyle(.cyan)
                            Text(title).font(.title2.bold())
                            Text(pd("اختار الماركة والموديل والسنة فقط","Choose make, model and year","براند و مۆدێل و ساڵ هەڵبژێرە","Marka, model ve yılı seç","برند، مدل و سال را انتخاب کنید"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        VStack(spacing: 0) {
                            selectionRow(pdt("make"), value: make.isEmpty ? "اختار" : make) {
                                Picker(pdt("make"), selection: $make) {
                                    Text(pdt("choose")).tag("")
                                    ForEach(VehicleCatalog.makes, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            selectionRow(pdt("model"), value: model.isEmpty ? "اختار" : model) {
                                Picker(pdt("model"), selection: $model) {
                                    Text("اختار").tag("")
                                    ForEach(models, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            selectionRow(pdt("year"), value: candidateYears.isEmpty ? "—" : String(year)) {
                                Picker(pdt("year"), selection: $year) {
                                    ForEach(candidateYears, id: \.self) { Text(String($0)).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .disabled(candidateYears.isEmpty)
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07)))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(pdt("optional_name")).font(.caption).foregroundStyle(.secondary)
                            TextField(pd("مثلاً: سيارتي / سيارة الوالد","Example: My car / Family car","نموونە: ئۆتۆمبێلەکەم / ئۆتۆمبێلی خێزان","Örn: Benim aracım / Aile aracı","مثال: خودروی من / خودروی خانواده"), text: $nickname)
                                .textInputAutocapitalization(.words)
                                .padding(13)
                                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07)))
                        }

                        if let matched {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(pd("البروفايل جاهز","Profile ready","پرۆفایل ئامادەیە","Profil hazır","پروفایل آماده"), systemImage: "checkmark.seal.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.green)
                                    Spacer()
                                }
                                Text(matched.displayName).font(.headline)
                                Text(pd("الجيل:","Generation:","نەوە:","Nesil:","نسل:") + " \(matched.generation)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.green.opacity(0.18)))
                        }

                        Button {
                            guard let profile = matched else { return }
                            _ = garage.add(profile: profile, year: year, nickname: nickname)
                            dismiss()
                        } label: {
                            Label(pdt("add_to_garage"), systemImage: "plus.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(matched == nil ? Color.white.opacity(0.08) : Color.cyan, in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(matched == nil ? .white.opacity(0.35) : .black)
                        }
                        .buttonStyle(.plain)
                        .disabled(matched == nil)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(pdt("close")) { dismiss() }.foregroundStyle(.cyan)
                }
            }
            .toolbarBackground(.black.opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: make) { _, _ in
                model = models.first ?? ""
                year = candidateYears.first ?? year
            }
            .onChange(of: model) { _, _ in
                year = candidateYears.first ?? year
            }
        }
        .preferredColorScheme(.dark)
    }

    private func selectionRow<Content: View>(_ title: String, value: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.bold()).lineLimit(2)
            }
            Spacer(minLength: 8)
            control().labelsHidden().tint(.cyan)
        }
        .padding(.vertical, 11)
    }
}
