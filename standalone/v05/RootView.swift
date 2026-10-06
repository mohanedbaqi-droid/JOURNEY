import SwiftUI

struct RootView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @State private var showPicker = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.015, green: 0.035, blue: 0.07), Color(red: 0.02, green: 0.085, blue: 0.12), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.cyan.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 78)
                .offset(x: 150, y: -320)

            Group {
                switch selectedTab {
                case 1: GarageView()
                case 2: SettingsView()
                default: homeView
                }
            }
            .padding(.top, 92)
            .padding(.bottom, 92)

            VStack(spacing: 0) {
                topHeader
                Spacer(minLength: 0)
                liquidTabBar
            }
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .sheet(isPresented: $showPicker) {
            VehiclePickerView(title: garage.vehicles.isEmpty ? "اختيار أول سيارة" : "إضافة سيارة")
        }
        .preferredColorScheme(.dark)
        .tint(.cyan)
    }

    private var topHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(.white.opacity(0.07))
                    .frame(width: 46, height: 46)
                Image(systemName: "road.lanes")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("PUNISHER DRIVE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(0.5)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            if selectedTab == 0 {
                Button { showPicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إضافة سيارة")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
        .padding(.bottom, 10)
        .background { Color.black.opacity(0.94).ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
        }
    }

    private var headerSubtitle: String {
        {
            guard let vehicle = garage.activeVehicle, let profile = vehicle.profile else {
                return "Smart Vehicle Control"
            }
            return "\(profile.make) \(profile.model) \(String(format: "%d", vehicle.year))"
        }()
    }

    private var homeView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if let vehicle = garage.activeVehicle, let profile = vehicle.profile {
                    activeVehicleHero(vehicle: vehicle, profile: profile)
                    statusStrip(vehicle: vehicle)
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

    private func activeVehicleHero(vehicle: GarageVehicle, profile: VehicleProfile) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.displayName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("\(profile.make) \(profile.model) • \(String(format: "%d", vehicle.year))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Text("ACTIVE")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.08), .white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
                VStack(spacing: 10) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 72, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                    Text(profile.assetKey)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(height: 152)
        }
        .glassCard(padding: 14)
    }

    private func statusStrip(vehicle: GarageVehicle) -> some View {
        HStack(spacing: 8) {
            statusPill(
                vehicle.hasESP ? "ESP متصل" : "ESP غير مربوط",
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
        .foregroundStyle(active ? .green : .white.opacity(0.70))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background((active ? Color.green : Color.white).opacity(active ? 0.12 : 0.06), in: Capsule())
        .overlay(Capsule().stroke((active ? Color.green : Color.white).opacity(0.12)))
    }

    private func quickControls(profile: VehicleProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("التحكم السريع").font(.headline)
                Spacer()
                Text("حسب بروفايل السيارة")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                controlButton("قفل", icon: "lock.fill", enabled: profile.capabilities.has(.lock))
                controlButton("فتح", icon: "lock.open.fill", enabled: profile.capabilities.has(.unlock))
                controlButton("تشغيل", icon: "power", enabled: profile.capabilities.has(.remoteStart))
                controlButton("إنذار", icon: "bell.and.waves.left.and.right.fill", enabled: profile.capabilities.has(.alarm))
            }
        }
        .glassCard(padding: 14)
    }

    private func controlButton(_ title: String, icon: String, enabled: Bool) -> some View {
        Button {} label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Text(title).font(.subheadline.bold())
                Text(enabled ? "جاهز بالبروفايل" : "غير مفعّل")
                    .font(.caption2)
                    .foregroundStyle(enabled ? .green : .white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(.white.opacity(enabled ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(enabled ? 1 : 0.72)
    }

    private func systemCards(vehicle: GarageVehicle, profile: VehicleProfile) -> some View {
        HStack(spacing: 10) {
            infoCard(title: "الكراج", value: "\(garage.vehicles.count)", subtitle: "سيارات", icon: "car.2.fill")
            infoCard(title: "ESP", value: vehicle.hasESP ? "مربوط" : "غير مربوط", subtitle: vehicle.hasESP ? vehicle.espLabel : "من الكراج", icon: "cpu")
            infoCard(title: "البروفايل", value: profile.generation, subtitle: profile.id, icon: "slider.horizontal.3")
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
            Image(systemName: "car.2.fill")
                .font(.system(size: 54))
                .foregroundStyle(.cyan)
            VStack(spacing: 6) {
                Text("الكراج فارغ").font(.title2.bold())
                Text("أضف أول سيارة وحدد الماركة والموديل والسنة. بعدها يصير عندك بروفايل مستقل لكل سيارة.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { showPicker = true } label: {
                Label("إضافة أول سيارة", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.cyan, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassCard()
    }

    private var liquidTabBar: some View {
        HStack(spacing: 8) {
            tabButton(0, title: "الرئيسية", icon: "house.fill")
            tabButton(1, title: "الكراج", icon: "car.2.fill")
            tabButton(2, title: "الإعدادات", icon: "gearshape.fill")
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 28)
        .background { Color.black.opacity(0.96).ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
        }
    }

    private func tabButton(_ index: Int, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = index }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(title).font(.caption2.bold())
            }
            .foregroundStyle(selectedTab == index ? .cyan : .white.opacity(0.48))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(selectedTab == index ? .white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 15))
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
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}
