import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @State private var showAddVehicle = false
    @AppStorage(PDLocalization.key) private var language = "ar"

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pdt("settings"))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("Punisher Drive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PunisherBrandMark(size: 46)
                    }

                    settingsCard(pdt("language"), icon: "globe", tint: .cyan) {
                        Menu {
                            ForEach(PDLanguage.allCases) { item in
                                Button {
                                    language = item.rawValue
                                } label: {
                                    HStack {
                                        Text(item.label)
                                        if language == item.rawValue {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "character.bubble.fill")
                                    .foregroundStyle(.cyan)
                                Text(PDLanguage(rawValue: language)?.label ?? "العربية")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(PDLanguage(rawValue: language)?.shortLabel ?? "AR")
                                    .font(.caption.bold())
                                    .foregroundStyle(.cyan)
                                Image(systemName: "chevron.down")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Text(pdt("language_note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        SmartAIView()
                    } label: {
                        settingsCard(pdt("smart_ai"), icon: "sparkles", tint: .purple) {
                            navRow(
                                pdt("smart_ai"),
                                subtitle: pdt("smart_ai_sub"),
                                icon: "brain.head.profile",
                                tint: .purple
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    if let vehicle = garage.activeVehicle, let profile = vehicle.profile {
                        settingsCard(pdt("active_vehicle"), icon: "car.fill", tint: .red) {
                            settingRow(pdt("vehicle"), value: vehicle.displayName)
                            settingRow(pdt("model"), value: "\(profile.make) \(profile.model) \(String(vehicle.year))")
                            settingRow("ESP", value: vehicle.hasESP ? vehicle.espLabel : pdt("not_linked"))
                        }
                    }

                    settingsCard(pdt("garage"), icon: "car.2.fill", tint: .cyan) {
                        NavigationLink { GarageView() } label: {
                            navRow(
                                pdt("manage_garage"),
                                subtitle: pd(
                                    "إضافة، حذف وتبديل السيارة النشطة",
                                    "Add, remove and switch active vehicle",
                                    "زیادکردن، سڕینەوە و گۆڕینی ئۆتۆمبێلی چالاک",
                                    "Araç ekleme, silme ve aktif aracı değiştirme",
                                    "افزودن، حذف و تغییر خودروی فعال"
                                ),
                                icon: "car.2.fill",
                                tint: .cyan
                            )
                        }

                        Button { showAddVehicle = true } label: {
                            navRow(
                                pdt("add_car"),
                                subtitle: pd("ماركة • موديل • سنة", "Make • Model • Year", "براند • مۆدێل • ساڵ", "Marka • Model • Yıl", "برند • مدل • سال"),
                                icon: "plus.circle.fill",
                                tint: .red
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    settingsCard(pdt("connection"), icon: "antenna.radiowaves.left.and.right", tint: .cyan) {
                        navRow(
                            pdt("connect_esp"),
                            subtitle: garage.activeVehicle?.hasESP == true
                                ? pd("الجهاز مربوط بالسيارة النشطة", "Device is linked to active vehicle", "ئامێرەکە بە ئۆتۆمبێلی چالاکەوە پەیوەستە", "Cihaz aktif araca bağlı", "دستگاه به خودروی فعال متصل است")
                                : pdt("not_linked"),
                            icon: "cpu",
                            tint: .cyan
                        )
                        navRow("GPS", subtitle: pdt("gps_tracking"), icon: "location.fill", tint: .red)
                        navRow("OBD", subtitle: pdt("obd_diag"), icon: "waveform.path.ecg", tint: .cyan)
                    }

                    settingsCard(pd("بيانات الزبائن", "Customer data", "داتای کڕیار", "Müşteri verileri", "اطلاعات مشتری"), icon: "person.2.badge.gearshape.fill", tint: .green) {
                        NavigationLink { CustomerServerSettingsView() } label: {
                            navRow(
                                "Customer Server",
                                subtitle: pd(
                                    "تهيئة السيرفر الخاص برفع معلومات الزبائن والمستمسكات",
                                    "Configure the private server for customer data and documents",
                                    "ڕێکخستنی سێرڤەری تایبەت بۆ داتا و بەڵگەکانی کڕیار",
                                    "Müşteri verileri ve belgeleri için özel sunucuyu yapılandır",
                                    "تنظیم سرور خصوصی برای اطلاعات و مدارک مشتری"
                                ),
                                icon: "server.rack",
                                tint: .green
                            )
                        }
                    }

                    settingsCard(pdt("app"), icon: "gearshape.2.fill", tint: .red) {
                        navRow(pdt("notifications"), subtitle: pd("تنبيهات السيارة والاتصال", "Vehicle and connection alerts", "ئاگادارکردنەوەی ئۆتۆمبێل و پەیوەندی", "Araç ve bağlantı uyarıları", "هشدارهای خودرو و اتصال"), icon: "bell.fill", tint: .red)
                        NavigationLink { AboutView() } label: {
                            navRow(pdt("about_app"), subtitle: pd("المطور، التواصل والإصدارات", "Developer, contact and versions", "گەشەپێدەر، پەیوەندی و وەشانەکان", "Geliştirici, iletişim ve sürümler", "توسعه‌دهنده، تماس و نسخه‌ها"), icon: "info.circle.fill", tint: .cyan)
                        }
                    }

                    HStack {
                        Text(pdt("version"))
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
            .sheet(isPresented: $showAddVehicle) {
                VehiclePickerView(title: pdt("add_car"))
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "14"
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
            Image(systemName: PDLocalization.current.isRTL ? "chevron.left" : "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.vertical, 4)
    }
}
