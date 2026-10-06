import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @State private var showAddVehicle = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("الإعدادات")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("Punisher Drive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PunisherBrandMark(size: 46)
                    }

                    if let vehicle = garage.activeVehicle, let profile = vehicle.profile {
                        settingsCard("السيارة النشطة", icon: "car.fill", tint: .red) {
                            settingRow("السيارة", value: vehicle.displayName)
                            settingRow("النوع", value: "\(profile.make) \(profile.model) \(String(vehicle.year))")
                            settingRow("ESP", value: vehicle.hasESP ? vehicle.espLabel : "غير مربوط")
                        }
                    }

                    settingsCard("الكراج", icon: "car.2.fill", tint: .cyan) {
                        NavigationLink { GarageView() } label: {
                            navRow("إدارة الكراج", subtitle: "إضافة، حذف وتبديل السيارة النشطة", icon: "car.2.fill", tint: .cyan)
                        }
                        Button { showAddVehicle = true } label: {
                            navRow("إضافة سيارة", subtitle: "ماركة • موديل • سنة", icon: "plus.circle.fill", tint: .red)
                        }
                        .buttonStyle(.plain)
                    }

                    settingsCard("الاتصال", icon: "antenna.radiowaves.left.and.right", tint: .cyan) {
                        navRow("ربط ESP", subtitle: garage.activeVehicle?.hasESP == true ? "الجهاز مربوط بالسيارة النشطة" : "اختيار وربط جهاز السيارة", icon: "cpu", tint: .cyan)
                        navRow("GPS", subtitle: "إعداد التتبع والموقع", icon: "location.fill", tint: .red)
                        navRow("OBD", subtitle: "التشخيص وبيانات السيارة", icon: "waveform.path.ecg", tint: .cyan)
                    }

                    settingsCard("التطبيق", icon: "gearshape.2.fill", tint: .red) {
                        navRow("الإشعارات", subtitle: "تنبيهات السيارة والاتصال", icon: "bell.fill", tint: .red)
                        NavigationLink { AboutView() } label: {
                            navRow("حول التطبيق", subtitle: "المطور، التواصل والإصدارات", icon: "info.circle.fill", tint: .cyan)
                        }
                    }

                    HStack {
                        Text("الإصدار")
                        Spacer()
                        Text(appVersion)
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddVehicle) { VehiclePickerView(title: "إضافة سيارة") }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "7"
        return "\(version) (\(build))"
    }

    private func settingsCard<Content: View>(_ title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            content()
        }
        .padding(15)
        .background(
            LinearGradient(colors: [tint.opacity(0.065), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(tint.opacity(0.20)))
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }

    private func navRow(_ title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(0.18)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.left")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.vertical, 4)
    }
}
