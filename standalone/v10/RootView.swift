import SwiftUI

struct RootView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @State private var showPicker = false
    @State private var selectedTab = 0
    @State private var documentsVehicle: GarageVehicle?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.055, green: 0.015, blue: 0.025), Color(red: 0.01, green: 0.065, blue: 0.085)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.red.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -160, y: -300)

            Circle()
                .fill(.cyan.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 88)
                .offset(x: 170, y: -240)

            Group {
                switch selectedTab {
                case 1: GarageView()
                case 2: FleetMapView()
                case 3: SettingsView()
                case 4:
                    NavigationStack { AboutView() }
                default: homeView
                }
            }
            .padding(.top, 102)
            .padding(.bottom, 96)

            VStack(spacing: 0) {
                topHeader
                Spacer(minLength: 0)
                liquidTabBar
            }
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .sheet(isPresented: $showPicker) {
            VehiclePickerView(title: garage.vehicles.isEmpty ? pdt("choose_vehicle") : pdt("add_car"))
        }
        .sheet(item: $documentsVehicle) { vehicle in
            NavigationStack {
                CustomerDocumentsView(vehicle: vehicle)
                    .environmentObject(garage)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.cyan)
    }

    private var topHeader: some View {
        HStack(spacing: 12) {
            PunisherBrandMark(size: 54, showWordmark: true)

            Spacer()

            if selectedTab == 0 {
                Button { showPicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.07), in: Circle())
                        .overlay(Circle().stroke(.red.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pdt("add_car"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 47)
        .padding(.bottom, 8)
        .background { Color.black.opacity(0.94).ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LinearGradient(colors: [.red.opacity(0.35), .cyan.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)
        }
    }

    private var headerSubtitle: String {
        guard let vehicle = garage.activeVehicle, let profile = vehicle.profile else {
            return "Smart Vehicle Control"
        }
        return "\(profile.make) \(profile.model) \(String(vehicle.year))"
    }

    private var homeView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if let vehicle = garage.activeVehicle, let profile = vehicle.profile {
                    activeVehicleHero(vehicle: vehicle, profile: profile)
                    statusStrip(vehicle: vehicle)
                    NavigationLink {
                        VehicleAppearanceView(vehicle: vehicle)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: vehicle.vehicleColorHex))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.white.opacity(0.25)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pdt("vehicle_color_plate")).font(.subheadline.bold())
                                Text(vehicle.vehiclePlateText.isEmpty ? pdt("choose_color_plate") : vehicle.vehiclePlateText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.left")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.36))
                        }
                        .padding(12)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        documentsVehicle = vehicle
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.text.rectangle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.cyan)
                                .frame(width: 34, height: 34)
                                .background(.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pd(
                                    "معلومات الزبون والمستمسكات",
                                    "Customer & documents",
                                    "زانیاری و بەڵگەکانی کڕیار",
                                    "Müşteri ve belgeler",
                                    "مشتری و مدارک"
                                ))
                                .font(.subheadline.bold())

                                Text(documentStatus(vehicle))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: PDLocalization.current.isRTL ? "chevron.left" : "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.36))
                        }
                        .padding(12)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.cyan.opacity(0.13)))
                    }
                    .buttonStyle(.plain)

                    quickControls(profile: profile)
                    systemCards(vehicle: vehicle, profile: profile)
                } else {
                    emptyGarageCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
    }

    private func documentStatus(_ vehicle: GarageVehicle) -> String {
        let count = (vehicle.hasAnnualCardDocument ? 1 : 0) + (vehicle.hasUnifiedIDDocument ? 1 : 0)
        if count == 2 {
            return pd("السنوية والبطاقة الموحدة محفوظات محلياً", "Registration and ID saved locally", "سنویە و کارتی نیشتمانی ناوخۆ پاشەکەوت کراون", "Ruhsat ve kimlik yerel kaydedildi", "کارت خودرو و کارت ملی محلی ذخیره شده")
        }
        if count == 1 {
            return pd("مستمسك واحد محفوظ محلياً", "One document saved locally", "یەک بەڵگە ناوخۆ پاشەکەوت کراوە", "Bir belge yerel kaydedildi", "یک مدرک محلی ذخیره شده")
        }
        return pd("أضف السنوية والبطاقة الموحدة", "Add registration and unified ID", "سنویە و کارتی نیشتمانی زیاد بکە", "Ruhsat ve kimlik ekle", "کارت خودرو و کارت ملی را اضافه کنید")
    }

    private func activeVehicleHero(vehicle: GarageVehicle, profile: VehicleProfile) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.displayName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("\(profile.make) \(profile.model) • \(String(vehicle.year))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Text(pdt("active").uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.cyan.opacity(0.12), in: Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.09), .white.opacity(0.035), .cyan.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(colors: [.red.opacity(0.34), .cyan.opacity(0.30)], startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1
                            )
                    }

                VehicleAssetImage(
                    profile: profile,
                    colorHex: vehicle.vehicleColorHex,
                    maxHeight: 214,
                    plateText: vehicle.vehiclePlateText
                )
                .padding(.horizontal, 2)
            }
            .frame(height: 226)
        }
        .glassCard(padding: 14)
    }

    private func statusStrip(vehicle: GarageVehicle) -> some View {
        HStack(spacing: 8) {
            statusPill(
                vehicle.hasESP ? "ESP Online" : "ESP Offline",
                icon: vehicle.hasESP ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                active: vehicle.hasESP
            )
            statusPill("GPS", icon: "location.fill", active: false)
            statusPill("OBD", icon: "waveform.path.ecg", active: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPill(_ title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
        }
        .font(.caption.bold())
        .foregroundStyle(active ? .cyan : .white.opacity(0.70))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background((active ? Color.cyan : Color.white).opacity(active ? 0.12 : 0.06), in: Capsule())
        .overlay(Capsule().stroke((active ? Color.cyan : Color.white).opacity(0.16)))
    }

    private func quickControls(profile: VehicleProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(pdt("quick_control")).font(.headline)
                Spacer()
                Text("حسب بروفايل السيارة")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                controlButton(pdt("lock"), icon: "lock.fill", enabled: profile.capabilities.has(.lock), tint: .red)
                controlButton(pdt("unlock"), icon: "lock.open.fill", enabled: profile.capabilities.has(.unlock), tint: .cyan)
                controlButton(pdt("start"), icon: "power", enabled: profile.capabilities.has(.remoteStart), tint: .red)
                controlButton(pdt("alarm"), icon: "bell.and.waves.left.and.right.fill", enabled: profile.capabilities.has(.alarm), tint: .cyan)
            }
        }
        .glassCard(padding: 14)
    }

    private func controlButton(_ title: String, icon: String, enabled: Bool, tint: Color) -> some View {
        Button {} label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(enabled ? tint : .white.opacity(0.46))
                Text(title).font(.subheadline.bold())
                Text(enabled ? pdt("profile_ready") : pdt("not_enabled"))
                    .font(.caption2)
                    .foregroundStyle(enabled ? .white.opacity(0.72) : .white.opacity(0.38))
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(tint.opacity(enabled ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(enabled ? 0.25 : 0.08)))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(enabled ? 1 : 0.72)
    }

    private func systemCards(vehicle: GarageVehicle, profile: VehicleProfile) -> some View {
        HStack(spacing: 10) {
            infoCard(title: pdt("garage"), value: "\(garage.vehicles.count)", subtitle: pdt("vehicles"), icon: "car.2.fill")
            infoCard(title: "ESP", value: vehicle.hasESP ? pdt("linked") : pdt("not_linked"), subtitle: vehicle.hasESP ? vehicle.espLabel : "من الكراج", icon: "cpu")
            infoCard(title: pdt("profile"), value: profile.generation, subtitle: profile.id, icon: "slider.horizontal.3")
        }
    }

    private func infoCard(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).font(.headline).foregroundStyle(.cyan)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1)
            Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.07)))
    }

    private var emptyGarageCard: some View {
        VStack(spacing: 18) {
            PunisherBrandMark(size: 96)
            VStack(spacing: 6) {
                Text(pdt("garage_empty")).font(.title2.bold())
                Text("أضف أول سيارة وحدد الماركة والموديل والسنة. بعدها يصير عندك بروفايل مستقل لكل سيارة.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { showPicker = true } label: {
                Label(pdt("add_first_car"), systemImage: "plus.circle.fill")
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
        .padding(20)
        .glassCard()
    }

    private var liquidTabBar: some View {
        HStack(spacing: 6) {
            tabButton(1, title: pdt("garage"), icon: "car.2.fill")
            tabButton(2, title: pdt("map"), icon: "map.fill")
            tabButton(0, title: pdt("home"), icon: "house.fill", prominent: true)
            tabButton(3, title: pdt("settings"), icon: "gearshape.fill")
            tabButton(4, title: pdt("about"), icon: "info.circle.fill")
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 28)
        .background { Color.black.opacity(0.96).ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(colors: [.red.opacity(0.30), .cyan.opacity(0.30)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.7)
        }
    }

    private func tabButton(_ index: Int, title: String, icon: String, prominent: Bool = false) -> some View {
        let active = selectedTab == index
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = index }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if prominent {
                        Circle()
                            .fill(active ? Color.red.opacity(0.20) : Color.white.opacity(0.045))
                            .frame(width: 48, height: 48)
                            .overlay(Circle().stroke(active ? Color.red.opacity(0.70) : Color.white.opacity(0.08), lineWidth: 1))
                            .shadow(color: active ? .red.opacity(0.45) : .clear, radius: 10)
                    }
                    Image(systemName: icon)
                        .font(.system(size: prominent ? 22 : 19, weight: .semibold))
                }
                .frame(height: prominent ? 48 : 30)

                Text(title).font(.caption2.bold())
            }
            .foregroundStyle(active ? (prominent ? Color.red : Color.cyan) : .white.opacity(0.48))
            .frame(maxWidth: .infinity)
            .padding(.vertical, prominent ? 2 : 7)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func glassCard(padding: CGFloat = 0) -> some View {
        self
            .padding(padding)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.085), .white.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(colors: [.red.opacity(0.18), .white.opacity(0.06), .cyan.opacity(0.16)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1
                    )
            )
    }
}
