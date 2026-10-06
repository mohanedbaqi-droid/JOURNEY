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
                    }

                    if let vehicle = garage.activeVehicle, let profile = vehicle.profile {
                        settingsCard("السيارة النشطة", icon: "car.fill") {
                            settingRow("السيارة", value: vehicle.displayName)
                            settingRow("النوع", value: "\(profile.make) \(profile.model) \(String(vehicle.year))")
                            settingRow("ESP", value: vehicle.hasESP ? vehicle.espLabel : "غير مربوط")
                        }
                    }

                    settingsCard("الكراج", icon: "car.2.fill") {
                        NavigationLink { GarageView() } label: {
                            navRow("إدارة الكراج", subtitle: "إضافة، حذف وتبديل السيارة النشطة", icon: "car.2.fill")
                        }
                        Button { showAddVehicle = true } label: {
                            navRow("إضافة سيارة ثانية", subtitle: "ماركة • موديل • سنة", icon: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    settingsCard("عن التطبيق", icon: "info.circle.fill") {
                        settingRow("الإصدار", value: "0.5.0 (5)")
                        settingRow("البروفايلات", value: String(VehicleCatalog.profiles.count))
                        settingRow("السيارات بالكراج", value: String(garage.vehicles.count))
                        settingRow("المشروع", value: "Standalone")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddVehicle) { VehiclePickerView(title: "إضافة سيارة") }
        }
    }

    private func settingsCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
            content()
        }
        .padding(15)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07)))
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

    private func navRow(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 34, height: 34)
                .background(.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
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
