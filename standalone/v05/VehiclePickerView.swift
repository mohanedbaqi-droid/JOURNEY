import SwiftUI

struct VehiclePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var garage: VehicleProfileStore

    var title: String = "إضافة سيارة"

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
                            Text("اختار الماركة والموديل والسنة فقط")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        VStack(spacing: 0) {
                            selectionRow("ماركة الصنع", value: make.isEmpty ? "اختار" : make) {
                                Picker("ماركة الصنع", selection: $make) {
                                    Text("اختار").tag("")
                                    ForEach(VehicleCatalog.makes, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            selectionRow("الموديل", value: model.isEmpty ? "اختار" : model) {
                                Picker("الموديل", selection: $model) {
                                    Text("اختار").tag("")
                                    ForEach(models, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            selectionRow("سنة الصنع", value: candidateYears.isEmpty ? "—" : String(year)) {
                                Picker("سنة الصنع", selection: $year) {
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
                            Text("اسم اختياري").font(.caption).foregroundStyle(.secondary)
                            TextField("مثلاً: سيارتي / سيارة الوالد", text: $nickname)
                                .textInputAutocapitalization(.words)
                                .padding(13)
                                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07)))
                        }

                        if let matched {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("البروفايل جاهز", systemImage: "checkmark.seal.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.green)
                                    Spacer()
                                }
                                Text(matched.displayName).font(.headline)
                                Text("الجيل: \(matched.generation)")
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
                            Label("إضافة إلى الكراج واعتمادها", systemImage: "plus.circle.fill")
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
                    Button("إغلاق") { dismiss() }.foregroundStyle(.cyan)
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
