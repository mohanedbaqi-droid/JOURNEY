import Foundation
@preconcurrency import CoreBluetooth
import CoreLocation
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var mqtt: MQTTService
    @EnvironmentObject private var proximity: ProximityMonitor
    @EnvironmentObject private var devices: DeviceStore
    @EnvironmentObject private var homeShortcuts: HomeScreenShortcutRouter
    @EnvironmentObject private var nfcStore: NFCCredentialStore
    @EnvironmentObject private var nfcRouter: NFCLaunchRouter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var faceID = FaceIDAuthenticator()
    @State private var confirmStart = false
    @State private var pressedControlToken: String?
    @State private var showingDevices = false
    @State private var showingLocalDiagnostics = false
    @State private var showingOBDStatus = false
    @State private var showingNFC = false
    @State private var showingHUD = false
    @State private var showingMap = false
    @State private var showingMQTTSettings = false
    @State private var showingKeylessEntry = false
    @State private var faceIDError: String?
    @State private var selectedTab = 0
    @AppStorage("journey.settings.appearance") private var appAppearance = "dark"
    @AppStorage("journey.settings.textSize") private var appTextSize = "normal"
    @AppStorage("journey.settings.language") private var appLanguage = "ar"
    @AppStorage("journey.settings.speedUnit") private var appSpeedUnit = "kmh"
    @AppStorage("journey.settings.temperatureUnit") private var appTemperatureUnit = "c"

    private func appText(_ ar: String, _ en: String) -> String { appLanguage == "en" ? en : ar }

    private var preferredScheme: ColorScheme? {
        switch appAppearance {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }

    private var preferredDynamicType: DynamicTypeSize {
        switch appTextSize {
        case "small": return .small
        case "large": return .xLarge
        case "xlarge": return .xxLarge
        default: return .large
        }
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.02, green: 0.05, blue: 0.10), Color(red: 0.04, green: 0.11, blue: 0.17), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(.cyan.opacity(0.09))
                    .frame(width: 360)
                    .blur(radius: 70)
                    .offset(x: 130, y: -290)

                if let device = devices.selectedDevice {
                    let vehicle = mqtt.state(for: device.deviceID)
                    Group {
                        switch selectedTab {
                        case 4:
                            JourneyAppInfoView()
                        case 3:
                            OBDStatusView(vehicle: vehicle, deviceID: device.deviceID)
                                .environmentObject(mqtt)
                        case 1:
                            controlsPage(device: device, vehicle: vehicle)
                        case 2:
                            VehicleMapView(vehicle: vehicle, vehicleName: device.name, deviceID: device.deviceID)
                                .environmentObject(mqtt)
                        default:
                            overviewPage(device: device, vehicle: vehicle)
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        deviceHeader(device, vehicle: vehicle)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background {
                                Color.black
                                    .ignoresSafeArea(edges: .top)
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                            }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        liquidTabBar
                            .background {
                                Color.black
                                    .ignoresSafeArea(edges: .bottom)
                            }
                    }
                    .tint(.cyan)
                    .onAppear { mqtt.prepareBluetooth(for: device.deviceID) }
                } else {
                    emptyState
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingDevices) {
                ManageDevicesView()
                    .environmentObject(devices)
                    .environmentObject(proximity)
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingLocalDiagnostics) {
                NavigationStack {
                    ESPStatusView(
                        vehicle: devices.selectedDevice.map { mqtt.state(for: $0.deviceID) } ?? VehicleState(),
                        bluetoothStatus: mqtt.bluetoothStatus,
                        deviceID: devices.selectedDevice?.deviceID
                    )
                        .navigationTitle("فحص البورد المحلي")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("إغلاق") { showingLocalDiagnostics = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingOBDStatus) {
                NavigationStack {
                    OBDStatusView(
                        vehicle: devices.selectedDevice.map { mqtt.state(for: $0.deviceID) } ?? VehicleState(),
                        deviceID: devices.selectedDevice?.deviceID
                    )
                    .environmentObject(mqtt)
                        .navigationTitle("قراءة OBD عبر BLE")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("إغلاق") { showingOBDStatus = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingNFC) {
                NFCAccessView {
                    showingNFC = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        nfcRouter.requestInAppTest()
                    }
                }
                .environmentObject(nfcStore)
            }
            .sheet(isPresented: $showingHUD) {
                NavigationStack {
                    HUDControlView(
                        vehicle: devices.selectedDevice.map { mqtt.state(for: $0.deviceID) } ?? VehicleState()
                    )
                    .navigationTitle("شاشة HUD")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("تم") { showingHUD = false }
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingMap) {
                NavigationStack {
                    VehicleMapView(
                        vehicle: devices.selectedDevice.map { mqtt.state(for: $0.deviceID) } ?? VehicleState(),
                        vehicleName: devices.selectedDevice?.name ?? "JOURNEY",
                        deviceID: devices.selectedDevice?.deviceID
                    )
                    .environmentObject(mqtt)
                }
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingMQTTSettings) {
                MQTTSettingsView()
                    .environmentObject(mqtt)
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingKeylessEntry) {
                if let device = devices.selectedDevice {
                    KeylessEntrySettingsView(deviceID: device.deviceID)
                        .environmentObject(mqtt)
                        .preferredColorScheme(.dark)
                }
            }
            .onAppear {
                if devices.devices.isEmpty { showingDevices = true }
                if let device = devices.selectedDevice { mqtt.prepareBluetooth(for: device.deviceID) }
                if mqtt.isConfigured && mqtt.connection != .connected { mqtt.connect() }
                if let shortcut = homeShortcuts.consume() {
                    authenticateHomeScreenShortcut(shortcut)
                }
            }
            .onChange(of: scenePhase, initial: false) { _, phase in
                guard phase == .active, let device = devices.selectedDevice else { return }
                // Foregrounding an already-created SwiftUI view does not always
                // trigger onAppear. Wake BLE proactively so no button press is
                // required to make the ESP connect.
                mqtt.resumeBluetooth(for: device.deviceID)
            }
            .onChange(of: devices.selectedID, initial: false) { _, _ in
                guard let device = devices.selectedDevice else { return }
                mqtt.prepareBluetooth(for: device.deviceID)
            }
            .onReceive(homeShortcuts.$pendingShortcut) { shortcut in
                guard let shortcut else { return }
                homeShortcuts.clear()
                authenticateHomeScreenShortcut(shortcut)
            }
            .alert("تأكيد التشغيل عن بُعد", isPresented: $confirmStart) {
                Button("إلغاء", role: .cancel) {}
                Button("إرسال الأمر") {
                    guard let device = devices.selectedDevice else { return }
                    Task {
                        let allowed = await faceID.authenticate(reason: "تأكيد التشغيل عن بُعد لسيارة JOURNEY")
                        guard allowed else {
                            faceIDError = faceID.lastError
                            return
                        }
                        _ = mqtt.send(.start, to: device.deviceID)
                    }
                }
            } message: {
                Text("سيرسل التطبيق أمر تشغيل حقيقي إلى ESP. تأكد أن السيارة بمكان آمن والقير على P.")
            }
            .alert("تعذر التأكيد", isPresented: Binding(
                get: { faceIDError != nil },
                set: { if !$0 { faceIDError = nil } }
            )) {
                Button("حسنًا", role: .cancel) { faceIDError = nil }
            } message: {
                Text(faceIDError ?? "")
            }
        }
        .preferredColorScheme(preferredScheme)
        .dynamicTypeSize(preferredDynamicType)
        .environment(\.layoutDirection, appLanguage == "en" ? .leftToRight : .rightToLeft)
        .environment(\.locale, Locale(identifier: appLanguage == "en" ? "en" : "ar"))
        .tint(.cyan)
    }

    // الصفحة الأولى تبقى واجهة JOURNEY الأساسية: السيارة وحالتها المختصرة.
    private func overviewPage(device: DeviceProfile, vehicle: VehicleState) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                AnyView(quickNavigation)
                AnyView(CarVisualView(state: vehicle))
                AnyView(statusStrip(vehicle))
                AnyView(mainControls(device, state: vehicle))
                AnyView(telemetryCard(vehicle))
                AnyView(keylessEntryCard)
                AnyView(systemHealthCard(device: device, state: vehicle))
                AnyView(ownerManagementCard(device: device, state: vehicle))
                if let error = mqtt.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                }
                Text("JOURNEY CONNECTED CONTROL")
                    .font(.caption2.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.vertical, 8)
            }
            .padding()
            .padding(.top, 12)
        }
    }

    // كل ما يخص الفتح والقفل وحالة المحرك والريموت في صفحة مستقلة.
    private func controlsPage(device: DeviceProfile, vehicle: VehicleState) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                AnyView(mainControls(device, state: vehicle))
                AnyView(statusStrip(vehicle))
                AnyView(keylessEntryCard)
                AnyView(telemetryCard(vehicle))
                AnyView(aiAssistantCard(vehicle))
            }
            .padding()
            .padding(.top, 12)
        }
    }

    // ترتيب الأزرار مقصود: الرئيسية هي أول صفحة عند الفتح، لكن موقعها وسط
    // الشريط حتى تبقى نقطة التركيز البصرية في واجهة Liquid Glass.
    private var liquidTabBar: some View {
        ZStack(alignment: .center) {
            HStack(spacing: 4) {
                liquidTab(title: "معلومات", icon: "info.circle", tag: 4)
                liquidTab(title: "OBD", icon: "stethoscope", tag: 3)
                Color.clear.frame(width: 80, height: 40)
                liquidTab(title: "السيارة", icon: "car.fill", tag: 1)
                liquidTab(title: "الخريطة", icon: "map.fill", tag: 2)
            }
            .padding(.horizontal, 8)
            .frame(height: 60)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.90))
                    .overlay(Capsule().fill(.ultraThinMaterial).opacity(0.16))
            }
            .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))

            liquidHomeTab
                .offset(y: -10)
        }
        .frame(height: 72)
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    private func liquidTab(title: String, icon: String, tag: Int) -> some View {
        Button { selectedTab = tag } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(selectedTab == tag ? .cyan : .white.opacity(0.58))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selectedTab == tag ? .cyan.opacity(0.13) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var liquidHomeTab: some View {
        Button { selectedTab = 0 } label: {
            VStack(spacing: 3) {
                Image(systemName: "house.fill").font(.system(size: 22, weight: .bold))
                Text(appText("الرئيسية", "Home")).font(.system(size: 10, weight: .black))
            }
            .foregroundStyle(.white)
            .frame(width: 74, height: 74)
            .background(selectedTab == 0 ? Color.cyan.opacity(0.92) : Color.black.opacity(0.96), in: Circle())
            .overlay(Circle().stroke(selectedTab == 0 ? .white.opacity(0.62) : .cyan.opacity(0.55), lineWidth: 1.2))
            .shadow(color: .cyan.opacity(selectedTab == 0 ? 0.46 : 0.20), radius: 15, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mqtt.connection == .connected ? .green : .orange)
                .frame(width: 7, height: 7)
            Text(mqtt.connection.rawValue)
                .font(.caption.weight(.semibold))
        }
    }

    private func topAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.title3.bold())
                Text(title).font(.caption.bold())
            }
            .foregroundStyle(.cyan)
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.plain)
    }

    private var quickNavigation: some View {
        HStack(spacing: 0) {
                topAction("OBD", icon: "point.3.connected.trianglepath.dotted") { selectedTab = 3 }
                    .overlay(alignment: .trailing) { Divider().overlay(.cyan.opacity(0.18)) }
                topAction("ESP", icon: "cpu.fill") { showingLocalDiagnostics = true }
                    .overlay(alignment: .trailing) { Divider().overlay(.cyan.opacity(0.18)) }
                topAction("NFC", icon: "wave.3.right.circle.fill") { showingNFC = true }
                    .overlay(alignment: .trailing) { Divider().overlay(.cyan.opacity(0.18)) }
                topAction("HUD", icon: "display") { showingHUD = true }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25))
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(LinearGradient(colors: [.white.opacity(0.35), .cyan.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }

    private func authenticateHomeScreenShortcut(_ shortcut: HomeScreenShortcut) {
        guard let device = devices.selectedDevice else {
            faceIDError = "أضف جهاز السيارة أولاً حتى يعمل الاختصار."
            return
        }

        Task {
            let allowed = await faceID.authenticate(
                reason: "تأكيد \(shortcut.title) من اختصار الشاشة الرئيسية"
            )
            guard allowed else {
                faceIDError = faceID.lastError
                return
            }
            _ = mqtt.send(shortcut.action, to: device.deviceID)
        }
    }

    private func authenticateRemotePower(_ device: DeviceProfile, state: VehicleState) {
        Task {
            let turningOn = !state.remotePowered
            let allowed = await faceID.authenticate(
                reason: turningOn ? "تأكيد تشغيل طاقة ريموت السيارة" : "تأكيد إطفاء طاقة ريموت السيارة"
            )
            guard allowed else {
                faceIDError = faceID.lastError
                return
            }
            _ = mqtt.send(turningOn ? .remotePowerOn : .remotePowerOff, to: device.deviceID)
        }
    }

    private func deviceHeader(_ device: DeviceProfile, vehicle: VehicleState) -> some View {
        VStack(spacing: 4) {
            HStack {
                Button { showingDevices = true } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                VStack(spacing: 3) {
                    Text("JOURNEY")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .tracking(5)
                    Text(device.name).font(.headline)
                    Label(
                        vehicle.online ? (vehicle.cloudConnected && !mqtt.bluetoothStatus.contains("متصل") ? (vehicle.internetRoute == "CELLULAR" ? "ONLINE • 4G" : "ONLINE • Wi-Fi") : device.deviceID) : "غير متصل",
                        systemImage: vehicle.cloudConnected ? "cloud.fill" : "location.fill"
                    )
                        .font(.caption)
                        .foregroundStyle(vehicle.cloudConnected ? .green.opacity(0.82) : .white.opacity(0.52))
                }
                .fixedSize(horizontal: true, vertical: false)
                Spacer()
                connectionSettingsBar(vehicle)
            }
        }
    }

    // The connectivity display is also the settings entry point: no separate
    // gear icon is needed in the header.
    private func connectionSettingsBar(_ state: VehicleState) -> some View {
        Button { showingMQTTSettings = true } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: state.cloudConnected ? (state.internetRoute == "CELLULAR" ? "cellularbars" : "wifi") : "cellularbars")
                    Text(state.cloudConnected ? (state.internetRoute == "CELLULAR" ? "4G" : "NET") : (state.cellularNetwork == "غير متاح" ? "—" : state.cellularNetwork.uppercased()))
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(state.cloudConnected ? .green : networkColor(for: state.cellularSignalDBm))
                bluetoothDotIndicator(rssi: state.bluetoothRSSI)
            }
            .frame(width: 58, height: 58)
            .background(.black.opacity(0.66), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("إعدادات اتصال ESP")
    }

    // السطر العلوي هو الشبكة (4G/3G)، والنقاط الأربع تحته هي قوة BLE بين
    // الهاتف وESP — مثل الترتيب المتفق عليه في مؤشر iPhone.
    private func bluetoothDotIndicator(rssi: Int) -> some View {
        let count: Int = rssi >= -65 ? 4 : rssi >= -80 ? 3 : rssi >= -95 ? 2 : rssi >= -105 ? 1 : 0
        return HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < count ? Color.cyan : Color.white.opacity(0.20))
                    .frame(width: index == 0 ? 5 : 4, height: index == 0 ? 5 : 4)
            }
        }
    }

    private func cellularIndicator(_ state: VehicleState) -> some View {
        connectionChip(
            Label(state.cellularNetwork == "غير متاح" ? "—" : state.cellularNetwork.uppercased(), systemImage: "cellularbars")
            .foregroundStyle(networkColor(for: state.cellularSignalDBm))
        )
    }

    private func bluetoothIndicator(_ state: VehicleState) -> some View {
        connectionChip(
            BluetoothSignalIndicator(rssi: state.bluetoothRSSI)
        )
    }

    private func connectionChip<Content: View>(_ content: Content) -> some View {
        content
            .font(.caption2.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.07), in: Capsule())
    }

    private func networkColor(for rssi: Int) -> Color {
        if rssi <= -100 { return .gray }
        if rssi >= -65 { return .green }
        if rssi >= -80 { return .cyan }
        if rssi >= -95 { return .orange }
        return .red
    }

    private func statusStrip(_ state: VehicleState) -> some View {
        HStack(spacing: 8) {
            statusPill(state.simulatedLocked ? "مقفلة" : "مفتوحة", icon: state.simulatedLocked ? "lock.fill" : "lock.open.fill", active: !state.simulatedLocked)
            statusPill(state.simulatedEngineRunning ? "تعمل" : "متوقفة", icon: "engine.combustion.fill", active: state.simulatedEngineRunning)
            statusPill(state.gpsValid ? "GPS متصل" : "GPS غير متاح", icon: "location.fill", active: state.gpsValid)
        }
    }

    private var keylessEntryCard: some View {
        Button { showingKeylessEntry = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.radiowaves.forward")
                    .font(.title3.bold())
                    .foregroundStyle(.cyan)
                    .frame(width: 42, height: 42)
                    .background(.cyan.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(appText("الدخول الذكي", "Keyless"))
                        .font(.subheadline.bold())
                    Text("فتح عند الاقتراب وقفل عند الابتعاد — BLE")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.50))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .glassCard(padding: 13)
    }

    private func systemHealthCard(device: DeviceProfile, state: VehicleState) -> some View {
        let age = mqtt.stateAge(for: device.deviceID)
        let updateText: String
        if let age {
            updateText = age < 60 ? "الآن" : "قبل \(Int(age / 60)) د"
        } else {
            updateText = state.online ? "بانتظار قراءة" : "غير متصل"
        }

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("سلامة ومتابعة", systemImage: "shield.checkered")
                    .font(.headline)
                Spacer()
                Label("الإنذار جاهز", systemImage: "bell.badge.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                healthMetric("البطارية", value: String(format: "%.1f V", state.batteryVoltage), icon: "battery.75percent", tint: state.batteryVoltage >= 12 ? .green : .orange)
                healthMetric("آخر تحديث", value: updateText, icon: "clock.arrow.circlepath", tint: state.online ? .cyan : .orange)
            }
            if let last = mqtt.commandHistory.first {
                Label(last.title, systemImage: last.icon)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("لا توجد أوامر بعد", systemImage: "list.bullet.rectangle")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.50))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard(padding: 15)
    }

    private func ownerManagementCard(device: DeviceProfile, state: VehicleState) -> some View {
        let isAdmin = !state.ownerAdminPhone.isEmpty && state.ownerAdminPhone == AppConfig.phoneID
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("أجهزة المالك", systemImage: "person.2.badge.gearshape")
                    .font(.headline)
                Spacer()
                Text("\(state.authorizedPhoneCount) / 10")
                    .font(.caption.bold()).foregroundStyle(.cyan)
            }
            if !state.ownerStateKnown {
                Text("جاري التحقق من المدير المحفوظ في ESP…").font(.caption).foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
            } else if !state.trustedPhoneConfigured {
                Text("لا يوجد مالك مسجّل. سجّل هذا الآيفون كمدير.").font(.caption).foregroundStyle(.orange)
                Button("تسجيل هذا الآيفون كمدير", systemImage: "person.badge.key.fill") { secureOwnerAction(.ownerRegister, to: device.deviceID) }
                    .buttonStyle(.borderedProminent)
            } else if isAdmin {
                Text("هذا الآيفون هو المدير. الأجهزة الجديدة تحتاج موافقتك.").font(.caption).foregroundStyle(.secondary)
                if !state.pendingOwnerPhone.isEmpty {
                    Text("طلب جديد: \(state.pendingOwnerPhone.prefix(8))…").font(.caption).foregroundStyle(.orange)
                    HStack {
                        Button("موافقة") { secureOwnerAction(.ownerApprove, to: device.deviceID, target: state.pendingOwnerPhone) }.buttonStyle(.borderedProminent)
                        Button("رفض", role: .destructive) { secureOwnerAction(.ownerReject, to: device.deviceID, target: state.pendingOwnerPhone) }.buttonStyle(.bordered)
                    }
                }
                Button("مسح كل الأجهزة الأخرى", role: .destructive) { secureOwnerAction(.ownerClear, to: device.deviceID) }
                    .font(.caption)
            } else {
                Text("الآيفون الإداري يوافق على ربط هذا الجهاز قبل تفعيل الأوامر.").font(.caption).foregroundStyle(.secondary)
                Button("إرسال طلب ربط", systemImage: "person.badge.plus") { secureOwnerAction(.ownerRequest, to: device.deviceID) }
                    .buttonStyle(.bordered)
            }
        }
        .glassCard(padding: 15)
    }

    private func secureOwnerAction(_ action: BenchAction, to deviceID: String, target: String? = nil) {
        // The first administrator is a local, physical setup operation.  On
        // some sideloaded iOS builds the biometric prompt completes visually
        // but does not resume this Task, leaving the ESP with 0/10 owners even
        // though BLE is connected.  Bootstrap exactly the first owner without
        // that prompt; all later owner approvals/removals retain Face ID.
        if action == .ownerRegister {
            _ = mqtt.sendESPCommand(VehicleCommand(action: action, ownerTarget: target), to: deviceID)
            return
        }
        Task {
            guard await faceID.authenticate(reason: "تأكيد إدارة أجهزة مالك JOURNEY") else {
                faceIDError = faceID.lastError
                return
            }
            _ = mqtt.sendESPCommand(VehicleCommand(action: action, ownerTarget: target), to: deviceID)
        }
    }

    private func healthMetric(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.white.opacity(0.48))
                Text(value).font(.subheadline.bold())
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func statusPill(_ title: String, icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .foregroundStyle(active ? .cyan : .white.opacity(0.65))
            .background(active ? .cyan.opacity(0.13) : .white.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(active ? .cyan.opacity(0.30) : .white.opacity(0.07)))
    }

    private func mainControls(_ device: DeviceProfile, state: VehicleState) -> some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                largeControl("قفل", subtitle: "Lock", icon: "lock.fill", tint: .blue, statusActive: mqtt.isButtonActive("lock", for: device.deviceID), feedbackKey: "lock") { mqtt.send(.lock, to: device.deviceID) }
                largeControl("فتح", subtitle: "Unlock", icon: "lock.open.fill", tint: .green, statusActive: mqtt.isButtonActive("unlock", for: device.deviceID), feedbackKey: "unlock") { mqtt.send(.unlock, to: device.deviceID) }
                largeControl("تشغيل", subtitle: "Remote start", icon: "power", tint: .orange, statusActive: mqtt.isButtonActive("start", for: device.deviceID), feedbackKey: "start") { confirmStart = true }
                largeControl("إنذار", subtitle: "Alarm", icon: "bell.and.waves.left.and.right.fill", tint: .red, statusActive: mqtt.isButtonActive("alarm", for: device.deviceID), feedbackKey: "alarm") { mqtt.send(.horn, to: device.deviceID) }
            }
            // زر الطاقة تحت الأزرار وبعرض صف كامل، مثل حجم زرين متجاورين.
            largeControl(
                state.remotePowered ? "إطفاء طاقة الريموت" : "تشغيل طاقة الريموت",
                subtitle: state.remotePowered ? "مشتغل الآن • اضغط للإطفاء" : "طافي • Face ID",
                icon: state.remotePowered ? "key.fill" : "key",
                tint: state.remotePowered ? .green : .orange,
                status: state.remotePowered ? "مشتغل" : "طافي",
                statusActive: state.remotePowered,
                feedbackKey: "remotePower"
            ) { authenticateRemotePower(device, state: state) }
        }
        // Vehicle controls stay tappable while offline. A tap queues the command
        // and starts an immediate BLE reconnect; the ESP confirmation drives feedback.
        .opacity(1.0)
    }

    private func largeControl(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        status: String? = nil,
        statusActive: Bool = false,
        feedbackKey: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.prepare()
            impact.impactOccurred()
            if let feedbackKey {
                pressedControlToken = feedbackKey
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    if pressedControlToken == feedbackKey { pressedControlToken = nil }
                }
            }
            action()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(statusActive ? .green : .white.opacity(0.50))
                }
                Spacer(minLength: 0)
                if let status {
                    Text(status)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(statusActive ? .green : .white.opacity(0.55))
                        .background(statusActive ? .green.opacity(0.14) : .white.opacity(0.07), in: Capsule())
                }
            }
            .foregroundStyle((statusActive || (feedbackKey != nil && pressedControlToken == feedbackKey)) ? .green : .cyan)
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(((statusActive || (feedbackKey != nil && pressedControlToken == feedbackKey)) ? Color.green : Color.cyan).opacity((statusActive || (feedbackKey != nil && pressedControlToken == feedbackKey)) ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 18))
            .scaleEffect(feedbackKey != nil && pressedControlToken == feedbackKey ? 0.975 : 1.0)
            .animation(.easeOut(duration: 0.12), value: pressedControlToken)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(((statusActive || (feedbackKey != nil && pressedControlToken == feedbackKey)) ? Color.green : Color.cyan).opacity(0.55)))
        }
        .buttonStyle(.plain)
    }

    private func vehicleStatusText(_ state: VehicleState) -> String {
        if !state.online { return "ESP غير متصل" }
        if state.obdConnected && state.canAwake { return state.rpm > 0 ? "OBD مباشر • المحرك شغال" : "OBD مباشر • IGN/ACC" }
        if state.obdConnected { return "KONNWEI متصلة • CAN نايم" }
        return "بانتظار OBD"
    }

    private func telemetryCard(_ state: VehicleState) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(appText("بيانات السيارة", "Vehicle data")).font(.headline)
                Spacer()
                Text(vehicleStatusText(state)).font(.caption).foregroundStyle(.cyan.opacity(0.75))
            }
            Divider().overlay(.white.opacity(0.08))
            HStack {
                metric("RPM", value: "\(state.rpm)")
                metric(appText("السرعة", "Speed"), value: appSpeedUnit == "mph" ? "\(Int((Double(state.speedKph) * 0.621371).rounded())) mph" : "\(state.speedKph) km/h")
                metric(appText("الحرارة", "Temperature"), value: state.obdConnected ? (appTemperatureUnit == "f" ? "\(Int((Double(state.coolantC) * 9.0 / 5.0 + 32.0).rounded()))°F" : "\(state.coolantC)°C") : "—")
            }
            HStack {
                metric("فولت البطارية", value: state.batteryVoltage > 0 ? String(format: "%.2f V", state.batteryVoltage) : "—")
                metric("بنزين", value: state.obdConnected && state.fuelLevelValid ? "\(state.fuelLevelPercent)%" : "—")
                metric("OBD رد/ث", value: state.obdConnected ? "\(state.obdResponseRate)" : "—")
            }
            HStack {
                Label(state.gpsValid ? "GPS متصل" : "بانتظار GPS", systemImage: "location.fill")
                Spacer()
                Label(state.obdConnected ? "OBD متصل" : "OBD غير متصل", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.47))
                Label("السرعة وRPM والحرارة والبنزين من OBD؛ حالة الباب واللايت والإشارات تحتاج فحص BCM مخصص", systemImage: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(.cyan)
        }
        .glassCard(padding: 16)
    }

    private func aiAssistantCard(_ state: VehicleState) -> some View {
        let insights = AIAnalysisService.analyze(state)

        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appText("المساعد الذكي", "AI Assistant")).font(.headline)
                    Text("تحليل وشرح فقط — لا يتحكم بالمخارج ولا يمسح الأعطال")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                Text("READ ONLY")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            ForEach(insights.prefix(3)) { insight in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: insight.severity.symbol)
                            .foregroundStyle(aiColor(insight.severity))
                        Text(insight.title).font(.subheadline.bold())
                        Spacer()
                        Text(insight.severity.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(aiColor(insight.severity))
                    }
                    Text(insight.explanation)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                    Label(insight.nextStep, systemImage: "wrench.and.screwdriver.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .padding(12)
                .background(aiColor(insight.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .glassCard(padding: 16)
    }

    private func aiColor(_ severity: AIInsight.Severity) -> Color {
        switch severity {
        case .info: return .cyan
        case .attention: return .orange
        case .critical: return .red
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "car.side.lock")
                .font(.system(size: 58))
                .foregroundStyle(.cyan)
            Text(appText("أضف أول جهاز", "Add your first device")).font(.title2.bold())
            Text("ابحث عن البورد القريب بالبلوتوث حتى يظهر هنا.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("فتح البحث") { showingDevices = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .glassCard()
    }
}

private struct JourneyAppInfoView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.05, blue: 0.10), Color(red: 0.04, green: 0.11, blue: 0.17), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "car.side.and.exclamationmark")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .padding(18)
                        .background(.cyan.opacity(0.10), in: Circle())

                    VStack(spacing: 7) {
                        Text("JOURNEY")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .tracking(5)
                        Text("نظام التحكم والتشخيص الذكي للسيارة")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        Label("تصميم وتطوير", systemImage: "paintbrush.pointed.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                        Text("مهند الربيعي")
                            .font(.title3.bold())
                        Text("الريموت، NFC، OBD، التعقّب والتحليل الذكي ضمن نظام واحد.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(padding: 18)

                    VStack(spacing: 10) {
                        contactLink("البريد الإلكتروني", value: "mohaned_baqi@yahoo.com", icon: "envelope.fill", url: "mailto:mohaned_baqi@yahoo.com")
                        contactLink("اتصال", value: "07811119127", icon: "phone.fill", url: "tel:07811119127")
                        contactLink("WhatsApp", value: "07811119127", icon: "message.fill", url: "https://wa.me/9647811119127")
                        contactLink("Instagram", value: "@h0k38", icon: "camera.fill", url: "https://instagram.com/h0k38")
                    }
                    .glassCard(padding: 12)

                    Text("© 2026 JOURNEY • Designed by Mohaned Al‑Rubaie")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                }
                .padding()
                .padding(.top, 88)
            }
        }
    }

    private func contactLink(_ title: String, value: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.cyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.white.opacity(0.52))
                    Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "arrow.up.left.square").foregroundStyle(.white.opacity(0.42))
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HUDControlView: View {
    private enum DisplayMode: String, CaseIterable, Identifiable {
        case automatic = "تلقائي"
        case speed = "سرعة"
        case temperature = "حرارة"
        case rpm = "RPM"
        case gear = "كير"

        var id: String { rawValue }
    }

    let vehicle: VehicleState

    @AppStorage("hud.isEnabled") private var isEnabled = true
    @AppStorage("hud.mode") private var storedMode = DisplayMode.automatic.rawValue
    @AppStorage("hud.brightness") private var brightness = 5.0
    @AppStorage("hud.temperatureAlert") private var temperatureAlert = 105
    @AppStorage("hud.rpmAlert") private var rpmAlert = 4000
    @AppStorage("hud.useLiveData") private var useLiveData = true
    @AppStorage("journey.settings.speedUnit") private var speedUnit = "kmh"
    @AppStorage("journey.settings.temperatureUnit") private var temperatureUnit = "c"

    @State private var testSpeed = 48
    @State private var testTemperature = 91
    @State private var testRPM = 1850
    @State private var testGear = "D"

    private var selectedMode: DisplayMode {
        DisplayMode(rawValue: storedMode) ?? .automatic
    }

    private var speed: Int {
        let kph = useLiveData ? vehicle.speedKph : testSpeed
        return speedUnit == "mph" ? Int((Double(kph) * 0.621371).rounded()) : kph
    }

    private var temperature: Int {
        let c = useLiveData && vehicle.coolantC > 0 ? vehicle.coolantC : testTemperature
        return temperatureUnit == "f" ? Int((Double(c) * 9.0 / 5.0 + 32.0).rounded()) : c
    }

    private var rpm: Int {
        useLiveData ? vehicle.rpm : testRPM
    }

    private var effectiveMode: DisplayMode {
        guard selectedMode == .automatic else { return selectedMode }
        if temperature >= temperatureAlert { return .temperature }
        if rpm >= rpmAlert { return .rpm }
        if speed > 0 { return .speed }
        return .temperature
    }

    private var displayValue: String {
        guard isEnabled else { return "----" }
        switch effectiveMode {
        case .automatic:
            return "AUTO"
        case .speed:
            return String(format: "%4d", min(max(speed, 0), 9999))
        case .temperature:
            return String(format: "%3d%@", min(max(temperature, 0), 999), temperatureUnit == "f" ? "F" : "C")
        case .rpm:
            return String(format: "%4d", min(max(rpm, 0), 9999))
        case .gear:
            return "  \(testGear) "
        }
    }

    private var displayCaption: String {
        switch effectiveMode {
        case .automatic: return "تلقائي"
        case .speed: return speedUnit == "mph" ? "السرعة mph" : "السرعة km/h"
        case .temperature: return temperatureUnit == "f" ? "حرارة ماء المحرك °F" : "حرارة ماء المحرك °C"
        case .rpm: return "دورات المحرك RPM"
        case .gear: return "نمرة الكير"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.04, blue: 0.08), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    displayPreview
                    powerAndBrightness
                    modeSelector
                    automaticRules
                    testControls
                    connectionNote
                }
                .padding()
            }
        }
        .tint(.red)
    }

    private var displayPreview: some View {
        VStack(spacing: 12) {
            HStack {
                Label("TM1637 • 4 Digit", systemImage: "display")
                    .font(.subheadline.bold())
                Spacer()
                Circle()
                    .fill(isEnabled ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(isEnabled ? "تعمل" : "مطفيّة")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(displayValue)
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(isEnabled ? Color.red : Color.red.opacity(0.18))
                .shadow(color: isEnabled ? .red.opacity(0.85) : .clear, radius: 13)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(.black, in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.red.opacity(isEnabled ? 0.32 : 0.10), lineWidth: 1)
                )

            Text(displayCaption)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .glassCard(padding: 15)
    }

    private var powerAndBrightness: some View {
        VStack(spacing: 14) {
            Toggle("تشغيل شاشة الـHUD", isOn: $isEnabled)
                .font(.subheadline.bold())

            HStack {
                Label("السطوع", systemImage: "sun.max.fill")
                    .font(.subheadline)
                Slider(value: $brightness, in: 0...7, step: 1)
                Text("\(Int(brightness))")
                    .font(.subheadline.monospacedDigit().bold())
                    .frame(width: 22)
            }
        }
        .glassCard(padding: 15)
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("المعلومة المعروضة").font(.headline)
            Picker("نوع العرض", selection: $storedMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard(padding: 15)
    }

    private var automaticRules: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("ترتيب الوضع التلقائي").font(.headline)
            ruleRow("السيارة واقفة", value: "حرارة")
            ruleRow("السيارة تتحرك", value: "سرعة")
            ruleRow("الحرارة عالية", value: "حرارة فوراً")
            ruleRow("RPM عالي", value: "RPM فوراً")
            Divider().overlay(.white.opacity(0.08))
            Stepper("تنبيه الحرارة: \(temperatureAlert)°C", value: $temperatureAlert, in: 90...125)
            Stepper("حد RPM: \(rpmAlert)", value: $rpmAlert, in: 2500...7000, step: 250)
        }
        .font(.subheadline)
        .glassCard(padding: 15)
    }

    private func ruleRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value).bold().foregroundStyle(.red)
        }
    }

    private var testControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle("استخدم بيانات السيارة", isOn: $useLiveData)
                .font(.headline)

            if useLiveData {
                Text(vehicle.obdConnected ? "يعرض قراءات OBD عبر Bluetooth الحالية." : "قطعة OBD غير متصلة حالياً.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.50))
            } else {
                Stepper("سرعة التجربة: \(testSpeed) km/h", value: $testSpeed, in: 0...240)
                Stepper("حرارة التجربة: \(testTemperature)°C", value: $testTemperature, in: 20...130)
                Stepper("RPM التجريبي: \(testRPM)", value: $testRPM, in: 0...8000, step: 250)
                Picker("نمرة الكير", selection: $testGear) {
                    ForEach(["P", "R", "N", "D", "1", "2", "3", "4", "5", "6"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .font(.subheadline)
        .glassCard(padding: 15)
    }

    private var connectionNote: some View {
        Label(
            "الصفحة جاهزة للمحاكاة. عند ربط كود ESP تُرسل له: وضع العرض، السطوع، الحدود، والقراءة الحالية عبر BLE.",
            systemImage: "antenna.radiowaves.left.and.right"
        )
        .font(.caption)
        .foregroundStyle(.white.opacity(0.52))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }
}

private extension View {
    func glassCard(padding: CGFloat = 0) -> some View {
        self
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.42), .cyan.opacity(0.12), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
    }
}

private struct ESPStatusView: View {
    @EnvironmentObject private var mqtt: MQTTService
    @AppStorage("journey.settings.speedUnit") private var speedUnit = "kmh"
    let vehicle: VehicleState
    let bluetoothStatus: String
    let deviceID: String?
    @State private var pulseMs = 450.0
    @State private var wakeDelayMs = 1000.0
    @State private var powerOffDelayMs = 2000.0
    @State private var hudBrightness = 5.0
    @State private var showingFirmwarePicker = false
    @State private var updateStatus = ""
    @State private var isUpdating = false
    @State private var firmwareURL = ""
    @State private var maintenanceMode = false
    @State private var powerSaveMode = 0
    @State private var powerSaveIdleMinutes = 30.0

    var body: some View {
        List {
            Section("الاتصال المباشر") {
                Label(bluetoothStatus, systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(bluetoothStatus.hasPrefix("BLE متصل") ? .green : .orange)
                statusRow("حالة ESP", vehicle.online ? "متصل" : "بانتظار الاتصال")
                statusRow("وقت التشغيل", "\(vehicle.uptimeSeconds) ثانية")
                statusRow("طاقة الريموت", vehicle.remotePowered ? "مشتغلة" : "مطفأة")
                statusRow("أجهزة المالك", vehicle.ownerStateKnown ? "\(vehicle.authorizedPhoneCount) / 10 مسجّل" : "بانتظار ESP")
            }
            Section("OBD عبر BLE") {
                statusRow("قطعة OBD", vehicle.obdConnected ? "متصلة" : "بانتظار الاتصال")
                statusRow("السرعة", speedUnit == "mph" ? "\(Int((Double(vehicle.speedKph) * 0.621371).rounded())) mph" : "\(vehicle.speedKph) km/h")
                statusRow("الردود/ث", "\(vehicle.obdResponseRate)")
                statusRow("آخر حدث", vehicle.lastEvent)
            }
            Section("إعدادات محفوظة على ESP") {
                settingSlider("نبضة زر الريموت", value: $pulseMs, range: 100...2000, suffix: "ms")
                settingSlider("انتظار تشغيل الريموت", value: $wakeDelayMs, range: 100...5000, suffix: "ms")
                settingSlider("فصل طاقة الريموت", value: $powerOffDelayMs, range: 200...10000, suffix: "ms")
                HStack {
                    Text("سطوع شاشة HUD")
                    Spacer()
                    Stepper("\(Int(hudBrightness))", value: $hudBrightness, in: 0...7)
                        .labelsHidden()
                    Text("\(Int(hudBrightness))")
                        .foregroundStyle(.secondary)
                }
                Button("حفظ الإعدادات على ESP", systemImage: "square.and.arrow.down") { saveSettings() }
                    .disabled(deviceID == nil)
            }
            Section("الحماية والطاقة") {
                Toggle("وضع الصيانة", isOn: $maintenanceMode)
                    .onChange(of: maintenanceMode) { enabled in setMaintenance(enabled) }
                Picker("توفير الطاقة", selection: $powerSaveMode) {
                    Text("إلغاء").tag(0)
                    Text("يدوي").tag(1)
                    Text("تلقائي").tag(2)
                }
                .pickerStyle(.segmented)
                if powerSaveMode == 2 {
                    settingSlider("بدء التوفير بعد", value: $powerSaveIdleMinutes, range: 1...720, suffix: "دقيقة")
                }
                Button("حفظ وضع الطاقة", systemImage: "battery.75percent") { savePowerMode() }
                    .disabled(deviceID == nil)
                Button("إضافة بطاقة NFC الآن", systemImage: "wave.3.right.circle.fill") { send(.nfcEnroll) }
                    .disabled(deviceID == nil)
                Button("حذف بطاقة NFC", systemImage: "trash") { send(.nfcForget) }
                    .disabled(deviceID == nil)
            }
            Section("تحديث Firmware") {
                Text("للتحديث المحلي: اتصل من الآيفون بشبكة JOURNEY-ESP الظاهرة في Serial Monitor، ثم اختر ملف firmware.bin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(isUpdating ? "جاري رفع التحديث…" : "اختيار ملف firmware.bin", systemImage: "arrow.up.doc") {
                    showingFirmwarePicker = true
                }
                .disabled(isUpdating)
                if !updateStatus.isEmpty {
                    Text(updateStatus).font(.footnote).foregroundStyle(.secondary)
                }
                TextField("رابط HTTPS لملف firmware.bin", text: $firmwareURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("تحديث عبر 4G من الرابط", systemImage: "antenna.radiowaves.left.and.right") {
                    updateThrough4G()
                }
                .disabled(deviceID == nil || !firmwareURL.lowercased().hasPrefix("https://"))
                Text("رابط التحديث يجب أن ينتهي بملف firmware.bin متاح للتحميل المباشر. ESP ينزله عبر شريحته ثم يعيد التشغيل.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("الإعدادات تحفظ داخل ESP، لذلك تبقى بعد فصل الكهرباء ولا تحتاج كمبيوتر.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadSettings() }
        .fileImporter(isPresented: $showingFirmwarePicker, allowedContentTypes: [.data]) { result in
            if case .success(let file) = result { uploadFirmware(file) }
            if case .failure(let error) = result { updateStatus = error.localizedDescription }
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) \(suffix)").foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: 50)
        }
    }

    private func loadSettings() {
        pulseMs = Double(vehicle.remotePulseMs)
        wakeDelayMs = Double(vehicle.remoteWakeDelayMs)
        powerOffDelayMs = Double(vehicle.remotePowerOffDelayMs)
        hudBrightness = Double(vehicle.hudBrightness)
        maintenanceMode = vehicle.maintenanceMode
        powerSaveMode = vehicle.powerSaveMode
        powerSaveIdleMinutes = Double(vehicle.powerSaveIdleMinutes)
    }

    private func saveSettings() {
        guard let deviceID else { return }
        let settings = ESPRuntimeSettings(remotePulseMs: Int(pulseMs), remoteWakeDelayMs: Int(wakeDelayMs), remotePowerOffDelayMs: Int(powerOffDelayMs), hudBrightness: Int(hudBrightness))
        updateStatus = mqtt.sendESPSettings(settings, to: deviceID) ? "تم إرسال الإعدادات إلى ESP" : "تعذر إرسال الإعدادات"
    }

    private func uploadFirmware(_ file: URL) {
        isUpdating = true
        updateStatus = "جاري رفع الملف…"
        Task {
            let allowed = file.startAccessingSecurityScopedResource()
            defer { if allowed { file.stopAccessingSecurityScopedResource() } }
            do {
                var request = URLRequest(url: URL(string: "http://192.168.4.1/update")!)
                request.httpMethod = "POST"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 180
                let (_, response) = try await URLSession.shared.upload(for: request, fromFile: file)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                updateStatus = code == 200 ? "تم التحديث؛ ESP يعيد التشغيل الآن" : "فشل التحديث: HTTP \(code)"
            } catch {
                updateStatus = "فشل الرفع: \(error.localizedDescription)"
            }
            isUpdating = false
        }
    }

    private func updateThrough4G() {
        guard let deviceID else { return }
        updateStatus = mqtt.sendFirmwareURL(firmwareURL.trimmingCharacters(in: .whitespacesAndNewlines), to: deviceID)
            ? "تم إرسال رابط التحديث؛ ESP يبدأ التنزيل عبر 4G"
            : "تعذر إرسال رابط التحديث"
    }

    private func setMaintenance(_ enabled: Bool) {
        send(.maintenanceMode, maintenanceMode: enabled)
    }

    private func savePowerMode() {
        guard let deviceID else { return }
        let command = VehicleCommand(action: .powerSave, powerSave: PowerSaveSettings(mode: powerSaveMode, idleMinutes: Int(powerSaveIdleMinutes)))
        updateStatus = mqtt.sendESPCommand(command, to: deviceID) ? "تم حفظ وضع توفير الطاقة" : "تعذر حفظ وضع الطاقة"
    }

    private func send(_ action: BenchAction, maintenanceMode: Bool? = nil) {
        guard let deviceID else { return }
        let command = VehicleCommand(action: action, maintenanceMode: maintenanceMode)
        updateStatus = mqtt.sendESPCommand(command, to: deviceID) ? "تم إرسال الأمر إلى ESP" : "تعذر إرسال الأمر"
    }
}

private struct OBDStatusView: View {
    @EnvironmentObject private var mqtt: MQTTService
    let vehicle: VehicleState
    let deviceID: String?
    @StateObject private var faceID = FaceIDAuthenticator()
    @State private var adapterName = ""
    @State private var transport = "BLE"
    @State private var wifiPassword = ""
    @State private var wifiHost = "192.168.0.10"
    @State private var wifiPort = "35000"
    @State private var clearConfirmation = false
    @State private var statusMessage = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.05, blue: 0.10), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(
                        vehicle.obdConnected ? "OBD متصل" : "بانتظار قطعة OBD",
                        systemImage: vehicle.obdConnected ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(vehicle.obdConnected ? .green : .orange)

                    Text("ESP يرسل طلبات OBD القياسية للقراءة فقط عبر BLE أو Wi‑Fi؛ أوامر التحكم غير مستخدمة، ومسح الأخطاء لا يتم إلا بتأكيدك.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Group {
                        obdRow("الحالة", obdStatusArabic(vehicle.obdStatus))
                        obdRow("الردود بالثانية", "\(vehicle.obdResponseRate)")
                        obdRow("فحص PIDs", vehicle.obdStandardScanComplete ? "اكتمل: \(vehicle.obdSupportedPids) مدعوم" : "\(vehicle.obdScanProgress)% — \(vehicle.obdScannedPids)/\(vehicle.obdSupportedPids)")
                        obdRow("PID الحالي", vehicle.obdCurrentPid.isEmpty ? "—" : vehicle.obdCurrentPid)
                        obdRow("مجموع الردود", "\(vehicle.obdTotalResponses)")
                        obdRow("RPM", "\(vehicle.rpm)")
                        obdRow("السرعة", UserDefaults.standard.string(forKey: "journey.settings.speedUnit") == "mph" ? "\(Int((Double(vehicle.speedKph) * 0.621371).rounded())) mph" : "\(vehicle.speedKph) km/h")
                        obdRow("فولت البطارية", vehicle.batteryVoltage > 0 ? String(format: "%.2f V", vehicle.batteryVoltage) : "—")
                        obdRow("حالة السويتش / ACC", ignitionStateArabic(vehicle.ignitionState))
                        obdRow("حالة CAN", vehicle.canAwake ? "صاحي" : "نايم / بانتظار الاستيقاظ")
                        obdRow("آخر رد", vehicle.obdLastReply.isEmpty ? "—" : vehicle.obdLastReply)
                    }
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("اتصال OBD").font(.headline)
                        Picker("نوع الاتصال", selection: $transport) {
                            Text("BLE").tag("BLE")
                            Text("Wi‑Fi").tag("WIFI")
                        }
                        .pickerStyle(.segmented)
                        Text(transport == "BLE" ? "القطعة الأساسية KONNWEI محفوظة داخل ESP. البحث العام يعمل فقط عند ضغط الزر لتغيير القطعة." : "ESP يبحث عن شبكات Wi‑Fi القريبة؛ اختر شبكة قطعة OBD ثم أدخل الباسورد إذا موجود.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(transport == "BLE" ? "بحث ESP عن قطع BLE" : "بحث ESP عن شبكات Wi‑Fi", systemImage: "magnifyingglass") { searchAdapters() }
                            .buttonStyle(.bordered)
                            .disabled(deviceID == nil)
                        TextField(transport == "BLE" ? "اسم القطعة كما يظهر بالبلوتوث، مثال V-LINK" : "اسم شبكة Wi‑Fi لقطعة OBD", text: $adapterName)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        if transport == "WIFI" {
                            SecureField("باسورد الشبكة (إن وجد)", text: $wifiPassword).textFieldStyle(.roundedBorder)
                            TextField("عنوان قطعة OBD", text: $wifiHost).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                            TextField("المنفذ", text: $wifiPort).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        }
                        Button("اختيار وحفظ واتصال", systemImage: "checkmark.circle.fill") { saveAdapter() }
                            .buttonStyle(.borderedProminent)
                            .disabled(deviceID == nil || adapterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        let discovered = transport == "BLE" ? vehicle.obdDiscoveredAdapters : vehicle.obdDiscoveredWifiNetworks
                        if !discovered.isEmpty {
                            Text(transport == "BLE" ? "قطع ظهرت للـESP: \(discovered)" : "شبكات ظهرت للـESP: \(discovered)")
                                .font(.caption).foregroundStyle(.cyan)
                            ForEach(discovered.components(separatedBy: " | ").filter { !$0.isEmpty }, id: \.self) { name in
                                Button { adapterName = name } label: {
                                    HStack { Image(systemName: adapterName == name ? "checkmark.circle.fill" : "circle"); Text(name); Spacer() }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(adapterName == name ? .cyan : .primary)
                            }
                        }
                        if !vehicle.obdAdapterName.isEmpty { obdRow("المحفوظة", vehicle.obdAdapterName) }
                        Button("الرجوع إلى KONNWEI الأساسية", role: .destructive) { forgetAdapter() }
                            .disabled(deviceID == nil)
                    }
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("الأخطاء والتحليل").font(.headline)
                        obdRow("الأكواد", vehicle.diagnosticCodes.isEmpty ? "لا توجد أكواد" : vehicle.diagnosticCodes.joined(separator: ", "))
                        Text("فحص الأكواد يدوي فقط؛ لا يوجد فحص دوري بالخلفية.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("فحص الأخطاء الآن", systemImage: "stethoscope") { scanTroubleCodes() }
                            .buttonStyle(.bordered)
                            .disabled(deviceID == nil)
                        Toggle("أفهم أن المسح قد يطفي اللمبة مؤقتاً", isOn: $clearConfirmation)
                            .font(.caption)
                        Button(vehicle.obdClearInProgress ? "جاري مسح الأخطاء…" : "مسح أخطاء السيارة", systemImage: "trash.slash") {
                            clearTroubleCodes()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(deviceID == nil || vehicle.simulatedEngineRunning || !clearConfirmation || vehicle.obdClearInProgress)
                        if vehicle.simulatedEngineRunning {
                            Text("أطفئ المحرك أولاً؛ المسح مقفول أثناء التشغيل.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if !statusMessage.isEmpty { Text(statusMessage).font(.caption).foregroundStyle(.cyan) }
                    }
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    Label(
                        "OBD القياسي يعطي سرعة وRPM وحرارة؛ الأبواب واللايتات والإشارات ليست ضمن PIDs القياسية.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.cyan)
                }
                .padding()
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
        .tint(.cyan)
        .onAppear { adapterName = vehicle.obdAdapterName }
    }

    private func saveAdapter() {
        guard let deviceID else { return }
        let name = adapterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = VehicleCommand(action: .obdSelect, obdAdapter: OBDAdapterSelection(name: name, transport: transport, password: wifiPassword, host: wifiHost, port: Int(wifiPort) ?? 35000))
        statusMessage = mqtt.sendESPCommand(command, to: deviceID) ? "تم حفظ الاسم؛ ESP يبحث ويتصل به تلقائياً." : "تعذر إرسال الاختيار إلى ESP"
    }

    private func searchAdapters() {
        guard let deviceID else { return }
        let selection = OBDAdapterSelection(name: "", transport: transport)
        let command = VehicleCommand(action: .obdSearch, obdAdapter: selection)
        let sent = mqtt.sendESPCommand(command, to: deviceID)
        if sent {
            statusMessage = transport == "BLE"
                ? "أُرسل بحث BLE إلى ESP؛ انتظر 20 ثانية، وتظهر حتى الأجهزة بدون اسم."
                : "أُرسل بحث Wi‑Fi إلى ESP؛ البحث يبدأ فوراً وتظهر الشبكات المخفية أيضاً."
        } else {
            statusMessage = "تعذر إرسال طلب البحث إلى ESP"
        }
    }

    private func forgetAdapter() {
        guard let deviceID else { return }
        statusMessage = mqtt.sendESPCommand(VehicleCommand(action: .obdForget), to: deviceID) ? "تم الرجوع إلى KONNWEI الأساسية." : "تعذر الرجوع للقطعة الأساسية"
    }

    private func scanTroubleCodes() {
        guard let deviceID else { return }
        let command = VehicleCommand(action: .obdScanDTC)
        statusMessage = mqtt.sendESPCommand(command, to: deviceID) ? "بدأ فحص أخطاء OBD." : "تعذر إرسال طلب فحص الأخطاء"
    }

    private func clearTroubleCodes() {
        guard let deviceID, clearConfirmation, !vehicle.simulatedEngineRunning else { return }
        Task {
            guard await faceID.authenticate(reason: "تأكيد مسح أخطاء OBD لسيارة JOURNEY") else {
                statusMessage = faceID.lastError ?? "لم يتم تأكيد Face ID"
                return
            }
            let command = VehicleCommand(action: .obdClearDTC, obdClearConfirmed: true)
            statusMessage = mqtt.sendESPCommand(command, to: deviceID) ? "أُرسل طلب المسح؛ سيتم فحص الأكواد من جديد." : "تعذر إرسال أمر المسح"
        }
    }


    private func ignitionStateArabic(_ raw: String) -> String {
        switch raw {
        case "ENGINE_RUNNING": return "المحرك شغال"
        case "IGN_ON": return "IGN/ACC صاحي — المحرك طافي"
        case "OFF_OR_SLEEP": return "طافي / CAN نايم"
        default: return "غير معروف"
        }
    }

    private func obdStatusArabic(_ raw: String) -> String {
        switch raw {
        case "waiting_for_saved_adapter", "waiting": return "بانتظار القطعة الأساسية"
        case "connecting_saved_adapter", "connecting": return "جاري الاتصال بـ KONNWEI"
        case "initializing_elm327": return "تهيئة ELM327"
        case "connecting_ecu": return "الاتصال بكمبيوتر السيارة"
        case "reading_vin": return "قراءة رقم الشاصي VIN"
        case "scanning_supported_pids": return "فحص PIDs المدعومة"
        case "reading_standard_pids": return "قراءة بيانات السيارة"
        case "reading_dtc_stored": return "فحص الأخطاء المخزنة"
        case "reading_dtc_pending": return "فحص الأخطاء المعلقة"
        case "reading_dtc_permanent": return "فحص الأخطاء الدائمة"
        case "dtc_scan_complete": return "اكتمل فحص الأخطاء"
        case "adapter_searching": return "بحث يدوي عن قطع BLE"
        case "adapter_search_complete": return "اكتمل البحث اليدوي"
        case "adapter_not_found": return "لم يتم العثور على القطعة"
        case "obd_waiting_reply": return "بانتظار رد OBD"
        case "waiting_for_can": return "KONNWEI متصلة — بانتظار CAN"
        case "probing_can": return "فحص استيقاظ CAN"
        case "can_awake_reading_vin": return "CAN اشتغل — قراءة VIN"
        case "obd_live": return "متصل — قراءة مباشرة"
        case "dtc_scan_requested": return "بدء فحص الأخطاء"
        case "obd_adapter_no_response_reconnecting", "obd_no_response_reconnecting": return "انقطع رد القطعة — إعادة اتصال"
        case "ecu_handshake_invalid": return "رد ECU غير صالح"
        case "vin_invalid_no_advance": return "VIN غير صالح — توقف الفحص"
        case "default_adapter_restored": return "KONNWEI هي القطعة الأساسية"
        default: return raw.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func obdRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.subheadline, design: .monospaced)).multilineTextAlignment(.trailing)
        }
    }
}

// يبحث الآيفون عن أسماء أجهزة BLE فقط؛ لا يتصل بها ولا يقرأ السيارة. بعد أن
// يختار المالك الاسم، يرسله إلى ESP ليبقى هو قارئ OBD الدائم. لذلك يعمل البحث
// حتى مع نسخة ESP السابقة التي تدعم حفظ الاسم فقط.
private final class OBDAdapterScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published private(set) var adapters: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var status = ""
    private var central: CBCentralManager!
    private var pendingStart = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        adapters.removeAll()
        guard central.state == .poweredOn else {
            pendingStart = true
            status = "فعّل Bluetooth ثم أعد البحث"
            return
        }
        pendingStart = false
        status = "جاري مسح كل أجهزة BLE القريبة…"
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.stop() }
    }

    private func stop() {
        central.stopScan()
        isScanning = false
        status = adapters.isEmpty ? "لم يظهر أي جهاز BLE؛ تأكد من تفعيل Bluetooth ومن أن الجهاز القريب يعلن عن نفسه." : "ظهرت أجهزة BLE القريبة. اختر قطعة OBD ثم اضغط اختيار وحفظ واتصال."
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        if pendingStart { start() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = ((advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // لا نفلتر بالاسم: المستخدم يحتاج أن يرى كل أجهزة BLE ليتأكد أن
        // المسح حقيقي، وبعض القطع التجارية لا تضع OBD أو ELM في اسمها.
        let shown = name.isEmpty ? "بدون اسم [\(peripheral.identifier.uuidString)]" : name
        if !adapters.contains(shown) { adapters.append(shown) }
    }
}

private struct BluetoothSignalIndicator: View {
    let rssi: Int

    private var bars: Int {
        if rssi >= -65 { return 4 }
        if rssi >= -80 { return 3 }
        if rssi >= -95 { return 2 }
        if rssi >= -99 { return 1 }
        return 0
    }

    private var color: Color {
        switch bars {
        case 4: return .green
        case 3: return .cyan
        case 2: return .orange
        case 1: return .red
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bluetooth")
                .font(.caption.bold())
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index < bars ? color : .white.opacity(0.18))
                        .frame(width: 3, height: CGFloat(5 + index * 3))
                }
            }
            Text(bars == 0 ? "—" : "BLE")
                .font(.caption2.bold())
        }
        .foregroundStyle(color)
    }
}

private struct VehicleMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mqtt: MQTTService
    let vehicle: VehicleState
    let vehicleName: String
    let deviceID: String?
    @State private var region: MKCoordinateRegion
    @State private var locationName = "بانتظار GPS"

    init(vehicle: VehicleState, vehicleName: String, deviceID: String?) {
        self.vehicle = vehicle
        self.vehicleName = vehicleName
        self.deviceID = deviceID
        let coordinate = CLLocationCoordinate2D(
            latitude: vehicle.gpsValid ? vehicle.latitude : 30.5154,
            longitude: vehicle.gpsValid ? vehicle.longitude : 47.8213
        )
        _region = State(initialValue: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    private var points: [VehicleMapPoint] {
        guard vehicle.gpsValid else { return [] }
        return [VehicleMapPoint(
            coordinate: CLLocationCoordinate2D(latitude: vehicle.latitude, longitude: vehicle.longitude)
        )]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
            Map(coordinateRegion: $region, annotationItems: points) { point in
                MapAnnotation(coordinate: point.coordinate) {
                    VStack(spacing: 4) {
                        Image(systemName: "car.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.cyan, in: Circle())
                            .shadow(color: .cyan.opacity(0.45), radius: 10)
                        Text(vehicleName)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.75), in: Capsule())
                    }
                }
            }
                    .frame(height: 335)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                    Label(vehicle.gpsValid ? "الموقع الحي" : "بانتظار GPS", systemImage: vehicle.gpsValid ? "location.fill" : "location.slash.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(13)
                }

                HStack(spacing: 10) {
                    mapCommandButton("قفل", icon: "lock.fill", tint: .blue) { send(.lock) }
                    mapCommandButton("فتح", icon: "lock.open.fill", tint: .green) { send(.unlock) }
                }

                HStack(spacing: 8) {
                    mapStatus(vehicle.simulatedLocked ? "مقفلة" : "مفتوحة", icon: vehicle.simulatedLocked ? "lock.fill" : "lock.open.fill", active: !vehicle.simulatedLocked)
                    mapStatus(vehicle.simulatedEngineRunning ? "تعمل" : "متوقفة", icon: "engine.combustion.fill", active: vehicle.simulatedEngineRunning)
                    mapStatus(vehicle.gpsValid ? "GPS متصل" : "GPS بانتظار", icon: "location.fill", active: vehicle.gpsValid)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("حالة السيارة").font(.headline)
                        Spacer()
                        Circle().fill(vehicle.online ? .green : .orange).frame(width: 9, height: 9)
                    }
                    if vehicle.gpsValid {
                        Label(locationName, systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                        Text(String(format: "%.6f, %.6f", vehicle.latitude, vehicle.longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button {
                            let url = URL(string: "http://maps.apple.com/?ll=\(vehicle.latitude),\(vehicle.longitude)&q=JOURNEY")!
                            UIApplication.shared.open(url)
                        } label: {
                            Label("فتح في خرائط Apple", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("تظهر السيارة هنا تلقائياً عندما ينشر ESP إحداثيات GPS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(15)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
            }
            .padding()
            .padding(.top, 88)
        }
        .background(Color(red: 0.02, green: 0.05, blue: 0.10).ignoresSafeArea())
        .navigationTitle("الخريطة والتعقّب")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("تم") { dismiss() }
            }
        }
        .task(id: "\(vehicle.latitude),\(vehicle.longitude),\(vehicle.gpsValid)") {
            await resolveLocationName()
        }
    }

    @MainActor
    private func resolveLocationName() async {
        guard vehicle.gpsValid else {
            locationName = "بانتظار GPS"
            return
        }
        let location = CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = placemarks?.first else {
            locationName = "موقع السيارة الحالي"
            return
        }
        let parts = [mark.name, mark.subLocality, mark.locality].compactMap { $0 }.filter { !$0.isEmpty }
        locationName = parts.isEmpty ? "موقع السيارة الحالي" : Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: "، ")
    }

    private func send(_ command: BenchAction) {
        guard let deviceID else { return }
        mqtt.send(command, to: deviceID)
    }

    private func mapCommandButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(tint)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(tint.opacity(0.30)))
        }
        .buttonStyle(.plain)
        .disabled(deviceID == nil)
    }

    private func mapStatus(_ title: String, icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(active ? .cyan : .white.opacity(0.64))
            .background(active ? .cyan.opacity(0.13) : .white.opacity(0.055), in: Capsule())
    }
}

/// A live map preview replacing the old launcher and NFC management cards.
/// It uses the actual GPS coordinates as soon as the ESP publishes them, and
/// keeps a Basra Corniche preview while the receiver is waiting for a fix.
private struct VehicleMapEntryCard: View {
    let vehicle: VehicleState
    let openMap: () -> Void
    @State private var region: MKCoordinateRegion
    @State private var locationName = "بانتظار GPS"

    init(vehicle: VehicleState, openMap: @escaping () -> Void) {
        self.vehicle = vehicle
        self.openMap = openMap
        let coordinate = CLLocationCoordinate2D(
            latitude: vehicle.gpsValid ? vehicle.latitude : 30.5154,
            longitude: vehicle.gpsValid ? vehicle.longitude : 47.8213
        )
        _region = State(initialValue: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        ))
    }

    private var points: [VehicleMapPoint] {
        guard vehicle.gpsValid else { return [] }
        return [VehicleMapPoint(
            coordinate: CLLocationCoordinate2D(latitude: vehicle.latitude, longitude: vehicle.longitude)
        )]
    }

    var body: some View {
        Button(action: openMap) {
            ZStack(alignment: .bottomLeading) {
                Map(coordinateRegion: $region, interactionModes: [], annotationItems: points) { point in
                    MapAnnotation(coordinate: point.coordinate) {
                        Image(systemName: "car.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.cyan, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 4)
                    }
                }
                .allowsHitTesting(false)
                .saturation(0.82)

                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.76)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 11) {
                    Image(systemName: vehicle.gpsValid ? "location.fill" : "map.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.cyan)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.48), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("الخريطة والتعقّب")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(vehicle.gpsValid ? locationName : "بانتظار موقع السيارة من GPS")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(14)
            }
            .frame(height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(.cyan.opacity(0.38), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("الخريطة والتعقّب")
        .task(id: "\(vehicle.latitude),\(vehicle.longitude),\(vehicle.gpsValid)") {
            await resolveLocationName()
        }
    }

    @MainActor
    private func resolveLocationName() async {
        guard vehicle.gpsValid else {
            locationName = "بانتظار GPS"
            return
        }
        let location = CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = placemarks?.first else {
            locationName = "موقع السيارة الحالي"
            return
        }
        let parts = [mark.name, mark.subLocality, mark.locality].compactMap { $0 }.filter { !$0.isEmpty }
        locationName = parts.isEmpty ? "موقع السيارة الحالي" : Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: "، ")
    }
}

private struct VehicleMapPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

private struct KeylessEntrySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mqtt: MQTTService
    let deviceID: String

    @AppStorage("journey.keyless.enabled") private var enabled = true
    @AppStorage("journey.keyless.unlockDistance") private var unlockDistance = 1.5
    @AppStorage("journey.keyless.lockDistance") private var lockDistance = 4.0
    @AppStorage("journey.keyless.unlockHold") private var unlockHold = 4.0
    @AppStorage("journey.keyless.lockDelay") private var lockDelay = 20.0
    @AppStorage("journey.keyless.keepRemotePowered") private var keepRemotePowered = true

    private var effectiveLockDistance: Double {
        max(lockDistance, unlockDistance + 1.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("تفعيل الدخول الذكي", isOn: $enabled)
                        .tint(.cyan)
                    Text("عند الاتصال الآمن بالـESP: يفتح عند الاقتراب ويقفل بعد الابتعاد.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("مفتاح الآيفون", systemImage: "iphone.radiowaves.left.and.right")
                }

                Section("مسافات تقريبية") {
                    settingSlider(title: "مسافة الفتح", value: $unlockDistance, range: 0.5...3.0, step: 0.5, tint: .green)
                    settingSlider(title: "مسافة القفل", value: $lockDistance, range: 2.0...8.0, step: 0.5, tint: .orange)
                    Text("القفل مضبوط على \(String(format: "%.1f", effectiveLockDistance)) م أو أكثر حتى لا يفتح ويقفل بسرعة.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("ثبات الإشارة") {
                    settingSlider(title: "تثبيت القرب قبل الفتح", value: $unlockHold, range: 2.0...8.0, step: 1.0, suffix: " ث", tint: .cyan)
                    settingSlider(title: "تأخير القفل بعد الابتعاد", value: $lockDelay, range: 10.0...45.0, step: 5.0, suffix: " ث", tint: .orange)
                }

                Section("ريموت السيارة الاحتياطي") {
                    Toggle("يبقى الريموت مفعّل أثناء وجود الآيفون", isOn: $keepRemotePowered)
                        .tint(.cyan)
                    Text("عند الاقتراب: ESP يشغّل 3.3V للريموت، ينتظر ثانية، ثم ينفذ الفتح. عند الابتعاد: يقفل أولاً، ينتظر ثانيتين، ثم يفصل تغذية الريموت.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Label("يبقى مفتاح السيارة موجوداً أثناء وقوفك داخلها، فلا ينفصل الريموت مباشرة بعد الفتح.", systemImage: "key.fill")
                        .font(.footnote)
                        .foregroundStyle(.cyan)
                }

                Section {
                    Label("المسافة تقديرية لأن BLE تقيس قوة الإشارة، وتتأثر بالجدران ومكان الهاتف. فعّلها بعد اختبارها حول السيارة.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("الدخول الذكي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ وإرسال") { save() }
                }
            }
            .onChange(of: unlockDistance) { value in
                if lockDistance < value + 1.0 { lockDistance = value + 1.0 }
            }
        }
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String = " م",
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text("\(String(format: suffix == " م" ? "%.1f" : "%.0f", value.wrappedValue))\(suffix)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(tint)
            }
            Slider(value: value, in: range, step: step)
                .tint(tint)
        }
        .padding(.vertical, 3)
    }

    private func save() {
        lockDistance = effectiveLockDistance
        let config = KeylessEntryConfig(
            enabled: enabled,
            unlockDistanceMeters: unlockDistance,
            lockDistanceMeters: effectiveLockDistance,
            unlockHoldSeconds: Int(unlockHold),
            lockDelaySeconds: Int(lockDelay),
            keepRemotePoweredWhilePresent: keepRemotePowered,
            remoteWakeDelaySeconds: 1,
            remotePowerOffDelaySeconds: 2
        )
        _ = mqtt.sendKeylessConfig(config, to: deviceID)
        dismiss()
    }
}

private struct MQTTSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mqtt: MQTTService
    @EnvironmentObject private var devices: DeviceStore

    @State private var host = ""
    @State private var port = "8883"
    @State private var username = ""
    @State private var password = ""
    @State private var errorText: String?
    @State private var wifiEnabled = false
    @State private var wifiSSID = ""
    @State private var wifiPassword = ""
    @State private var wifiMessage: String?
    @State private var cellularEnabled = false
    @State private var cellularAPN = "internet"
    @State private var cellularUsername = ""
    @State private var cellularPassword = ""
    @State private var cellularSimPin = ""
    @State private var hotspotEnabled = false
    @State private var hotspotSSID = "JOURNEY-4G"
    @State private var hotspotPassword = "Journey2017"
    @State private var cellularMessage: String?
    @State private var connectionPriority: [String] = ["CELLULAR", "WIFI", "BLE"]
    @State private var priorityMessage: String?

    @AppStorage("journey.settings.appearance") private var appearance = "dark"
    @AppStorage("journey.settings.textSize") private var textSize = "normal"
    @AppStorage("journey.settings.language") private var language = "ar"
    @AppStorage("journey.settings.speedUnit") private var speedUnit = "kmh"
    @AppStorage("journey.settings.temperatureUnit") private var temperatureUnit = "c"
    @AppStorage("journey.settings.notifyEngine") private var notifyEngine = true
    @AppStorage("journey.settings.notifyKeyless") private var notifyKeyless = true
    @AppStorage("journey.settings.notifyLocks") private var notifyLocks = true
    @AppStorage("journey.settings.notifyOBD") private var notifyOBD = false
    @AppStorage("journey.settings.developerMode") private var developerMode = false

    private func tr(_ ar: String, _ en: String) -> String { language == "en" ? en : ar }

    private var selectedDeviceID: String? { devices.selectedDevice?.deviceID }
    private var vehicle: VehicleState {
        guard let id = selectedDeviceID else { return VehicleState() }
        return mqtt.state(for: id)
    }
    private var wifiNetworks: [String] {
        vehicle.wifiDiscoveredNetworks
            .components(separatedBy: " | ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("المظهر", "Appearance"), selection: $appearance) {
                        Text(tr("داكن", "Dark")).tag("dark")
                        Text(tr("فاتح", "Light")).tag("light")
                        Text(tr("حسب النظام", "System")).tag("system")
                    }
                    Picker(tr("حجم الخط", "Text size"), selection: $textSize) {
                        Text(tr("صغير", "Small")).tag("small")
                        Text(tr("عادي", "Normal")).tag("normal")
                        Text(tr("كبير", "Large")).tag("large")
                        Text(tr("أكبر", "Extra large")).tag("xlarge")
                    }
                    Picker(tr("اللغة", "Language"), selection: $language) {
                        Text(tr("العربية", "Arabic")).tag("ar")
                        Text("English").tag("en")
                    }
                } header: {
                    Label(tr("المظهر واللغة", "Appearance & Language"), systemImage: "paintbrush.pointed.fill")
                }

                Section {
                    Picker(tr("وحدة السرعة", "Speed unit"), selection: $speedUnit) {
                        Text("km/h").tag("kmh")
                        Text("mph").tag("mph")
                    }
                    Picker(tr("درجة الحرارة", "Temperature"), selection: $temperatureUnit) {
                        Text("°C").tag("c")
                        Text("°F").tag("f")
                    }
                    Text(language == "en" ? "Battery voltage is read automatically by the ESP firmware; there is no fake local switch." : "فولت البطارية يُقرأ تلقائياً من Firmware الـESP؛ ماكو مفتاح محلي وهمي.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label(tr("السيارة والقراءات", "Vehicle & Readings"), systemImage: "car.fill")
                }

                Section {
                    Toggle(tr("تشغيل وإطفاء المحرك", "Engine start/stop"), isOn: $notifyEngine)
                    Toggle(tr("الاقتراب والابتعاد", "Approach/departure"), isOn: $notifyKeyless)
                    Toggle(tr("القفل والفتح", "Lock/unlock"), isOn: $notifyLocks)
                    Toggle(tr("حالة OBD", "OBD status"), isOn: $notifyOBD)
                    Label("مضافة حماية من إشعار إطفاء كاذب أثناء الحركة ومن تكرار إشعار الاقتراب.", systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } header: {
                    Label(tr("الإشعارات", "Notifications"), systemImage: "bell.badge.fill")
                }

                Section {
                    ForEach(Array(connectionPriority.enumerated()), id: \.element) { index, route in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 24, height: 24)
                                .background(.cyan.opacity(0.16), in: Circle())

                            Label(priorityTitle(route), systemImage: priorityIcon(route))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                movePriority(at: index, offset: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)

                            Button {
                                movePriority(at: index, offset: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == connectionPriority.count - 1)
                        }
                    }

                    Button {
                        saveConnectionPriority()
                    } label: {
                        Label("حفظ ترتيب الأولوية", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedDeviceID == nil)

                    if let priorityMessage {
                        Text(priorityMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("ارفع أو نزّل أي مسار. الأوامر العادية تتبع هذا التسلسل، بينما الدخول الذكي Keyless يبقى BLE أولاً حتى يظل سريع.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("أولوية الاتصال", systemImage: "arrow.up.arrow.down")
                }

                Section {
                    Toggle("تشغيل Wi-Fi بالـESP", isOn: $wifiEnabled)
                        .tint(.cyan)
                        .onChange(of: wifiEnabled) { _, enabled in
                            if !enabled { setWifiEnabled(false) }
                        }

                    HStack {
                        Label(
                            vehicle.wifiConnected ? "متصل: \(vehicle.wifiSSID)" : wifiStatusText(vehicle.wifiStatus),
                            systemImage: vehicle.wifiConnected ? "wifi" : "wifi.slash"
                        )
                        .foregroundStyle(vehicle.wifiConnected ? .green : .secondary)
                        Spacer()
                        if vehicle.wifiConnected {
                            Text("\(vehicle.wifiRSSI) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !vehicle.wifiIP.isEmpty {
                        LabeledContent("IP", value: vehicle.wifiIP)
                    }
                    LabeledContent("التحكم عن بُعد", value: vehicle.cloudConnected ? "ONLINE عبر الإنترنت" : "غير متصل بالسحابة")
                        .foregroundStyle(vehicle.cloudConnected ? .green : .secondary)

                    Button {
                        searchWifi()
                    } label: {
                        Label(vehicle.wifiStatus == "searching" ? "جاري البحث..." : "بحث عن الشبكات", systemImage: "magnifyingglass")
                    }
                    .disabled(vehicle.wifiStatus == "searching" || selectedDeviceID == nil)

                    if !wifiNetworks.isEmpty {
                        Picker("الشبكة", selection: $wifiSSID) {
                            Text("اختر شبكة").tag("")
                            ForEach(wifiNetworks, id: \.self) { network in
                                Text(network).tag(network)
                            }
                        }
                    } else {
                        TextField("اسم الشبكة SSID", text: $wifiSSID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    SecureField("كلمة مرور الشبكة", text: $wifiPassword)

                    HStack {
                        Button {
                            connectWifi()
                        } label: {
                            Label("اتصال", systemImage: "wifi")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!wifiEnabled || wifiSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDeviceID == nil)

                        Spacer()

                        Button(role: .destructive) {
                            forgetWifi()
                        } label: {
                            Label("نسيان الشبكة", systemImage: "trash")
                        }
                        .disabled(selectedDeviceID == nil)
                    }

                    if let wifiMessage {
                        Text(wifiMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("البحث يدوي فقط، وماكو Scan مستمر. بهالشكل نقلل تأثير Wi-Fi على BLE أثناء الاستخدام الطبيعي.")
                    Text("إذا الإنترنت شغال، أوامر السيارة تروح MQTT عبر الشريحة أو Wi-Fi؛ BLE يبقى للدخول الذكي، ويرجع fallback محلي فقط إذا انقطع الإنترنت.")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Wi-Fi الـESP", systemImage: "wifi")
                }

                Section {
                    Toggle("تشغيل الشريحة / 4G", isOn: $cellularEnabled)
                        .tint(.green)
                        .onChange(of: cellularEnabled) { _, enabled in
                            if !enabled { setCellularEnabled(false) }
                        }

                    HStack {
                        Label(cellularStatusText(vehicle.cellularStatus),
                              systemImage: vehicle.cellularRegistered ? "antenna.radiowaves.left.and.right" : "simcard")
                            .foregroundStyle(vehicle.cellularRegistered ? .green : .secondary)
                        Spacer()
                        if vehicle.cellularRegistered {
                            Text(vehicle.cellularNetwork)
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                    }

                    if vehicle.cellularSignalDBm > -120 {
                        LabeledContent("قوة الإشارة", value: "\(vehicle.cellularSignalDBm) dBm")
                    }
                    LabeledContent("تسجيل الشبكة", value: vehicle.cellularRegistered ? "مسجل" : "غير مسجل")
                    LabeledContent("بيانات الإنترنت", value: vehicle.cellularDataAttached ? "متصلة" : "غير متصلة")
                    LabeledContent("مسار الإنترنت", value: vehicle.internetRoute == "CELLULAR" ? "الشريحة" : (vehicle.internetRoute == "WIFI" ? "Wi-Fi" : "غير متصل"))
                        .foregroundStyle(vehicle.internetRoute == "CELLULAR" ? .green : .secondary)

                    TextField("APN", text: $cellularAPN)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("اسم مستخدم APN - اختياري", text: $cellularUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("كلمة مرور APN - اختيارية", text: $cellularPassword)
                    SecureField("SIM PIN - إذا الشريحة تحتاجه", text: $cellularSimPin)
                        .keyboardType(.numberPad)

                    Toggle("بث نت الشريحة كنقطة اتصال", isOn: $hotspotEnabled)
                        .tint(.green)
                    if hotspotEnabled {
                        TextField("اسم نقطة الاتصال", text: $hotspotSSID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("كلمة مرور نقطة الاتصال", text: $hotspotPassword)
                        HStack {
                            Label(vehicle.hotspotRunning ? "نقطة الاتصال شغالة" : "نقطة الاتصال متوقفة", systemImage: vehicle.hotspotRunning ? "personalhotspot" : "wifi.slash")
                                .foregroundStyle(vehicle.hotspotRunning ? .green : .secondary)
                            Spacer()
                            if vehicle.hotspotRunning {
                                Text(vehicle.hotspotSSID)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack {
                        Button {
                            saveCellular()
                        } label: {
                            Label("حفظ واتصال", systemImage: "simcard.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!cellularEnabled || cellularAPN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDeviceID == nil)

                        Spacer()

                        Button {
                            testCellular()
                        } label: {
                            Label("فحص", systemImage: "waveform.path.ecg")
                        }
                        .disabled(selectedDeviceID == nil)
                    }

                    Button(role: .destructive) {
                        forgetCellular()
                    } label: {
                        Label("مسح إعدادات الشريحة", systemImage: "trash")
                    }
                    .disabled(selectedDeviceID == nil)

                    if let cellularMessage {
                        Text(cellularMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("الـAPN الافتراضي مضبوط على internet. اسم المستخدم وكلمة المرور وSIM PIN اختيارية حسب شركة الشريحة.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("الشريحة والـ4G", systemImage: "simcard.fill")
                }

                Section {
                    Toggle(tr("وضع المطور", "Developer Mode"), isOn: $developerMode)
                    if developerMode {
                        LabeledContent("حالة BLE", value: mqtt.bluetoothStatus)
                        LabeledContent("MQTT", value: mqtt.connection.rawValue)
                        Text("وضع المطور للـLogs وCAN/OBD والفحص، ولا يغيّر مخارج السيارة وحده.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Label("التشخيص وCAN", systemImage: "waveform.path.ecg.rectangle.fill")
                }

                Section("اتصال MQTT المشفّر") {
                    TextField("عنوان السيرفر", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("المنفذ", text: $port)
                        .keyboardType(.numberPad)
                    TextField("اسم المستخدم", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("كلمة المرور", text: $password)
                    Label("TLS فقط، وكلمة المرور محفوظة في Keychain داخل الآيفون.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink {
                        SettingsAboutView()
                    } label: {
                        Label("النظام والتحديث", systemImage: "gearshape.2.fill")
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                }
            }
            .onAppear {
                let saved = mqtt.settings
                host = saved.host
                port = String(saved.port)
                username = saved.username
                password = saved.password
                wifiEnabled = vehicle.wifiEnabled
                if wifiSSID.isEmpty { wifiSSID = vehicle.wifiSSID }
                cellularEnabled = vehicle.cellularEnabled
                if !vehicle.cellularAPN.isEmpty { cellularAPN = vehicle.cellularAPN }
                hotspotEnabled = vehicle.hotspotEnabled
                if !vehicle.hotspotSSID.isEmpty { hotspotSSID = vehicle.hotspotSSID }
                loadConnectionPriority()
            }
        }
    }

    private func loadConnectionPriority() {
        let raw = UserDefaults.standard.string(forKey: "journey.settings.connectionPriority") ?? "CELLULAR,WIFI,BLE"
        let values = raw.split(separator: ",").map(String.init)
        if values.count == 3 && Set(values) == Set(["BLE", "CELLULAR", "WIFI"]) {
            connectionPriority = values
        } else {
            connectionPriority = ["CELLULAR", "WIFI", "BLE"]
        }
    }

    private func movePriority(at index: Int, offset: Int) {
        let target = index + offset
        guard connectionPriority.indices.contains(index),
              connectionPriority.indices.contains(target) else { return }
        connectionPriority.swapAt(index, target)
        priorityMessage = nil
    }

    private func saveConnectionPriority() {
        guard let id = selectedDeviceID else {
            priorityMessage = "ماكو ESP محدد"
            return
        }
        if mqtt.saveConnectionPriority(connectionPriority, to: id) {
            priorityMessage = "انحفظ الترتيب بالآيفون وانرسل للـESP"
        } else {
            priorityMessage = mqtt.lastError ?? "تعذر حفظ الأولوية"
        }
    }

    private func priorityTitle(_ route: String) -> String {
        switch route {
        case "BLE": return "Bluetooth BLE"
        case "CELLULAR": return "الشريحة / 4G"
        case "WIFI": return "Wi-Fi"
        default: return route
        }
    }

    private func priorityIcon(_ route: String) -> String {
        switch route {
        case "BLE": return "bolt.horizontal.circle"
        case "CELLULAR": return "cellularbars"
        case "WIFI": return "wifi"
        default: return "questionmark.circle"
        }
    }

    private func searchWifi() {
        guard let id = selectedDeviceID else {
            wifiMessage = "ماكو ESP محدد"
            return
        }
        wifiMessage = "تم إرسال أمر البحث للـESP"
        _ = mqtt.sendESPCommand(VehicleCommand(action: .wifiSearch), to: id)
    }

    private func setWifiEnabled(_ enabled: Bool) {
        guard let id = selectedDeviceID else { return }
        let settings = ESPWiFiSettings(enabled: enabled, ssid: wifiSSID, password: wifiPassword)
        _ = mqtt.sendESPCommand(VehicleCommand(action: .wifiConfig, wifiSettings: settings), to: id)
        wifiMessage = enabled ? "تم إرسال أمر تشغيل Wi-Fi" : "تم إرسال أمر إطفاء Wi-Fi"
    }

    private func connectWifi() {
        let ssid = wifiSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty else {
            wifiMessage = "اختار الشبكة أولاً"
            return
        }
        guard let id = selectedDeviceID else {
            wifiMessage = "ماكو ESP محدد"
            return
        }
        wifiEnabled = true
        let settings = ESPWiFiSettings(enabled: true, ssid: ssid, password: wifiPassword)
        _ = mqtt.sendESPCommand(VehicleCommand(action: .wifiConfig, wifiSettings: settings), to: id)
        wifiMessage = "جاري اتصال ESP بالشبكة"
    }

    private func forgetWifi() {
        guard let id = selectedDeviceID else { return }
        _ = mqtt.sendESPCommand(VehicleCommand(action: .wifiForget), to: id)
        wifiEnabled = false
        wifiSSID = ""
        wifiPassword = ""
        wifiMessage = "تم إرسال أمر نسيان الشبكة"
    }

    private func wifiStatusText(_ status: String) -> String {
        switch status {
        case "connecting": return "جاري الاتصال"
        case "searching": return "جاري البحث"
        case "networks_found": return "تم العثور على شبكات"
        case "networks_not_found": return "ما لكه شبكات"
        case "scan_failed": return "فشل البحث"
        case "network_required": return "اختار شبكة"
        case "forgotten": return "تم نسيان الشبكة"
        case "disconnected": return "غير متصل"
        default: return "Wi-Fi مطفأ"
        }
    }

    private func setCellularEnabled(_ enabled: Bool) {
        guard let id = selectedDeviceID else { return }
        let settings = ESPCellularSettings(
            enabled: enabled,
            apn: cellularAPN,
            username: cellularUsername,
            password: cellularPassword,
            simPin: cellularSimPin,
            hotspotEnabled: hotspotEnabled,
            hotspotSSID: hotspotSSID,
            hotspotPassword: hotspotPassword
        )
        _ = mqtt.sendESPCommand(VehicleCommand(action: .cellularConfig, cellularSettings: settings), to: id)
        cellularMessage = enabled ? "تم إرسال أمر تشغيل الشريحة" : "تم إرسال أمر إطفاء بيانات الشريحة"
    }

    private func saveCellular() {
        let apn = cellularAPN.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apn.isEmpty else {
            cellularMessage = "أدخل APN"
            return
        }
        guard let id = selectedDeviceID else {
            cellularMessage = "ماكو ESP محدد"
            return
        }
        cellularEnabled = true
        let settings = ESPCellularSettings(
            enabled: true,
            apn: apn,
            username: cellularUsername,
            password: cellularPassword,
            simPin: cellularSimPin,
            hotspotEnabled: hotspotEnabled,
            hotspotSSID: hotspotSSID,
            hotspotPassword: hotspotPassword
        )
        _ = mqtt.sendESPCommand(VehicleCommand(action: .cellularConfig, cellularSettings: settings), to: id)
        cellularMessage = "تم حفظ إعدادات الشريحة وجاري الفحص"
    }

    private func testCellular() {
        guard let id = selectedDeviceID else { return }
        _ = mqtt.sendESPCommand(VehicleCommand(action: .cellularTest), to: id)
        cellularMessage = "جاري فحص الشريحة والشبكة"
    }

    private func forgetCellular() {
        guard let id = selectedDeviceID else { return }
        _ = mqtt.sendESPCommand(VehicleCommand(action: .cellularForget), to: id)
        cellularEnabled = false
        cellularAPN = "internet"
        cellularUsername = ""
        cellularPassword = ""
        cellularSimPin = ""
        hotspotEnabled = false
        hotspotSSID = "JOURNEY-4G"
        hotspotPassword = "Journey2017"
        cellularMessage = "تم إرسال أمر مسح إعدادات الشريحة"
    }

    private func cellularStatusText(_ status: String) -> String {
        switch status {
        case "ready": return "الشريحة جاهزة"
        case "registered": return "مسجلة على الشبكة"
        case "data_attached": return "الإنترنت متصل"
        case "checking": return "جاري الفحص"
        case "pin_required": return "تحتاج SIM PIN"
        case "sim_missing": return "الشريحة غير موجودة"
        case "registration_failed": return "فشل تسجيل الشبكة"
        case "data_failed": return "فشل اتصال البيانات"
        case "disabled": return "الشريحة مطفأة"
        default: return "بانتظار الفحص"
        }
    }

    private func save() {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHost.isEmpty {
            dismiss()
            return
        }
        guard let value = UInt16(port), value > 0 else {
            errorText = "رقم المنفذ غير صحيح"
            return
        }
        mqtt.saveSettings(host: cleanHost, port: value, username: username, password: password)
        mqtt.connect()
        dismiss()
    }
}

private struct SettingsAboutView: View {
    var body: some View {
        List {
            Section("JOURNEY") {
                LabeledContent("إصدار التطبيق", value: "2.4.16 (47)")
                LabeledContent("Firmware المطلوب", value: "v12.66")
            }
            Section("التحديث") {
                Label("تحديث ESP عبر OTA يبقى من صفحة الفحص/الصيانة.", systemImage: "arrow.triangle.2.circlepath")
                Label("إعدادات الواجهة تُحفظ محلياً وتبقى بعد إعادة تشغيل التطبيق.", systemImage: "internaldrive.fill")
            }
        }
        .navigationTitle("النظام والتحديث")
    }
}

#Preview {
    ContentView()
        .environmentObject(MQTTService())
        .environmentObject(ProximityMonitor())
        .environmentObject(DeviceStore())
}
