import Foundation
import CryptoKit
import CoreLocation
import MapKit
import SwiftUI
import WidgetKit
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
    @AppStorage("journey.demo.enabled") private var demoEnabled = false
    @AppStorage("journey.demo.locked") private var demoLocked = true
    @AppStorage("journey.demo.engine") private var demoEngine = false
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
                JourneyWallpaperView()

                if demoEnabled {
                    JourneyIsolatedDemoView()
                } else if let device = devices.selectedDevice {
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
                            JourneyMapDashboardView(vehicle: vehicle, vehicleName: device.name, deviceID: device.deviceID)
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
                                JourneyTheme.surface
                                    .ignoresSafeArea(edges: .top)
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(JourneyTheme.ink.opacity(0.08)).frame(height: 0.5)
                            }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        liquidTabBar
                            .background {
                                JourneyTheme.surface
                                    .ignoresSafeArea(edges: .bottom)
                            }
                    }
                    .tint(JourneyTheme.accent)
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
                    .preferredColorScheme(preferredScheme)
            }
            .sheet(isPresented: $showingLocalDiagnostics) {
                NavigationStack {
                    ESPStatusView(
                        vehicle: devices.selectedDevice.map { mqtt.state(for: $0.deviceID) } ?? VehicleState(),
                        bluetoothStatus: mqtt.bluetoothStatus,
                        deviceID: devices.selectedDevice?.deviceID
                    )
                        .navigationTitle(JL("حالة واتصال ESP", "ESP status and connectivity"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(JL("إغلاق", "Close")) { showingLocalDiagnostics = false }
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
                        .navigationTitle(JL("قراءة OBD عبر BLE", "OBD over BLE"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(JL("إغلاق", "Close")) { showingOBDStatus = false }
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
                    .navigationTitle(JL("شاشة HUD", "HUD display"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(JL("تم", "Done")) { showingHUD = false }
                        }
                    }
                }
                .preferredColorScheme(preferredScheme)
            }
            .sheet(isPresented: $showingMap) {
                NavigationStack {
                    JourneyMapDashboardView(
                        vehicle: devices.selectedDevice.map { mqtt.state(for: $0.deviceID) } ?? VehicleState(),
                        vehicleName: devices.selectedDevice?.name ?? "JOURNEY",
                        deviceID: devices.selectedDevice?.deviceID
                    )
                    .environmentObject(mqtt)
                }
                .preferredColorScheme(preferredScheme)
            }
            .sheet(isPresented: $showingMQTTSettings) {
                MQTTSettingsView()
                    .environmentObject(mqtt)
                    .preferredColorScheme(preferredScheme)
            }
            .sheet(isPresented: $showingKeylessEntry) {
                if let device = devices.selectedDevice {
                    KeylessEntrySettingsView(deviceID: device.deviceID)
                        .environmentObject(mqtt)
                        .preferredColorScheme(preferredScheme)
                }
            }
            .onAppear {
                mqtt.syncSelectedWidget(force: true)
                WidgetCenter.shared.reloadAllTimelines()
                if devices.devices.isEmpty && !demoEnabled { showingDevices = true }
                mqtt.setDemoMode(demoEnabled)
                if !demoEnabled {
                    if let device = devices.selectedDevice { mqtt.prepareBluetooth(for: device.deviceID) }
                    if mqtt.isConfigured && mqtt.connection != .connected { mqtt.connect() }
                }
                if let shortcut = homeShortcuts.consume() {
                    authenticateHomeScreenShortcut(shortcut)
                }
            }
            .onChange(of: scenePhase, initial: false) { _, phase in
                guard phase == .active, !demoEnabled, let device = devices.selectedDevice else { return }
                // Foregrounding an already-created SwiftUI view does not always
                // trigger onAppear. Wake BLE proactively so no button press is
                // required to make the ESP connect.
                mqtt.resumeBluetooth(for: device.deviceID)
            }
            .onChange(of: devices.selectedID, initial: false) { _, _ in
                guard !demoEnabled, let device = devices.selectedDevice else { return }
                mqtt.prepareBluetooth(for: device.deviceID)
                mqtt.refreshVehicleSubscription()
                mqtt.syncSelectedWidget(force: true)
            }
            .onChange(of: demoEnabled) { _, active in
                mqtt.setDemoMode(active)
                if !active {
                    if let device = devices.selectedDevice { mqtt.prepareBluetooth(for: device.deviceID) }
                    if mqtt.isConfigured { mqtt.connect() }
                }
                mqtt.syncSelectedWidget(force: true)
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onReceive(homeShortcuts.$pendingShortcut) { shortcut in
                guard let shortcut else { return }
                homeShortcuts.clear()
                authenticateHomeScreenShortcut(shortcut)
            }
            .alert(JL("تأكيد التشغيل عن بُعد", "Confirm remote start"), isPresented: $confirmStart) {
                Button(JL("إلغاء", "Cancel"), role: .cancel) {}
                Button(JL("إرسال الأمر", "Send command")) {
                    guard let device = devices.selectedDevice else { return }
                    Task {
                        let allowed = await faceID.authenticate(reason: JL("تأكيد التشغيل عن بُعد لسيارة JOURNEY", "Confirm JOURNEY remote start"))
                        guard allowed else {
                            faceIDError = faceID.lastError
                            return
                        }
                        _ = mqtt.send(.start, to: device.deviceID)
                    }
                }
            } message: {
                Text(JL("سيرسل التطبيق أمر تشغيل حقيقي إلى ESP. تأكد أن السيارة بمكان آمن والقير على P.", "The app will send a real start command to ESP. Make sure the vehicle is in a safe location and the transmission is in P."))
            }
            .alert(JL("تعذر التأكيد", "Confirmation failed"), isPresented: Binding(
                get: { faceIDError != nil },
                set: { if !$0 { faceIDError = nil } }
            )) {
                Button(JL("حسنًا", "OK"), role: .cancel) { faceIDError = nil }
            } message: {
                Text(JLStored(faceIDError ?? ""))
            }
        }
        .preferredColorScheme(preferredScheme)
        .dynamicTypeSize(preferredDynamicType)
        .environment(\.layoutDirection, appLanguage == "en" ? .leftToRight : .rightToLeft)
        .environment(\.locale, Locale(identifier: appLanguage == "en" ? "en" : "ar"))
        .tint(JourneyTheme.accent)
    }

    // الصفحة الأولى تبقى واجهة JOURNEY الأساسية: السيارة وحالتها المختصرة.
    private func overviewPage(device: DeviceProfile, vehicle: VehicleState) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                AnyView(quickNavigation)
                AnyView(JourneySelectedCarView(state: vehicle).padding(.horizontal, -14))
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
                    .foregroundStyle(JourneyTheme.ink.opacity(0.34))
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
                liquidTab(title: JL("معلومات", "About"), icon: "info.circle", tag: 4)
                liquidTab(title: "OBD", icon: "stethoscope", tag: 3)
                Color.clear.frame(width: 80, height: 40)
                liquidTab(title: JL("السيارة", "Vehicle"), icon: "car.fill", tag: 1)
                liquidTab(title: JL("الخريطة", "Map"), icon: "map.fill", tag: 2)
            }
            .padding(.horizontal, 8)
            .frame(height: 60)
            .background {
                Capsule()
                    .fill(JourneyTheme.surface.opacity(0.90))
                    .overlay(Capsule().fill(.ultraThinMaterial).opacity(0.16))
            }
            .overlay(Capsule().stroke(JourneyTheme.ink.opacity(0.24), lineWidth: 1))

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
            .foregroundStyle(selectedTab == tag ? .cyan : JourneyTheme.ink.opacity(0.58))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selectedTab == tag ? .cyan.opacity(0.13) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var liquidHomeTab: some View {
        Button { selectedTab = 0 } label: {
            VStack(spacing: 3) {
                Image(systemName: "house.fill").font(.system(size: 22, weight: .bold))
                Text(appText(JL("الرئيسية", "Home"), "Home")).font(.system(size: 10, weight: .black))
            }
            .foregroundStyle(.white)
            .frame(width: 74, height: 74)
            .background(selectedTab == 0 ? Color.cyan.opacity(0.92) : JourneyTheme.surface.opacity(0.96), in: Circle())
            .overlay(Circle().stroke(selectedTab == 0 ? JourneyTheme.ink.opacity(0.62) : .cyan.opacity(0.55), lineWidth: 1.2))
            .shadow(color: .cyan.opacity(selectedTab == 0 ? 0.46 : 0.20), radius: 15, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mqtt.connection == .connected ? .green : .orange)
                .frame(width: 7, height: 7)
            Text(mqtt.connection.title)
                .font(.caption.weight(.semibold))
        }
    }

    private func topAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.title3.bold())
                Text(title).font(.caption.bold())
            }
            .foregroundStyle(JourneyTheme.accent)
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
                .stroke(LinearGradient(colors: [JourneyTheme.ink.opacity(0.35), .cyan.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }

    private func authenticateHomeScreenShortcut(_ shortcut: HomeScreenShortcut) {
        if demoEnabled {
            switch shortcut.action {
            case .lock: demoLocked = true
            case .unlock: demoLocked = false
            case .start:
                Task {
                    let allowed = await faceID.authenticate(reason: JL("تأكيد تشغيل المحرك التجريبي", "Confirm demo engine start"))
                    guard allowed else { faceIDError = faceID.lastError; return }
                    demoEngine.toggle()
                }
            default: break
            }
            return
        }
        guard let device = devices.selectedDevice else {
            faceIDError = JL("أضف جهاز السيارة أولاً حتى يعمل الاختصار.", "Add a vehicle device first to use this shortcut.")
            return
        }
        Task {
            // Lock/unlock use the owner's transport without a biometric prompt.
            // Start shows a safety confirmation; its Send button performs Face ID.
            if shortcut.action == .start {
                confirmStart = true
                return
            }
            let deviceID = device.deviceID
            mqtt.prepareBluetooth(for: deviceID)
            if mqtt.isConfigured && mqtt.connection != .connected { mqtt.connect() }
            // Wait for a fresh ESP state rather than silently dropping the
            // command while the app is waking up from a widget deep link.
            let previous = mqtt.lastStateAt[deviceID]
            var ready = false
            for _ in 0..<40 {
                if let at = mqtt.lastStateAt[deviceID],
                   Date().timeIntervalSince(at) >= 0,
                   Date().timeIntervalSince(at) < 4,
                   mqtt.state(for: deviceID).online,
                   (at != previous || Date().timeIntervalSince(at) < 2) {
                    ready = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard ready else {
                faceIDError = JL("ESP غير متصل؛ لم يُرسل الأمر.", "ESP is offline; command was not sent.")
                return
            }
            guard mqtt.send(shortcut.action, to: deviceID) else {
                faceIDError = JL("تعذر إرسال الأمر إلى ESP.", "Could not send the command to ESP.")
                return
            }
            mqtt.syncSelectedWidget(force: true)
        }
    }

    private func authenticateRemotePower(_ device: DeviceProfile, state: VehicleState) {
        guard mqtt.pendingRemotePower[device.deviceID] == nil else { return }
        Task {
            let turningOn = !state.remotePowered
            let allowed = await faceID.authenticate(
                reason: turningOn ? JL("تأكيد تشغيل طاقة ريموت السيارة", "Confirm vehicle remote power on") : JL("تأكيد إطفاء طاقة ريموت السيارة", "Confirm vehicle remote power off")
            )
            guard allowed else {
                faceIDError = faceID.lastError
                return
            }
            if !(await mqtt.setRemotePower(turningOn, for: device.deviceID)) {
                faceIDError = mqtt.lastError
            }
        }
    }

    private func deviceHeader(_ device: DeviceProfile, vehicle: VehicleState) -> some View {
        VStack(spacing: 4) {
            HStack {
                Button { showingDevices = true } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3)
                        .foregroundStyle(JourneyTheme.accent)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                VStack(spacing: 3) {
                    Text("JOURNEY")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .tracking(5)
                    Text(device.name).font(.headline)
                    Label(
                        vehicle.online ? (vehicle.cloudConnected && !mqtt.bluetoothStatus.contains(JL("متصل", "Connected")) ? "ONLINE • 4G" : device.deviceID) : JL("غير متصل", "Disconnected"),
                        systemImage: vehicle.cloudConnected ? "cloud.fill" : "location.fill"
                    )
                        .font(.caption)
                        .foregroundStyle(vehicle.cloudConnected ? .green.opacity(0.82) : JourneyTheme.ink.opacity(0.52))
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
                    Image(systemName: "cellularbars")
                    Text(state.cloudConnected ? (state.internetRoute == "CELLULAR" ? "4G" : "NET") : (state.cellularNetwork == JL("غير متاح", "Unavailable") ? "—" : state.cellularNetwork.uppercased()))
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(state.cloudConnected ? .green : networkColor(for: state.cellularSignalDBm))
                bluetoothDotIndicator(rssi: state.bluetoothRSSI)
            }
            .frame(width: 58, height: 58)
            .background(JourneyTheme.surface.opacity(0.66), in: Circle())
            .overlay(Circle().stroke(JourneyTheme.ink.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(JL("إعدادات اتصال ESP", "ESP connection settings"))
    }

    // السطر العلوي هو الشبكة (4G/3G)، والنقاط الأربع تحته هي قوة BLE بين
    // الهاتف وESP — مثل الترتيب المتفق عليه في مؤشر iPhone.
    private func bluetoothDotIndicator(rssi: Int) -> some View {
        let count: Int = rssi >= -65 ? 4 : rssi >= -80 ? 3 : rssi >= -95 ? 2 : rssi >= -105 ? 1 : 0
        return HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < count ? Color.cyan : JourneyTheme.ink.opacity(0.20))
                    .frame(width: index == 0 ? 5 : 4, height: index == 0 ? 5 : 4)
            }
        }
    }

    private func cellularIndicator(_ state: VehicleState) -> some View {
        connectionChip(
            Label(state.cellularNetwork == JL("غير متاح", "Unavailable") ? "—" : state.cellularNetwork.uppercased(), systemImage: "cellularbars")
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
            .background(JourneyTheme.ink.opacity(0.07), in: Capsule())
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
            statusPill(state.canLockValid ? (state.canLocked ? JL("مقفلة", "Locked") : JL("مفتوحة", "Unlocked")) : JL("حالة القفل غير معروفة", "Lock state unknown"), icon: state.canLockValid ? (state.canLocked ? "lock.fill" : "lock.open.fill") : "questionmark.circle", active: state.canLockValid && !state.canLocked)
            statusPill(state.engineStateText, icon: "engine.combustion.fill", active: state.simulatedEngineRunning)
            statusPill(state.gpsValid ? JL("GPS متصل", "GPS connected") : JL("GPS غير متاح", "GPS unavailable"), icon: "location.fill", active: state.gpsValid)
        }
    }

    private var keylessEntryCard: some View {
        Button { showingKeylessEntry = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.radiowaves.forward")
                    .font(.title3.bold())
                    .foregroundStyle(JourneyTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(.cyan.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(appText(JL("الدخول الذكي", "Smart entry"), "Keyless"))
                        .font(.subheadline.bold())
                    Text(JL("فتح عند الاقتراب وقفل عند الابتعاد — BLE", "Unlock nearby and lock on departure — BLE"))
                        .font(.caption)
                        .foregroundStyle(JourneyTheme.ink.opacity(0.50))
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
            updateText = age < 60 ? JL("الآن", "Now") : JL("قبل \(Int(age / 60)) د", "\(Int(age / 60)) min ago")
        } else {
            updateText = state.online ? JL("بانتظار قراءة", "Waiting for a reading") : JL("غير متصل", "Disconnected")
        }

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(JL("سلامة ومتابعة", "Safety and monitoring"), systemImage: "shield.checkered")
                    .font(.headline)
                Spacer()
                Label(JL("الإنذار جاهز", "Alarm ready"), systemImage: "bell.badge.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                healthMetric(JL("البطارية", "Battery"), value: String(format: "%.1f V", state.batteryVoltage), icon: "battery.75percent", tint: state.batteryVoltage >= 12 ? .green : .orange)
                healthMetric(JL("آخر تحديث", "Last update"), value: updateText, icon: "clock.arrow.circlepath", tint: state.online ? .cyan : .orange)
            }
            if let last = mqtt.commandHistory.first {
                Label(last.title, systemImage: last.icon)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(JourneyTheme.ink.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label(JL("لا توجد أوامر بعد", "No commands yet"), systemImage: "list.bullet.rectangle")
                    .font(.caption2)
                    .foregroundStyle(JourneyTheme.ink.opacity(0.50))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard(padding: 15)
    }

    private func ownerManagementCard(device: DeviceProfile, state: VehicleState) -> some View {
        let isAdmin = !state.ownerAdminPhone.isEmpty && state.ownerAdminPhone == AppConfig.phoneID
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(JL("أجهزة المالك", "Owner devices"), systemImage: "person.2.badge.gearshape")
                    .font(.headline)
                Spacer()
                Text("\(state.authorizedPhoneCount) / 10")
                    .font(.caption.bold()).foregroundStyle(JourneyTheme.accent)
            }
            if !state.ownerStateKnown {
                Text(JL("جاري التحقق من المدير المحفوظ في ESP…", "Checking the administrator saved on ESP…")).font(.caption).foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
            } else if !state.trustedPhoneConfigured {
                Text(JL("لا يوجد مالك مسجّل. سجّل هذا الآيفون كمدير.", "No registered owner. Register this iPhone as administrator.")).font(.caption).foregroundStyle(.orange)
                Button(JL("تسجيل هذا الآيفون كمدير", "Register this iPhone as administrator"), systemImage: "person.badge.key.fill") { secureOwnerAction(.ownerRegister, to: device.deviceID) }
                    .buttonStyle(.borderedProminent)
            } else if isAdmin {
                Text(JL("هذا الآيفون هو المدير. الأجهزة الجديدة تحتاج موافقتك.", "This iPhone is the administrator. New devices require your approval.")).font(.caption).foregroundStyle(.secondary)
                if !state.pendingOwnerPhone.isEmpty {
                    Text(JL("طلب جديد: \(state.pendingOwnerPhone.prefix(8))…", "New request: \(state.pendingOwnerPhone.prefix(8))…")).font(.caption).foregroundStyle(.orange)
                    HStack {
                        Button(JL("موافقة", "Approve")) { secureOwnerAction(.ownerApprove, to: device.deviceID, target: state.pendingOwnerPhone) }.buttonStyle(.borderedProminent)
                        Button(JL("رفض", "Reject"), role: .destructive) { secureOwnerAction(.ownerReject, to: device.deviceID, target: state.pendingOwnerPhone) }.buttonStyle(.bordered)
                    }
                }
                Button(JL("مسح كل الأجهزة الأخرى", "Remove all other devices"), role: .destructive) { secureOwnerAction(.ownerClear, to: device.deviceID) }
                    .font(.caption)
            } else {
                Text(JL("الآيفون الإداري يوافق على ربط هذا الجهاز قبل تفعيل الأوامر.", "The administrator iPhone must approve this device before commands are enabled.")).font(.caption).foregroundStyle(.secondary)
                Button(JL("إرسال طلب ربط", "Request pairing"), systemImage: "person.badge.plus") { secureOwnerAction(.ownerRequest, to: device.deviceID) }
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
            guard await faceID.authenticate(reason: JL("تأكيد إدارة أجهزة مالك JOURNEY", "Confirm JOURNEY owner device management")) else {
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
                Text(title).font(.caption2).foregroundStyle(JourneyTheme.ink.opacity(0.48))
                Text(value).font(.subheadline.bold())
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(JourneyTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func statusPill(_ title: String, icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .foregroundStyle(active ? .cyan : JourneyTheme.ink.opacity(0.65))
            .background(active ? .cyan.opacity(0.13) : JourneyTheme.ink.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(active ? .cyan.opacity(0.30) : JourneyTheme.ink.opacity(0.07)))
    }

    private func mainControls(_ device: DeviceProfile, state: VehicleState) -> some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                largeControl(JL("قفل", "Lock"), subtitle: "Lock", icon: "lock.fill", tint: .blue, statusActive: mqtt.isButtonActive("lock", for: device.deviceID), feedbackKey: "lock") { mqtt.send(.lock, to: device.deviceID) }
                largeControl(JL("فتح", "Unlock"), subtitle: "Unlock", icon: "lock.open.fill", tint: .green, statusActive: mqtt.isButtonActive("unlock", for: device.deviceID), feedbackKey: "unlock") { mqtt.send(.unlock, to: device.deviceID) }
                largeControl(JL("تشغيل", "Start"), subtitle: "Remote start", icon: "power", tint: .orange, statusActive: mqtt.isButtonActive("start", for: device.deviceID), feedbackKey: "start") { confirmStart = true }
                largeControl(JL("إنذار", "Alarm"), subtitle: "Alarm", icon: "bell.and.waves.left.and.right.fill", tint: .red, statusActive: mqtt.isButtonActive("alarm", for: device.deviceID), feedbackKey: "alarm") { mqtt.send(.horn, to: device.deviceID) }
            }
            // زر الطاقة تحت الأزرار وبعرض صف كامل، مثل حجم زرين متجاورين.
            largeControl(
                state.remotePowered ? JL("إطفاء طاقة الريموت", "Turn remote power off") : JL("تشغيل طاقة الريموت", "Turn remote power on"),
                subtitle: mqtt.pendingRemotePower[device.deviceID] != nil
                    ? JL("بانتظار تأكيد ESP…", "Waiting for ESP confirmation…")
                    : (!state.online ? JL("ESP غير متصل", "ESP disconnected") : (state.remotePowered ? JL("مشتغل الآن • اضغط للإطفاء", "On now • Tap to turn off") : JL("طافي • Face ID", "Off • Face ID"))),
                icon: state.remotePowered ? "key.fill" : "key",
                tint: state.remotePowered ? .green : .orange,
                status: !state.online ? JL("غير متاح", "Unavailable") : (state.remotePowered ? JL("مشتغل", "On") : JL("طافي", "Off")),
                statusActive: state.online && state.remotePowered,
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
                        .foregroundStyle(statusActive ? .green : JourneyTheme.ink.opacity(0.50))
                }
                Spacer(minLength: 0)
                if let status {
                    Text(status)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(statusActive ? .green : JourneyTheme.ink.opacity(0.55))
                        .background(statusActive ? .green.opacity(0.14) : JourneyTheme.ink.opacity(0.07), in: Capsule())
                }
            }
            .foregroundStyle(statusActive ? .green : .cyan)
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background((statusActive ? Color.green : Color.cyan).opacity(statusActive ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 18))
            .scaleEffect(feedbackKey != nil && pressedControlToken == feedbackKey ? 0.975 : 1.0)
            .animation(.easeOut(duration: 0.12), value: pressedControlToken)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke((statusActive ? Color.green : Color.cyan).opacity(0.55)))
        }
        .buttonStyle(.plain)
    }

    private func vehicleStatusText(_ state: VehicleState) -> String {
        if !state.online { return JL("ESP غير متصل", "ESP disconnected") }
        if !state.rpmValid { return JL("قراءة المحرك غير متاحة", "Engine reading unavailable") }
        if state.obdConnected && state.canAwake { return state.rpm > 0 ? JL("OBD مباشر • المحرك شغال", "Live OBD • Engine running") : JL("OBD مباشر • IGN/ACC", "Live OBD • IGN/ACC") }
        if state.obdConnected { return JL("KONNWEI متصلة • CAN نايم", "KONNWEI connected • CAN asleep") }
        return JL("بانتظار OBD", "Waiting for OBD")
    }

    private func telemetryCard(_ state: VehicleState) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(appText(JL("بيانات السيارة", "Vehicle data"), "Vehicle data")).font(.headline)
                Spacer()
                Text(vehicleStatusText(state)).font(.caption).foregroundStyle(.cyan.opacity(0.75))
            }
            Divider().overlay(JourneyTheme.ink.opacity(0.08))
            HStack {
                metric("RPM", value: state.rpmValid ? "\(state.rpm)" : "—")
                metric(appText(JL("السرعة", "Speed"), "Speed"), value: !state.speedValid ? "—" : appSpeedUnit == "mph" ? "\(Int((Double(state.speedKph) * 0.621371).rounded())) mph" : "\(state.speedKph) km/h")
                metric(appText(JL("الحرارة", "Temperature"), "Temperature"), value: state.coolantValid ? (appTemperatureUnit == "f" ? "\(Int((Double(state.coolantC) * 9.0 / 5.0 + 32.0).rounded()))°F" : "\(state.coolantC)°C") : "—")
            }
            HStack {
                metric(JL("فولت البطارية", "Battery voltage"), value: state.batteryVoltage > 0 ? String(format: "%.2f V", state.batteryVoltage) : "—")
                metric(JL("بنزين", "Fuel"), value: state.obdConnected && state.fuelLevelValid ? "\(state.fuelLevelPercent)%" : "—")
                metric(JL("OBD رد/ث", "OBD responses/s"), value: state.obdConnected ? "\(state.obdResponseRate)" : "—")
            }
            HStack {
                Label(state.gpsValid ? JL("GPS متصل", "GPS connected") : JL("بانتظار GPS", "Waiting for GPS"), systemImage: "location.fill")
                Spacer()
                Label(state.obdConnected ? JL("OBD متصل", "OBD connected") : JL("OBD غير متصل", "OBD disconnected"), systemImage: "point.3.connected.trianglepath.dotted")
            }
            .font(.caption)
            .foregroundStyle(JourneyTheme.ink.opacity(0.47))
                Label(JL("RPM والحرارة وحالة الأبواب واللايت والإشارات من إطارات CAN المؤكدة عبر OBD؛ السرعة والبنزين من PIDs القياسية", "RPM, coolant, doors, lights and turn signals use confirmed CAN frames through OBD; speed and fuel use standard PIDs."), systemImage: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(JourneyTheme.accent)
        }
        .glassCard(padding: 16)
    }

    private func aiAssistantCard(_ state: VehicleState) -> some View {
        let insights = AIAnalysisService.analyze(state)

        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(JourneyTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appText(JL("المساعد الذكي", "Smart assistant"), "AI Assistant")).font(.headline)
                    Text(JL("تحليل وشرح فقط — لا يتحكم بالمخارج ولا يمسح الأعطال", "Analysis and explanation only — no output control or code clearing"))
                        .font(.caption2)
                        .foregroundStyle(JourneyTheme.ink.opacity(0.48))
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
                        Text(JLStored(insight.title)).font(.subheadline.bold())
                        Spacer()
                        Text(insight.severity.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(aiColor(insight.severity))
                    }
                    Text(JLStored(insight.explanation))
                        .font(.caption)
                        .foregroundStyle(JourneyTheme.ink.opacity(0.70))
                    Label(insight.nextStep, systemImage: "wrench.and.screwdriver.fill")
                        .font(.caption2)
                        .foregroundStyle(JourneyTheme.ink.opacity(0.48))
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
            Text(title).font(.caption2).foregroundStyle(JourneyTheme.ink.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "car.side.lock")
                .font(.system(size: 58))
                .foregroundStyle(JourneyTheme.accent)
            Text(appText(JL("أضف أول جهاز", "Add your first device"), "Add your first device")).font(.title2.bold())
            Text(JL("ابحث عن البورد القريب بالبلوتوث حتى يظهر هنا.", "Search for the nearby board over Bluetooth to show it here."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(JL("فتح البحث", "Open search")) { showingDevices = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .glassCard()
    }
}

private struct JourneyAppInfoView: View {
    var body: some View {
        ZStack {
            JourneyWallpaperView()

            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "car.side.and.exclamationmark")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(JourneyTheme.accent)
                        .padding(18)
                        .background(.cyan.opacity(0.10), in: Circle())

                    VStack(spacing: 7) {
                        Text("JOURNEY")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .tracking(5)
                        Text(JL("نظام التحكم والتشخيص الذكي للسيارة", "Smart vehicle control and diagnostics"))
                            .font(.subheadline)
                            .foregroundStyle(JourneyTheme.ink.opacity(0.62))
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        Label(JL("تصميم وتطوير", "Design and development"), systemImage: "paintbrush.pointed.fill")
                            .font(.caption.bold())
                            .foregroundStyle(JourneyTheme.accent)
                        Text(JL("مهند الربيعي", "Mohaned Al-Rubaie"))
                            .font(.title3.bold())
                        Text(JL("الريموت، NFC، OBD، التعقّب والتحليل الذكي ضمن نظام واحد.", "Remote, NFC, OBD, tracking and intelligent analysis in one system."))
                            .font(.caption)
                            .foregroundStyle(JourneyTheme.ink.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(padding: 18)

                    VStack(spacing: 10) {
                        contactLink(JL("البريد الإلكتروني", "Email"), value: "mohaned_baqi@yahoo.com", icon: "envelope.fill", url: "mailto:mohaned_baqi@yahoo.com")
                        contactLink(JL("اتصال", "Connect"), value: "07811119127", icon: "phone.fill", url: "tel:07811119127")
                        contactLink("WhatsApp", value: "07811119127", icon: "message.fill", url: "https://wa.me/9647811119127")
                        contactLink("Instagram", value: "@h0k38", icon: "camera.fill", url: "https://instagram.com/h0k38")
                    }
                    .glassCard(padding: 12)

                    Text("© 2026 JOURNEY • Designed by Mohaned Al‑Rubaie")
                        .font(.caption2)
                        .foregroundStyle(JourneyTheme.ink.opacity(0.38))
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
                    .foregroundStyle(JourneyTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(JourneyTheme.ink.opacity(0.52))
                    Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(JourneyTheme.ink)
                }
                Spacer()
                Image(systemName: "arrow.up.left.square").foregroundStyle(JourneyTheme.ink.opacity(0.42))
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

        var title: String {
            switch self {
            case .automatic: return JL("تلقائي", "Automatic")
            case .speed: return JL("سرعة", "Speed")
            case .temperature: return JL("حرارة", "Temperature")
            case .rpm: return "RPM"
            case .gear: return JL("كير", "Gear")
            }
        }

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
        case .automatic: return JL("تلقائي", "Automatic")
        case .speed: return speedUnit == "mph" ? JL("السرعة mph", "Speed mph") : JL("السرعة km/h", "Speed km/h")
        case .temperature: return temperatureUnit == "f" ? JL("حرارة ماء المحرك °F", "Engine coolant °F") : JL("حرارة ماء المحرك °C", "Engine coolant °C")
        case .rpm: return JL("دورات المحرك RPM", "Engine RPM")
        case .gear: return JL("نمرة الكير", "Gear position")
        }
    }

    var body: some View {
        ZStack {
            JourneyWallpaperView()

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
                Text(isEnabled ? JL("تعمل", "Running") : JL("مطفيّة", "Off"))
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
                .foregroundStyle(JourneyTheme.ink.opacity(0.55))
        }
        .glassCard(padding: 15)
    }

    private var powerAndBrightness: some View {
        VStack(spacing: 14) {
            Toggle(JL("تشغيل شاشة الـHUD", "Enable HUD display"), isOn: $isEnabled)
                .font(.subheadline.bold())

            HStack {
                Label(JL("السطوع", "Brightness"), systemImage: "sun.max.fill")
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
            Text(JL("المعلومة المعروضة", "Displayed information")).font(.headline)
            Picker(JL("نوع العرض", "Display mode"), selection: $storedMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard(padding: 15)
    }

    private var automaticRules: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(JL("ترتيب الوضع التلقائي", "Automatic mode order")).font(.headline)
            ruleRow(JL("السيارة واقفة", "Vehicle stationary"), value: JL("حرارة", "Temperature"))
            ruleRow(JL("السيارة تتحرك", "Vehicle moving"), value: JL("سرعة", "Speed"))
            ruleRow(JL("الحرارة عالية", "High temperature"), value: JL("حرارة فوراً", "Show temperature immediately"))
            ruleRow(JL("RPM عالي", "High RPM"), value: JL("RPM فوراً", "Show RPM immediately"))
            Divider().overlay(JourneyTheme.ink.opacity(0.08))
            Stepper(JL("تنبيه الحرارة: \(temperatureAlert)°C", "Temperature alert: \(temperatureAlert)°C"), value: $temperatureAlert, in: 90...125)
            Stepper(JL("حد RPM: \(rpmAlert)", "RPM threshold: \(rpmAlert)"), value: $rpmAlert, in: 2500...7000, step: 250)
        }
        .font(.subheadline)
        .glassCard(padding: 15)
    }

    private func ruleRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(JourneyTheme.ink.opacity(0.65))
            Spacer()
            Text(value).bold().foregroundStyle(.red)
        }
    }

    private var testControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle(JL("استخدم بيانات السيارة", "Use vehicle data"), isOn: $useLiveData)
                .font(.headline)

            if useLiveData {
                Text(vehicle.obdConnected ? JL("يعرض قراءات OBD عبر Bluetooth الحالية.", "Shows current OBD readings over Bluetooth.") : JL("قطعة OBD غير متصلة حالياً.", "OBD adapter is currently disconnected."))
                    .font(.caption)
                    .foregroundStyle(JourneyTheme.ink.opacity(0.50))
            } else {
                Stepper(JL("سرعة التجربة: \(testSpeed) km/h", "Test speed: \(testSpeed) km/h"), value: $testSpeed, in: 0...240)
                Stepper(JL("حرارة التجربة: \(testTemperature)°C", "Test temperature: \(testTemperature)°C"), value: $testTemperature, in: 20...130)
                Stepper(JL("RPM التجريبي: \(testRPM)", "Test RPM: \(testRPM)"), value: $testRPM, in: 0...8000, step: 250)
                Picker(JL("نمرة الكير", "Gear position"), selection: $testGear) {
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
            JL("الصفحة جاهزة للمحاكاة. عند ربط كود ESP تُرسل له: وضع العرض، السطوع، الحدود، والقراءة الحالية عبر BLE.", "This page supports simulation. When ESP firmware is connected, display mode, brightness, thresholds and current readings are sent over BLE."),
            systemImage: "antenna.radiowaves.left.and.right"
        )
        .font(.caption)
        .foregroundStyle(JourneyTheme.ink.opacity(0.52))
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
                            colors: [JourneyTheme.ink.opacity(0.42), .cyan.opacity(0.12), JourneyTheme.ink.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [JourneyTheme.ink.opacity(0.08), .clear], startPoint: .top, endPoint: .center))
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
    @State private var tempWarningC = 50.0
    @State private var tempWarningDirty = false
    @State private var pendingTempWarning: Int?
    @State private var tempSaveStatus = ""
    @State private var updateStatus = ""
    @State private var firmwareURL = ""
    @State private var showingFirmwareImporter = false
    @State private var selectedFirmwareName = ""
    @State private var selectedFirmwareBytes = 0
    @State private var selectedFirmwareSHA256 = ""
    @State private var selectedFirmwareData: Data?
    @State private var maintenanceMode = false
    @State private var powerSaveMode = 0
    @State private var powerSaveIdleMinutes = 30.0
    @State private var diagnosticReport = ""
    @State private var diagnosticMessage = ""

    var body: some View {
        List {
            Section(JL("الاتصال المباشر", "Direct connection")) {
                Label(JLStored(bluetoothStatus), systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(JLStored(bluetoothStatus).hasPrefix(JL("BLE متصل", "BLE connected")) ? .green : .orange)
                statusRow(JL("حالة ESP", "ESP status"), vehicle.online ? JL("متصل", "Connected") : JL("بانتظار الاتصال", "Waiting for connection"))
                statusRow(JL("وقت التشغيل", "Uptime"), JL("\(vehicle.uptimeSeconds) ثانية", "\(vehicle.uptimeSeconds) seconds"))
                statusRow(JL("طاقة الريموت", "Remote power"), !vehicle.online ? JL("غير متاح", "Unavailable") : (vehicle.remotePowered ? JL("مشتغلة", "On") : JL("مطفأة", "Off")))
                statusRow(JL("أجهزة المالك", "Owner devices"), vehicle.ownerStateKnown ? JL("\(vehicle.authorizedPhoneCount) / 10 مسجّل", "\(vehicle.authorizedPhoneCount) / 10 registered") : JL("بانتظار ESP", "Waiting for ESP"))
            }
            Section(JL("صحة ESP", "ESP health")) {
                statusRow(JL("حرارة شريحة ESP", "ESP chip temperature"), vehicle.online ? vehicle.espTemperatureC.map { String(format: "%.1f °C", $0) } ?? "—" : "—")
                statusRow(JL("بطارية ESP", "ESP battery"), vehicle.online && vehicle.espBatteryPercent != nil ? String(format: "%.0f%% · %.2f V", vehicle.espBatteryPercent ?? 0, vehicle.espBatteryVoltage ?? 0) : JL("غير متاحة — تحتاج حساس بطارية", "Unavailable — battery gauge required"))
                Text(!vehicle.online || vehicle.espTemperatureC == nil ? JL("بانتظار قراءة حرارة فعلية", "Waiting for a live temperature reading") : vehicle.espThermalLevel >= 2 ? JL("حرارة مرتفعة جداً؛ افحص التهوية والتغذية", "Very high temperature; check ventilation and power") : vehicle.espThermalLevel == 1 ? JL("حرارة مرتفعة؛ افحص التهوية", "High temperature; check ventilation") : JL("الحرارة دون حد التنبيه", "Temperature below warning threshold"))
                    .foregroundStyle(vehicle.online && vehicle.espTemperatureC != nil && vehicle.espThermalLevel > 0 ? Color.orange : Color.secondary)
                statusRow(JL("حد التنبيه المحفوظ", "Saved warning threshold"), vehicle.espTempWarningC.map { "\($0) °C" } ?? JL("بانتظار ESP v12.78", "Waiting for ESP v12.78"))
                statusRow(JL("بداية تنبيه الحرارة", "Temperature warning starts at"), "\(Int(tempWarningC)) °C")
                Slider(value: $tempWarningC, in: 35...75, step: 1, onEditingChanged: { editing in
                    if editing { tempWarningDirty = true; tempSaveStatus = "" }
                }).disabled(!vehicle.online || vehicle.espTempWarningC == nil || pendingTempWarning != nil)
                Button(JL("حفظ حد التنبيه على ESP", "Save warning threshold to ESP")) { saveTempWarning() }
                    .disabled(!vehicle.online || vehicle.espTempWarningC == nil || pendingTempWarning != nil || Int(tempWarningC) == vehicle.espTempWarningC)
                if !tempSaveStatus.isEmpty { Text(tempSaveStatus).font(.footnote) }
                Text(JL("الافتراضي 50°C؛ التصعيد عند 80°C. هذه حرارة الشريحة، وليست حرارة البطارية أو المقصورة.", "Default 50°C; escalation at 80°C. This is chip temperature, not battery or cabin temperature.")).font(.caption)
                if vehicle.online && vehicle.espResetReason == 9 {
                    Text(JL("آخر إعادة تشغيل: هبوط تغذية (Brownout)، وليس إثباتاً لعطل حراري.", "Last reset: brownout; this does not prove a thermal fault.")).foregroundStyle(.orange)
                }
                statusRow(JL("فيرموير ESP", "ESP firmware"), vehicle.online ? (vehicle.firmwareVersion.isEmpty ? "—" : vehicle.firmwareVersion) : "—")
            }
            Section(JL("تشخيص ESP الكامل", "Full ESP diagnostics")) {
                Button {
                    guard let deviceID else { return }
                    _ = mqtt.requestFullDiagnostics(for: deviceID, via: .bluetooth)
                } label: {
                    Label(JL("سحب التشخيص عبر البلوتوث", "Download diagnostics via Bluetooth"),
                          systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(deviceID == nil || mqtt.diagnosticTransferBusy)
                Button {
                    guard let deviceID else { return }
                    _ = mqtt.requestFullDiagnostics(for: deviceID, via: .cloud)
                } label: {
                    Label(JL("سحب التشخيص عبر الإنترنت", "Download diagnostics via Internet"),
                          systemImage: "icloud.and.arrow.down")
                }
                .disabled(deviceID == nil || mqtt.diagnosticTransferBusy)
                if mqtt.diagnosticTransferBusy {
                    ProgressView(mqtt.diagnosticTransferStatus)
                }
                if !mqtt.diagnosticTransferStatus.isEmpty {
                    Text(mqtt.diagnosticTransferStatus)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !mqtt.fullDiagnosticReport.isEmpty {
                    Button(JL("نسخ ملف التشخيص", "Copy diagnostics"), systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = mqtt.fullDiagnosticReport
                    }
                    ShareLink(item: mqtt.fullDiagnosticReport) {
                        Label(JL("مشاركة ملف التشخيص", "Share diagnostics"),
                              systemImage: "square.and.arrow.up")
                    }
                    Text(mqtt.fullDiagnosticReport)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text(JL("اختَر البلوتوث للفحص المحلي أو الإنترنت للفحص عن بُعد. كل مسار مستقل ولا يتحول تلقائياً إلى الثاني.",
                        "Choose Bluetooth for local diagnostics or Internet for remote diagnostics. Each route is independent and never silently switches."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(JL("OBD عبر BLE", "OBD over BLE")) {
                statusRow(JL("قطعة OBD", "OBD adapter"), vehicle.obdConnected ? JL("متصلة", "Connected") : JL("بانتظار الاتصال", "Waiting for connection"))
                statusRow(JL("السرعة", "Speed"), speedUnit == "mph" ? "\(Int((Double(vehicle.speedKph) * 0.621371).rounded())) mph" : "\(vehicle.speedKph) km/h")
                statusRow(JL("الردود/ث", "Responses/s"), "\(vehicle.obdResponseRate)")
                statusRow(JL("آخر حدث", "Last event"), vehicle.lastEvent)
            }
            Section(JL("إعدادات محفوظة على ESP", "Settings saved on ESP")) {
                settingSlider(JL("نبضة زر الريموت", "Remote button pulse"), value: $pulseMs, range: 100...2000, suffix: "ms")
                settingSlider(JL("انتظار تشغيل الريموت", "Remote wake delay"), value: $wakeDelayMs, range: 100...5000, suffix: "ms")
                settingSlider(JL("فصل طاقة الريموت", "Remote power off delay"), value: $powerOffDelayMs, range: 200...10000, suffix: "ms")
                HStack {
                    Text(JL("سطوع شاشة HUD", "HUD brightness"))
                    Spacer()
                    Stepper("\(Int(hudBrightness))", value: $hudBrightness, in: 0...7)
                        .labelsHidden()
                    Text("\(Int(hudBrightness))")
                        .foregroundStyle(.secondary)
                }
                Button(JL("حفظ الإعدادات على ESP", "Save settings to ESP"), systemImage: "square.and.arrow.down") { saveSettings() }
                    .disabled(deviceID == nil)
            }
            Section(JL("الحماية والطاقة", "Security and power")) {
                Toggle(JL("وضع الصيانة", "Maintenance mode"), isOn: $maintenanceMode)
                    .onChange(of: maintenanceMode) { enabled in setMaintenance(enabled) }
                Picker(JL("توفير الطاقة", "Power saving"), selection: $powerSaveMode) {
                    Text(JL("إلغاء", "Cancel")).tag(0)
                    Text(JL("يدوي", "Manual")).tag(1)
                    Text(JL("تلقائي", "Automatic")).tag(2)
                }
                .pickerStyle(.segmented)
                if powerSaveMode == 2 {
                    settingSlider(JL("بدء التوفير بعد", "Start saving after"), value: $powerSaveIdleMinutes, range: 1...720, suffix: JL("دقيقة", "minutes"))
                }
                Button(JL("حفظ وضع الطاقة", "Save power mode"), systemImage: "battery.75percent") { savePowerMode() }
                    .disabled(deviceID == nil)
                Button(JL("إضافة بطاقة NFC الآن", "Add NFC card now"), systemImage: "wave.3.right.circle.fill") { send(.nfcEnroll) }
                    .disabled(deviceID == nil)
                Button(JL("حذف بطاقة NFC", "Delete NFC card"), systemImage: "trash") { send(.nfcForget) }
                    .disabled(deviceID == nil)
            }
            Section(JL("تحديث Firmware", "Firmware update")) {
                Button(JL("اختيار ملف firmware.bin من الآيفون", "Choose firmware.bin from iPhone"), systemImage: "doc.badge.plus") {
                    showingFirmwareImporter = true
                }
                if !updateStatus.isEmpty {
                    Text(updateStatus)
                        .font(.footnote)
                        .foregroundStyle(selectedFirmwareData == nil ? .orange : .green)
                }
                if !selectedFirmwareName.isEmpty {
                    Text("\(selectedFirmwareName) · \(selectedFirmwareBytes) bytes")
                    Text("SHA-256: \(selectedFirmwareSHA256)")
                        .font(.caption2)
                        .textSelection(.enabled)
                        .font(.footnote)
                    Text(JL("تم اختيار الملف فقط. النقل المباشر عبر MQTT يحتاج دعم استقبال OTA بالفيرموير قبل تفعيل الإرسال.", "File selected only. MQTT OTA streaming requires ESP firmware receiver support before transmission can be enabled."))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Button(JL("إرسال الملف عبر الإنترنت MQTT", "Send file over Internet MQTT"), systemImage: "arrow.up.doc") {
                    guard let data = selectedFirmwareData, let deviceID else { return }
                    updateStatus = mqtt.beginFirmwareTransfer(data, to: deviceID)
                        ? JL("تم إرسال طلب بدء OTA؛ بانتظار موافقة ESP", "OTA negotiation sent; waiting for ESP approval")
                        : mqtt.firmwareTransferStatus
                }
                .disabled(deviceID == nil || selectedFirmwareData == nil || mqtt.firmwareTransferBusy || mqtt.connection != .connected)
                if mqtt.firmwareTransferBusy {
                    ProgressView(value: mqtt.firmwareTransferProgress)
                    Button(JL("إلغاء النقل", "Cancel transfer"), role: .cancel) {
                        mqtt.cancelFirmwareTransfer()
                    }
                }
                if !mqtt.firmwareTransferStatus.isEmpty {
                    Text(mqtt.firmwareTransferStatus).font(.footnote)
                }
                TextField(JL("رابط HTTPS لملف firmware.bin", "HTTPS URL for firmware.bin"), text: $firmwareURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button(JL("تحديث عبر 4G من الرابط", "Update via 4G from URL"), systemImage: "antenna.radiowaves.left.and.right") {
                    updateThrough4G()
                }
                .disabled(deviceID == nil || !isValidFirmwareURL)
                Text(JL("يقبل رابط HTTPS مباشر أو رابط Cloudflare R2 موقّع بعد firmware.bin. إرسال الرابط لا يعني نجاح التنزيل أو التثبيت.", "The update URL must provide a directly downloadable firmware.bin. ESP downloads it through its cellular connection, then restarts."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text(JL("الإعدادات تحفظ داخل ESP، لذلك تبقى بعد فصل الكهرباء ولا تحتاج كمبيوتر.", "Settings are stored on ESP and remain after power loss. No computer is required."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $showingFirmwareImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectedFirmwareData = nil
                selectedFirmwareName = ""
                selectedFirmwareBytes = 0
                selectedFirmwareSHA256 = ""
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                guard url.pathExtension.lowercased() == "bin" else {
                    updateStatus = JL("اختار ملف BIN الخاص بالـESP", "Select an ESP firmware .bin file")
                    return
                }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    let count = values.fileSize ?? 0
                    guard (262_144...3_145_728).contains(count) else {
                        updateStatus = JL("حجم الفيرموير خارج الحدود المتوقعة", "Firmware size outside expected range")
                        return
                    }
                    let firmwareData = try Data(contentsOf: url)
                    guard count == 0 || firmwareData.count == count else {
                        updateStatus = JL("حجم الملف غير متطابق", "Firmware size mismatch")
                        return
                    }
                    guard firmwareData.first == 0xE9 else {
                        updateStatus = JL("ملف BIN ليس فيرموير ESP32 صالح", "Invalid ESP32 firmware BIN")
                        return
                    }
                    selectedFirmwareSHA256 = SHA256.hash(data: firmwareData).map { String(format: "%02x", $0) }.joined()
                    selectedFirmwareData = firmwareData
                    selectedFirmwareName = url.lastPathComponent
                    selectedFirmwareBytes = firmwareData.count
                    updateStatus = JL("تم اختيار الملف؛ جاهز لطلب النقل عبر MQTT عند اتصال ESP", "Firmware selected; ready to negotiate MQTT transfer when ESP is online")
                } catch {
                    updateStatus = JL("تعذر قراءة الملف", "Could not read selected file")
                }
            case .failure:
                updateStatus = JL("تعذر اختيار الملف", "Could not select file")
            }
        }
        .onAppear { loadSettings(); syncTempWarning() }
        .onChange(of: vehicle.espTempWarningC) { _ in syncTempWarning() }
    }

    private func captureDiagnostics() {
        guard let deviceID else { return }
        let v = mqtt.state(for: deviceID)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let value: (Bool) -> String = { $0 ? "YES" : "NO" }
        let report: [String] = [
            "JOURNEY ESP TELEMETRY DIAGNOSTICS",
            "Captured: \(stamp)",
            "Device: \(deviceID)",
            "NOTE: Latest received telemetry, NOT raw ESP serial output.",
            "",
            "[CONNECTIVITY]",
            "BLE: \(mqtt.bluetoothStatus)",
            "MQTT: \(mqtt.connection.title)",
            "Telemetry source: MQTT ONLY (BLE local controls/events)",
            "Last cloud telemetry age: \(mqtt.cloudTelemetryAge(for: deviceID).map { String(format: "%.1f seconds", $0) } ?? "NEVER RECEIVED")",
            "ESP online: \(value(v.online))",
            "Cloud connected: \(value(v.cloudConnected))",
            "Internet route: \(v.internetRoute)",
            "Cellular enabled: \(value(v.cellularEnabled))",
            "Cellular registered: \(value(v.cellularRegistered))",
            "Cellular attached: \(value(v.cellularDataAttached))",
            "Cellular status: \(v.cellularStatus)",
            "Cellular network: \(v.cellularNetwork)",
            "Cellular signal: \(v.cellularSignalDBm) dBm",
            "BLE RSSI: \(v.bluetoothRSSI) dBm",
            "",
            "[ESP]",
            "Firmware: \(v.firmwareVersion)",
            "Uptime: \(v.uptimeSeconds) s",
            "Reset reason: \(v.espResetReason)",
            "Temperature: \(v.espTemperatureC.map { String(format: "%.2f C", $0) } ?? "N/A")",
            "Battery voltage: \(v.espBatteryVoltage.map { String(format: "%.2f V", $0) } ?? "N/A")",
            "Battery percent: \(v.espBatteryPercent.map { String(format: "%.1f%%", $0) } ?? "N/A")",
            "Thermal level: \(v.espThermalLevel)",
            "Sleeping: \(value(v.espSleeping))",
            "Remote powered: \(value(v.remotePowered))",
            "Owner state known: \(value(v.ownerStateKnown))",
            "Registered owner phones: \(v.authorizedPhoneCount)",
            "",
            "[OBD / CAN]",
            "Adapter: \(v.obdAdapterName)",
            "Connected: \(value(v.obdConnected))",
            "Status: \(v.obdStatus)",
            "CAN awake: \(value(v.canAwake))",
            "Ignition: \(v.ignitionState)",
            "Responses/s: \(v.obdResponseRate)",
            "Total responses: \(v.obdTotalResponses)",
            "Last reply: \(v.obdLastReply)",
            "Read diagnostics: \(v.readDiagnostics)",
            "RPM: \(v.rpm) (valid=\(value(v.rpmValid)))",
            "Speed: \(v.speedKph) km/h (valid=\(value(v.speedValid)))",
            "Coolant: \(v.coolantC) C (valid=\(value(v.coolantValid)))",
            "Vehicle battery: \(v.batteryVoltage) V",
            "Fuel: \(v.fuelLevelPercent)% (valid=\(value(v.fuelLevelValid)))",
            "DTC: \(v.diagnosticCodes.joined(separator: ", "))",
            "",
            "[BODY / EVENTS]",
            "Doors valid: \(value(v.doorsValid))",
            "Door known mask: \(v.doorKnownMask)",
            "Door open mask: \(v.doorOpenMask)",
            "Lights valid: \(value(v.lightsValid))",
            "Turns valid: \(value(v.turnsValid))",
            "Last event: \(v.lastEvent)",
            "Event type: \(v.vehicleEventType)",
            "Event text: \(v.vehicleEventText)",
            "",
            "[GPS]",
            "Valid: \(value(v.gpsValid))",
            "Coordinates: \(v.gpsValid ? "\(v.latitude), \(v.longitude)" : "N/A")"
        ]
        diagnosticReport = report.joined(separator: "\n")
        diagnosticMessage = JL("تم التقاط أحدث بيانات متوفرة. انسخ التقرير وأرسله للفحص.", "Latest available telemetry captured. Copy the report to share.")
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

    private func syncTempWarning() {
        guard let saved = vehicle.espTempWarningC else { return }
        if pendingTempWarning == saved {
            pendingTempWarning = nil
            tempWarningDirty = false
            tempSaveStatus = JL("أكد ESP حفظ حد التنبيه", "ESP confirmed the saved warning threshold")
        }
        if !tempWarningDirty && pendingTempWarning == nil { tempWarningC = Double(saved) }
    }

    private func saveTempWarning() {
        guard let deviceID, vehicle.online, vehicle.espTempWarningC != nil else { return }
        let target = Int(tempWarningC)
        let settings = ESPRuntimeSettings(espTempWarningC: target)
        guard mqtt.sendESPSettings(settings, to: deviceID) else {
            tempSaveStatus = JL("تعذر الإرسال؛ تحقق من الاتصال", "Could not send; check the connection")
            return
        }
        pendingTempWarning = target
        tempSaveStatus = JL("تم الإرسال؛ بانتظار تأكيد ESP", "Sent; waiting for ESP confirmation")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if pendingTempWarning == target {
                pendingTempWarning = nil
                tempSaveStatus = JL("لم يصل تأكيد؛ تحقق من الاتصال وأعد المحاولة", "No confirmation received; check the connection and retry")
            }
        }
    }

    private func saveSettings() {
        guard let deviceID else { return }
        let settings = ESPRuntimeSettings(remotePulseMs: Int(pulseMs), remoteWakeDelayMs: Int(wakeDelayMs), remotePowerOffDelayMs: Int(powerOffDelayMs), hudBrightness: Int(hudBrightness))
        updateStatus = mqtt.sendESPSettings(settings, to: deviceID) ? JL("تم إرسال الإعدادات إلى ESP", "Settings sent to ESP") : JL("تعذر إرسال الإعدادات", "Could not send settings")
    }

    private var isValidFirmwareURL: Bool {
        let trimmed = firmwareURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.path.lowercased().hasSuffix("/firmware.bin") else { return false }
        // Signed R2 links use query parameters after the .bin path.
        return true
    }

    private func updateThrough4G() {
        guard let deviceID else { return }
        guard isValidFirmwareURL else {
            updateStatus = JL("الرابط غير صالح: يجب أن يكون HTTPS ومساره firmware.bin", "Invalid URL: HTTPS and firmware.bin path required")
            return
        }
        updateStatus = mqtt.sendFirmwareURL(firmwareURL.trimmingCharacters(in: .whitespacesAndNewlines), to: deviceID)
            ? JL("تم إرسال أمر التحديث؛ انتظر تأكيد ESP قبل اعتبار التحديث ناجحاً", "OTA command sent; wait for ESP confirmation before treating update as successful")
            : JL("تعذر إرسال رابط التحديث", "Could not send update URL")
    }

    private func setMaintenance(_ enabled: Bool) {
        send(.maintenanceMode, maintenanceMode: enabled)
    }

    private func savePowerMode() {
        guard let deviceID else { return }
        let command = VehicleCommand(action: .powerSave, powerSave: PowerSaveSettings(mode: powerSaveMode, idleMinutes: Int(powerSaveIdleMinutes)))
        updateStatus = mqtt.sendESPCommand(command, to: deviceID) ? JL("تم حفظ وضع توفير الطاقة", "Power saving mode saved") : JL("تعذر حفظ وضع الطاقة", "Could not save power mode")
    }

    private func send(_ action: BenchAction, maintenanceMode: Bool? = nil) {
        guard let deviceID else { return }
        let command = VehicleCommand(action: action, maintenanceMode: maintenanceMode)
        updateStatus = mqtt.sendESPCommand(command, to: deviceID) ? JL("تم إرسال الأمر إلى ESP", "Command sent to ESP") : JL("تعذر إرسال الأمر", "Could not send command")
    }
}

private struct OBDStatusView: View {
    @EnvironmentObject private var mqtt: MQTTService
    let vehicle: VehicleState
    let deviceID: String?
    @StateObject private var faceID = FaceIDAuthenticator()
    @State private var clearConfirmation = false
    @State private var statusMessage = ""

    var body: some View {
        ZStack {
            JourneyWallpaperView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(
                        vehicle.obdConnected ? JL("OBD متصل", "OBD connected") : JL("بانتظار قطعة OBD", "Waiting for OBD adapter"),
                        systemImage: vehicle.obdConnected ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(vehicle.obdConnected ? .green : .orange)

                    Text(JL("ESP يرسل طلبات OBD القياسية للقراءة فقط عبر BLE؛ أوامر التحكم غير مستخدمة، ومسح الأخطاء لا يتم إلا بتأكيدك.", "ESP sends standard read-only OBD requests over BLE. Control commands are not used. Clearing codes requires your confirmation."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Group {
                        obdRow(JL("الحالة", "Status"), obdStatusArabic(vehicle.obdStatus))
                        obdRow(JL("الردود بالثانية", "Responses per second"), "\(vehicle.obdResponseRate)")
                        obdRow(JL("فحص PIDs", "PID scan"), vehicle.obdStandardScanComplete ? JL("اكتمل: \(vehicle.obdSupportedPids) مدعوم", "Complete: \(vehicle.obdSupportedPids) supported") : "\(vehicle.obdScanProgress)% — \(vehicle.obdScannedPids)/\(vehicle.obdSupportedPids)")
                        obdRow(JL("PID الحالي", "Current PID"), vehicle.obdCurrentPid.isEmpty ? "—" : vehicle.obdCurrentPid)
                        obdRow(JL("مجموع الردود", "Total responses"), "\(vehicle.obdTotalResponses)")
                        obdRow(JL("صلاحية المحرك", "Engine reading"), vehicle.rpmValid ? JL("صالحة", "Valid") : JL("غير متاحة", "Unavailable"))
                        obdRow(JL("الأبواب", "Doors"), vehicle.doorsValid ? (vehicle.simulatedDoorsOpen ? JL("مفتوحة", "Open") : JL("مغلقة", "Closed")) : "—")
                        obdRow(JL("الإضاءة", "Lights"), vehicle.lightsValid ? (vehicle.headlightsOn ? "ON" : "OFF") : "—")
                        obdRow(JL("الإشارات", "Turn signals"), vehicle.turnsValid ? "L:\(vehicle.leftSignalOn ? 1 : 0) R:\(vehicle.rightSignalOn ? 1 : 0)" : "—")
                        Text(vehicle.readDiagnostics).font(.caption.monospaced()).textSelection(.enabled)
                        obdRow("RPM", vehicle.rpmValid ? "\(vehicle.rpm)" : "—")
                        obdRow(JL("السرعة", "Speed"), !vehicle.speedValid ? "—" : UserDefaults.standard.string(forKey: "journey.settings.speedUnit") == "mph" ? "\(Int((Double(vehicle.speedKph) * 0.621371).rounded())) mph" : "\(vehicle.speedKph) km/h")
                        obdRow(JL("فولت البطارية", "Battery voltage"), vehicle.batteryVoltage > 0 ? String(format: "%.2f V", vehicle.batteryVoltage) : "—")
                        obdRow(JL("حالة السويتش / ACC", "Ignition / ACC status"), ignitionStateArabic(vehicle.ignitionState))
                        obdRow(JL("حالة CAN", "CAN status"), vehicle.canAwake ? JL("صاحي", "Awake") : JL("نايم / بانتظار الاستيقاظ", "Asleep / Waiting to wake"))
                        obdRow(JL("آخر رد", "Last response"), vehicle.obdLastReply.isEmpty ? "—" : vehicle.obdLastReply)
                    }
                    .padding(14)
                    .background(JourneyTheme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(JL("قطعة OBD المعتمدة", "Assigned OBD adapter")).font(.headline)
                        Text(JL("يتصل ESP مباشرة بقطعة KONNWEI المحفوظة تلقائياً، بدون بحث أو اختيار من التطبيق.",
                                "ESP automatically connects to its saved KONNWEI adapter. No app-side scanning or selection."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        obdRow(JL("القطعة", "Adapter"), vehicle.obdAdapterName.isEmpty ? "KONNWEI" : vehicle.obdAdapterName)
                        obdRow(JL("الاتصال", "Connection"), vehicle.obdConnected ? JL("متصل", "Connected") : JL("بانتظار الاتصال التلقائي", "Waiting for automatic connection"))
                    }
                    .padding(14)
                    .background(JourneyTheme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(JL("الأخطاء والتحليل", "Faults and analysis")).font(.headline)
                        obdRow(JL("الأكواد", "Codes"), vehicle.diagnosticCodes.isEmpty ? JL("لا توجد أكواد", "No codes") : vehicle.diagnosticCodes.joined(separator: ", "))
                        Text(JL("فحص الأكواد يدوي فقط؛ لا يوجد فحص دوري بالخلفية.", "Code scanning is manual only. There is no periodic background scan."))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(JL("فحص الأخطاء الآن", "Scan trouble codes now"), systemImage: "stethoscope") { scanTroubleCodes() }
                            .buttonStyle(.bordered)
                            .disabled(deviceID == nil)
                        Toggle(JL("أفهم أن المسح قد يطفي اللمبة مؤقتاً", "I understand clearing may temporarily turn off the warning lamp"), isOn: $clearConfirmation)
                            .font(.caption)
                        Button(vehicle.obdClearInProgress ? JL("جاري مسح الأخطاء…", "Clearing trouble codes…") : JL("مسح أخطاء السيارة", "Clear vehicle trouble codes"), systemImage: "trash.slash") {
                            clearTroubleCodes()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(deviceID == nil || !vehicle.rpmValid || vehicle.simulatedEngineRunning || !clearConfirmation || vehicle.obdClearInProgress)
                        if vehicle.simulatedEngineRunning {
                            Text(JL("أطفئ المحرك أولاً؛ المسح مقفول أثناء التشغيل.", "Stop the engine first. Clearing is blocked while running."))
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if !statusMessage.isEmpty { Text(JLStored(statusMessage)).font(.caption).foregroundStyle(JourneyTheme.accent) }
                    }
                    .padding(14)
                    .background(JourneyTheme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    Label(
                        JL("OBD القياسي يعطي سرعة وRPM وحرارة؛ الأبواب واللايتات والإشارات ليست ضمن PIDs القياسية.", "Standard OBD provides speed, RPM and temperature. Doors, lights and turn signals are not standard PIDs."),
                        systemImage: "info.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(JourneyTheme.accent)
                }
                .padding()
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
        .tint(JourneyTheme.accent)
    }

    private func scanTroubleCodes() {
        guard let deviceID else { return }
        let command = VehicleCommand(action: .obdScanDTC)
        statusMessage = mqtt.sendESPCommand(command, to: deviceID) ? JL("بدأ فحص أخطاء OBD.", "OBD trouble code scan started.") : JL("تعذر إرسال طلب فحص الأخطاء", "Could not send code scan request")
    }

    private func clearTroubleCodes() {
        guard let deviceID, clearConfirmation, !vehicle.simulatedEngineRunning else { return }
        Task {
            guard await faceID.authenticate(reason: JL("تأكيد مسح أخطاء OBD لسيارة JOURNEY", "Confirm clearing JOURNEY OBD trouble codes")) else {
                statusMessage = faceID.lastError ?? JL("لم يتم تأكيد Face ID", "Face ID was not confirmed")
                return
            }
            let command = VehicleCommand(action: .obdClearDTC, obdClearConfirmed: true)
            statusMessage = mqtt.sendESPCommand(command, to: deviceID) ? JL("أُرسل طلب المسح؛ سيتم فحص الأكواد من جديد.", "Clear request sent. Codes will be scanned again.") : JL("تعذر إرسال أمر المسح", "Could not send clear command")
        }
    }


    private func ignitionStateArabic(_ raw: String) -> String {
        switch raw {
        case "ENGINE_RUNNING": return JL("المحرك شغال", "Engine running")
        case "IGN_ON": return JL("IGN/ACC صاحي — المحرك طافي", "IGN/ACC awake — Engine off")
        case "OFF_OR_SLEEP": return JL("طافي / CAN نايم", "Off / CAN asleep")
        default: return JL("غير معروف", "Unknown")
        }
    }

    private func obdStatusArabic(_ raw: String) -> String {
        switch raw {
        case "waiting_for_saved_adapter", "waiting": return JL("بانتظار القطعة الأساسية", "Waiting for primary adapter")
        case "connecting_saved_adapter", "connecting": return JL("جاري الاتصال بـ KONNWEI", "Connecting to KONNWEI")
        case "initializing_elm327": return JL("تهيئة ELM327", "Initializing ELM327")
        case "connecting_ecu": return JL("الاتصال بكمبيوتر السيارة", "Connecting to vehicle ECU")
        case "reading_vin": return JL("قراءة رقم الشاصي VIN", "Reading VIN")
        case "scanning_supported_pids": return JL("فحص PIDs المدعومة", "Scanning supported PIDs")
        case "reading_standard_pids": return JL("قراءة بيانات السيارة", "Reading vehicle data")
        case "reading_dtc_stored": return JL("فحص الأخطاء المخزنة", "Scanning stored codes")
        case "reading_dtc_pending": return JL("فحص الأخطاء المعلقة", "Scanning pending codes")
        case "reading_dtc_permanent": return JL("فحص الأخطاء الدائمة", "Scanning permanent codes")
        case "dtc_scan_complete": return JL("اكتمل فحص الأخطاء", "Code scan complete")
        case "adapter_searching": return JL("بحث يدوي عن قطع BLE", "Manual BLE adapter search")
        case "adapter_search_complete": return JL("اكتمل البحث اليدوي", "Manual search complete")
        case "adapter_not_found": return JL("لم يتم العثور على القطعة", "Adapter not found")
        case "obd_waiting_reply": return JL("بانتظار رد OBD", "Waiting for OBD response")
        case "waiting_for_can": return JL("KONNWEI متصلة — بانتظار CAN", "KONNWEI connected — Waiting for CAN")
        case "probing_can": return JL("فحص استيقاظ CAN", "Checking CAN wake-up")
        case "can_awake_reading_vin": return JL("CAN اشتغل — قراءة VIN", "CAN awake — Reading VIN")
        case "obd_live": return JL("متصل — قراءة مباشرة", "Connected — Live readings")
        case "dtc_scan_requested": return JL("بدء فحص الأخطاء", "Starting code scan")
        case "obd_adapter_no_response_reconnecting", "obd_no_response_reconnecting": return JL("انقطع رد القطعة — إعادة اتصال", "Adapter stopped responding — Reconnecting")
        case "ecu_handshake_invalid": return JL("رد ECU غير صالح", "Invalid ECU response")
        case "vin_invalid_no_advance": return JL("VIN غير صالح — توقف الفحص", "Invalid VIN — Scan stopped")
        case "default_adapter_restored": return JL("KONNWEI هي القطعة الأساسية", "KONNWEI is the primary adapter")
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
                        .fill(index < bars ? color : JourneyTheme.ink.opacity(0.18))
                        .frame(width: 3, height: CGFloat(5 + index * 3))
                }
            }
            Text(bars == 0 ? "—" : "BLE")
                .font(.caption2.bold())
        }
        .foregroundStyle(color)
    }
}

struct VehicleMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mqtt: MQTTService
    let vehicle: VehicleState
    let vehicleName: String
    let deviceID: String?
    @State private var region: MKCoordinateRegion
    @State private var locationName = JL("بانتظار GPS", "Waiting for GPS")
    @State private var expandedMap = false

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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    mapCommandButton(JL("فتح", "Unlock"), icon: "lock.open.fill", tint: .green) { send(.unlock) }
                    mapCommandButton(JL("قفل", "Lock"), icon: "lock.fill", tint: .blue) { send(.lock) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                ZStack(alignment: .topLeading) {
                    Map(coordinateRegion: $region, annotationItems: points) { point in
                        MapAnnotation(coordinate: point.coordinate) {
                            VStack(spacing: 4) {
                                Image(systemName: "car.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(
                                        vehicle.online && vehicle.rpmValid
                                            ? (vehicle.simulatedEngineRunning ? Color.green : Color.yellow)
                                            : Color.gray,
                                        in: Circle()
                                    )
                                Text(vehicleName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.75), in: Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .simultaneousGesture(TapGesture().onEnded { expandedMap = true })

                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            vehicle.gpsValid ? JL("الموقع الحي", "Live location") : JL("بانتظار GPS", "Waiting for GPS"),
                            systemImage: vehicle.gpsValid ? "location.fill" : "location.slash.fill"
                        )
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.78), in: Capsule())

                        if vehicle.speedValid {
                            Text("\(vehicle.speedKph) كم/س")
                                .font(.caption.bold().monospacedDigit())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.78), in: Capsule())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                }
                .frame(height: max(geometry.size.height - 76, 250))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .overlay(alignment: .bottomTrailing) {
                    Button { expandedMap = true } label: {
                        Label(JL("تكبير الخريطة", "Expand map"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.bold())
                            .padding(11)
                            .background(.black.opacity(0.78), in: Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.black)
        .fullScreenCover(isPresented: $expandedMap) {
            NavigationStack {
                Map(coordinateRegion: $region, annotationItems: points) { point in
                    MapAnnotation(coordinate: point.coordinate) {
                        Image(systemName: "car.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(
                                vehicle.online && vehicle.rpmValid
                                    ? (vehicle.simulatedEngineRunning ? Color.green : Color.yellow)
                                    : Color.gray,
                                in: Circle()
                            )
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(JL("إغلاق", "Close")) { expandedMap = false }
                    }
                }
            }
        }
        .task(id: "\(vehicle.latitude),\(vehicle.longitude),\(vehicle.gpsValid)") {
            await resolveLocationName()
        }
    }

    @MainActor
    private func resolveLocationName() async {
        guard vehicle.gpsValid else {
            locationName = JL("بانتظار GPS", "Waiting for GPS")
            return
        }
        let location = CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = placemarks?.first else {
            locationName = JL("موقع السيارة الحالي", "Current vehicle location")
            return
        }
        let parts = [mark.name, mark.subLocality, mark.locality].compactMap { $0 }.filter { !$0.isEmpty }
        locationName = parts.isEmpty ? JL("موقع السيارة الحالي", "Current vehicle location") : Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: JL("، ", ", "))
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
            .foregroundStyle(active ? .cyan : JourneyTheme.ink.opacity(0.64))
            .background(active ? .cyan.opacity(0.13) : JourneyTheme.ink.opacity(0.055), in: Capsule())
    }
}

/// A live map preview replacing the old launcher and NFC management cards.
/// It uses the actual GPS coordinates as soon as the ESP publishes them, and
/// keeps a Basra Corniche preview while the receiver is waiting for a fix.
private struct VehicleMapEntryCard: View {
    let vehicle: VehicleState
    let openMap: () -> Void
    @State private var region: MKCoordinateRegion
    @State private var locationName = JL("بانتظار GPS", "Waiting for GPS")

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
                        .foregroundStyle(JourneyTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.48), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(JL("الخريطة والتعقّب", "Map and tracking"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(vehicle.gpsValid ? locationName : JL("بانتظار موقع السيارة من GPS", "Waiting for vehicle GPS location"))
                            .font(.caption)
                            .foregroundStyle(JourneyTheme.ink.opacity(0.76))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .foregroundStyle(JourneyTheme.ink.opacity(0.72))
                }
                .padding(14)
            }
            .frame(height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(.cyan.opacity(0.38), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(JL("الخريطة والتعقّب", "Map and tracking"))
        .task(id: "\(vehicle.latitude),\(vehicle.longitude),\(vehicle.gpsValid)") {
            await resolveLocationName()
        }
    }

    @MainActor
    private func resolveLocationName() async {
        guard vehicle.gpsValid else {
            locationName = JL("بانتظار GPS", "Waiting for GPS")
            return
        }
        let location = CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = placemarks?.first else {
            locationName = JL("موقع السيارة الحالي", "Current vehicle location")
            return
        }
        let parts = [mark.name, mark.subLocality, mark.locality].compactMap { $0 }.filter { !$0.isEmpty }
        locationName = parts.isEmpty ? JL("موقع السيارة الحالي", "Current vehicle location") : Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: JL("، ", ", "))
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
                    Toggle(JL("تفعيل الدخول الذكي", "Enable smart entry"), isOn: $enabled)
                        .tint(JourneyTheme.accent)
                    Text(JL("عند الاتصال الآمن بالـESP: يفتح عند الاقتراب ويقفل بعد الابتعاد.", "With a secure ESP connection, unlock on approach and lock after departure."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label(JL("مفتاح الآيفون", "iPhone key"), systemImage: "iphone.radiowaves.left.and.right")
                }

                Section(JL("مسافات تقريبية", "Approximate distances")) {
                    settingSlider(title: JL("مسافة الفتح", "Unlock distance"), value: $unlockDistance, range: 0.5...3.0, step: 0.5, tint: .green)
                    settingSlider(title: JL("مسافة القفل", "Lock distance"), value: $lockDistance, range: 2.0...8.0, step: 0.5, tint: .orange)
                    Text(JL("القفل مضبوط على \(String(format: "%.1f", effectiveLockDistance)) م أو أكثر حتى لا يفتح ويقفل بسرعة.", "Lock distance is set to \(String(format: "%.1f", effectiveLockDistance)) m or more to prevent rapid locking and unlocking."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(JL("ثبات الإشارة", "Signal stability")) {
                    settingSlider(title: JL("تثبيت القرب قبل الفتح", "Confirm proximity before unlock"), value: $unlockHold, range: 2.0...8.0, step: 1.0, suffix: JL(" ث", " s"), tint: .cyan)
                    settingSlider(title: JL("تأخير القفل بعد الابتعاد", "Lock delay after departure"), value: $lockDelay, range: 10.0...45.0, step: 5.0, suffix: JL(" ث", " s"), tint: .orange)
                }

                Section(JL("ريموت السيارة الاحتياطي", "Spare vehicle remote")) {
                    Toggle(JL("يبقى الريموت مفعّل أثناء وجود الآيفون", "Keep remote powered while iPhone is nearby"), isOn: $keepRemotePowered)
                        .tint(JourneyTheme.accent)
                    Text(JL("عند الاقتراب: ESP يشغّل 3.3V للريموت، ينتظر ثانية، ثم ينفذ الفتح. عند الابتعاد: يقفل أولاً، ينتظر ثانيتين، ثم يفصل تغذية الريموت.", "On approach, ESP supplies 3.3V to the remote, waits one second, then unlocks. On departure, it locks first, waits two seconds, then cuts remote power."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Label(JL("يبقى مفتاح السيارة موجوداً أثناء وقوفك داخلها، فلا ينفصل الريموت مباشرة بعد الفتح.", "The vehicle key remains available while you are inside. Remote power is not cut immediately after unlocking."), systemImage: "key.fill")
                        .font(.footnote)
                        .foregroundStyle(JourneyTheme.accent)
                }

                Section {
                    Label(JL("المسافة تقديرية لأن BLE تقيس قوة الإشارة، وتتأثر بالجدران ومكان الهاتف. فعّلها بعد اختبارها حول السيارة.", "Distance is approximate because BLE measures signal strength and is affected by walls and phone placement. Enable after testing around the vehicle."), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle(JL("الدخول الذكي", "Smart entry"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(JL("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(JL("حفظ وإرسال", "Save and send")) { save() }
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
        suffix: String = JL(" م", " m"),
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(JL("\(String(format: suffix == " م" ? "%.1f" : "%.0f", value.wrappedValue))\(suffix)", "\(String(format: suffix == " م" ? "%.1f" : "%.0f", value.wrappedValue))\(suffix)"))
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
    @State private var cellularEnabled = false
    @State private var cellularAPN = "internet"
    @State private var cellularUsername = ""
    @State private var cellularPassword = ""
    @State private var cellularSimPin = ""
    @State private var cellularMessage: String?

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
    @AppStorage("journey.demo.enabled") private var demoEnabled = false

    private func tr(_ ar: String, _ en: String) -> String { language == "en" ? en : ar }

    private var selectedDeviceID: String? { devices.selectedDevice?.deviceID }
    private var vehicle: VehicleState {
        guard let id = selectedDeviceID else { return VehicleState() }
        return mqtt.state(for: id)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr(JL("المظهر", "Appearance"), "Appearance"), selection: $appearance) {
                        Text(tr(JL("داكن", "Dark"), "Dark")).tag("dark")
                        Text(tr(JL("فاتح", "Light"), "Light")).tag("light")
                        Text(tr(JL("حسب النظام", "System"), "System")).tag("system")
                    }
                    Picker(tr(JL("حجم الخط", "Text size"), "Text size"), selection: $textSize) {
                        Text(tr(JL("صغير", "Small"), "Small")).tag("small")
                        Text(tr(JL("عادي", "Normal"), "Normal")).tag("normal")
                        Text(tr(JL("كبير", "Large"), "Large")).tag("large")
                        Text(tr(JL("أكبر", "Extra large"), "Extra large")).tag("xlarge")
                    }
                    Picker(tr(JL("اللغة", "Language"), "Language"), selection: $language) {
                        Text(tr(JL("العربية", "العربية"), "Arabic")).tag("ar")
                        Text("English").tag("en")
                    }
                } header: {
                    Label(tr(JL("المظهر واللغة", "Appearance and language"), "Appearance & Language"), systemImage: "paintbrush.pointed.fill")
                }

                Section {
                    Toggle(JL("وضع الديمو (بدون أوامر حقيقية)", "Demo mode (no real commands)"), isOn: $demoEnabled)
                        .tint(.orange)
                    Text(JL("يعرض لوحة فحص منفصلة للأبواب والإنارة والمحرك. ما يرسل أي أمر للـESP أو السيارة.", "Shows an isolated test panel for doors, lights and engine. Never sends commands to ESP or vehicle."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label(JL("فحص الديمو", "Demo testing"), systemImage: "testtube.2")
                }
                JourneyCarAppearanceSettingsSection()
                JourneyWallpaperSettingsSection()
                JourneyWidgetSettingsSection()

                Section {
                    Picker(tr(JL("وحدة السرعة", "Speed unit"), "Speed unit"), selection: $speedUnit) {
                        Text("km/h").tag("kmh")
                        Text("mph").tag("mph")
                    }
                    Picker(tr(JL("درجة الحرارة", "Temperature"), "Temperature"), selection: $temperatureUnit) {
                        Text("°C").tag("c")
                        Text("°F").tag("f")
                    }
                    Text(language == "en" ? "Battery voltage is read automatically by the ESP firmware; there is no fake local switch." : JL("فولت البطارية يُقرأ تلقائياً من Firmware الـESP؛ ماكو مفتاح محلي وهمي.", "Battery voltage is read automatically by ESP firmware. There is no simulated local switch."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label(tr(JL("السيارة والقراءات", "Vehicle and readings"), "Vehicle & Readings"), systemImage: "car.fill")
                }

                Section {
                    Toggle(tr(JL("تشغيل وإطفاء المحرك", "Engine start and stop"), "Engine start/stop"), isOn: $notifyEngine)
                    Toggle(tr(JL("الاقتراب والابتعاد", "Approach and departure"), "Approach/departure"), isOn: $notifyKeyless)
                    Toggle(tr(JL("القفل والفتح", "Lock and unlock"), "Lock/unlock"), isOn: $notifyLocks)
                    Toggle(tr(JL("حالة OBD", "OBD status"), "OBD status"), isOn: $notifyOBD)
                    Label(JL("مضافة حماية من إشعار إطفاء كاذب أثناء الحركة ومن تكرار إشعار الاقتراب.", "Includes protection against false engine-off notifications while moving and repeated approach notifications."), systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } header: {
                    Label(tr(JL("الإشعارات", "Notifications"), "Notifications"), systemImage: "bell.badge.fill")
                }

                Section {
                    Toggle(JL("تشغيل الشريحة / 4G", "Enable cellular / 4G"), isOn: $cellularEnabled)
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
                        LabeledContent(JL("قوة الإشارة", "Signal strength"), value: "\(vehicle.cellularSignalDBm) dBm")
                    }
                    LabeledContent(JL("تسجيل الشبكة", "Network registration"), value: vehicle.cellularRegistered ? JL("مسجل", "Registered") : JL("غير مسجل", "Not registered"))
                    LabeledContent(JL("بيانات الإنترنت", "Internet data"), value: vehicle.cellularDataAttached ? JL("متصلة", "Connected") : JL("غير متصلة", "Disconnected"))
                    LabeledContent(JL("مسار الإنترنت", "Internet route"), value: vehicle.internetRoute == "CELLULAR" ? JL("الشريحة", "Cellular") : JL("غير متصل", "Disconnected"))
                        .foregroundStyle(vehicle.internetRoute == "CELLULAR" ? .green : .secondary)

                    TextField("APN", text: $cellularAPN)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(JL("اسم مستخدم APN - اختياري", "APN username — Optional"), text: $cellularUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(JL("كلمة مرور APN - اختيارية", "APN password — Optional"), text: $cellularPassword)
                    SecureField(JL("SIM PIN - إذا الشريحة تحتاجه", "SIM PIN — If required"), text: $cellularSimPin)
                        .keyboardType(.numberPad)

                    HStack {
                        Button {
                            saveCellular()
                        } label: {
                            Label(JL("حفظ واتصال", "Save and connect"), systemImage: "simcard.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!cellularEnabled || cellularAPN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDeviceID == nil)

                        Spacer()

                        Button {
                            testCellular()
                        } label: {
                            Label(JL("فحص", "Test"), systemImage: "waveform.path.ecg")
                        }
                        .disabled(selectedDeviceID == nil)
                    }

                    Button(role: .destructive) {
                        forgetCellular()
                    } label: {
                        Label(JL("مسح إعدادات الشريحة", "Clear cellular settings"), systemImage: "trash")
                    }
                    .disabled(selectedDeviceID == nil)

                    if let cellularMessage {
                        Text(JLStored(cellularMessage))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text(JL("الـAPN الافتراضي مضبوط على internet. اسم المستخدم وكلمة المرور وSIM PIN اختيارية حسب شركة الشريحة.", "Default APN is internet. Username, password and SIM PIN are optional depending on the carrier."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label(JL("الشريحة والـ4G", "Cellular and 4G"), systemImage: "simcard.fill")
                }

                Section {
                    Toggle(tr(JL("وضع المطور", "Developer mode"), "Developer Mode"), isOn: $developerMode)
                    if developerMode {
                        LabeledContent(JL("حالة BLE", "BLE status"), value: JLStored(mqtt.bluetoothStatus))
                        LabeledContent("MQTT", value: mqtt.connection.title)
                        Text(JL("وضع المطور للـLogs وCAN/OBD والفحص، ولا يغيّر مخارج السيارة وحده.", "Developer mode shows logs and CAN/OBD diagnostics. It does not change vehicle outputs by itself."))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Label(JL("التشخيص وCAN", "Diagnostics and CAN"), systemImage: "waveform.path.ecg.rectangle.fill")
                }

                Section(JL("اتصال MQTT المشفّر", "Encrypted MQTT connection")) {
                    TextField(JL("عنوان السيرفر", "Server address"), text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(JL("المنفذ", "Port"), text: $port)
                        .keyboardType(.numberPad)
                    TextField(JL("اسم المستخدم", "Username"), text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(JL("كلمة المرور", "Password"), text: $password)
                    Label(JL("TLS فقط، وكلمة المرور محفوظة في Keychain داخل الآيفون.", "TLS only. The password is stored in the iPhone Keychain."), systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink {
                        SettingsAboutView()
                    } label: {
                        Label(JL("النظام والتحديث", "System and updates"), systemImage: "gearshape.2.fill")
                    }
                }

                if let errorText {
                    Section { Text(JLStored(errorText)).foregroundStyle(.red) }
                }
            }
            .navigationTitle(JL("الإعدادات", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(JL("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(JL("حفظ", "Save")) { save() }
                }
            }
            .onAppear {
                let saved = mqtt.settings
                host = saved.host
                port = String(saved.port)
                username = saved.username
                password = saved.password
                cellularEnabled = vehicle.cellularEnabled
                if !vehicle.cellularAPN.isEmpty { cellularAPN = vehicle.cellularAPN }
            }
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
            hotspotEnabled: false,
            hotspotSSID: "",
            hotspotPassword: ""
        )
        _ = mqtt.sendESPCommand(VehicleCommand(action: .cellularConfig, cellularSettings: settings), to: id)
        cellularMessage = enabled ? JL("تم إرسال أمر تشغيل الشريحة", "Cellular enable command sent") : JL("تم إرسال أمر إطفاء بيانات الشريحة", "Cellular data disable command sent")
    }

    private func saveCellular() {
        let apn = cellularAPN.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apn.isEmpty else {
            cellularMessage = JL("أدخل APN", "Enter APN")
            return
        }
        guard let id = selectedDeviceID else {
            cellularMessage = JL("ماكو ESP محدد", "No ESP selected")
            return
        }
        cellularEnabled = true
        let settings = ESPCellularSettings(
            enabled: true,
            apn: apn,
            username: cellularUsername,
            password: cellularPassword,
            simPin: cellularSimPin,
            hotspotEnabled: false,
            hotspotSSID: "",
            hotspotPassword: ""
        )
        _ = mqtt.sendESPCommand(VehicleCommand(action: .cellularConfig, cellularSettings: settings), to: id)
        cellularMessage = JL("تم حفظ إعدادات الشريحة وجاري الفحص", "Cellular settings saved; checking connection")
    }

    private func testCellular() {
        guard let id = selectedDeviceID else { return }
        _ = mqtt.sendESPCommand(VehicleCommand(action: .cellularTest), to: id)
        cellularMessage = JL("جاري فحص الشريحة والشبكة", "Checking modem and network")
    }

    private func forgetCellular() {
        guard let id = selectedDeviceID else { return }
        _ = mqtt.sendESPCommand(VehicleCommand(action: .cellularForget), to: id)
        cellularEnabled = false
        cellularAPN = "internet"
        cellularUsername = ""
        cellularPassword = ""
        cellularSimPin = ""
        cellularMessage = JL("تم إرسال أمر مسح إعدادات الشريحة", "Clear cellular settings command sent")
    }

    private func cellularStatusText(_ status: String) -> String {
        switch status {
        case "ready": return JL("الشريحة جاهزة", "Modem ready")
        case "registered": return JL("مسجلة على الشبكة", "Registered on network")
        case "data_attached": return JL("الإنترنت متصل", "Internet connected")
        case "checking": return JL("جاري الفحص", "Checking")
        case "pin_required": return JL("تحتاج SIM PIN", "SIM PIN required")
        case "sim_missing": return JL("الشريحة غير موجودة", "SIM missing")
        case "registration_failed": return JL("فشل تسجيل الشبكة", "Network registration failed")
        case "data_failed": return JL("فشل اتصال البيانات", "Data connection failed")
        case "disabled": return JL("الشريحة مطفأة", "Cellular off")
        default: return JL("بانتظار الفحص", "Waiting for check")
        }
    }

    private func save() {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHost.isEmpty {
            dismiss()
            return
        }
        guard let value = UInt16(port), value > 0 else {
            errorText = JL("رقم المنفذ غير صحيح", "Invalid port number")
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
                LabeledContent(JL("إصدار التطبيق", "App version"), value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                LabeledContent(JL("Firmware المطلوب", "Required firmware"), value: "v12.76")
            }
            Section(JL("التحديث", "Updates")) {
                Label(JL("تحديث ESP عبر OTA يبقى من صفحة الفحص/الصيانة.", "ESP OTA updates are available on the diagnostics and maintenance page."), systemImage: "arrow.triangle.2.circlepath")
                Label(JL("إعدادات الواجهة تُحفظ محلياً وتبقى بعد إعادة تشغيل التطبيق.", "Interface settings are saved locally and remain after restarting the app."), systemImage: "internaldrive.fill")
            }
        }
        .navigationTitle(JL("النظام والتحديث", "System and updates"))
    }
}

#Preview {
    ContentView()
        .environmentObject(MQTTService())
        .environmentObject(ProximityMonitor())
        .environmentObject(DeviceStore())
}


// This home-screen simulator deliberately owns only local AppStorage values.
// No live ESP, MQTT, NFC or vehicle commands are triggered by these controls.
private struct JourneyIsolatedDemoView: View {
    @EnvironmentObject private var mqtt: MQTTService
    @EnvironmentObject private var devices: DeviceStore
    @State private var showingSettings = false
    @AppStorage("journey.demo.enabled") private var enabled = false
    @AppStorage("journey.demo.locked") private var locked = true
    @AppStorage("journey.demo.engine") private var engine = false
    @AppStorage("journey.demo.driverDoor") private var driverDoor = false
    @AppStorage("journey.demo.passengerDoor") private var passengerDoor = false
    @AppStorage("journey.demo.rearDriverDoor") private var rearDriverDoor = false
    @AppStorage("journey.demo.rearPassengerDoor") private var rearPassengerDoor = false
    @AppStorage("journey.demo.trunk") private var trunk = false
    @AppStorage("journey.demo.hood") private var hood = false
    @AppStorage("journey.demo.leftTurn") private var leftTurn = false
    @AppStorage("journey.demo.rightTurn") private var rightTurn = false
    @AppStorage("journey.demo.headlights") private var headlights = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    // Existing full-front car artwork is driven by these synthetic readings.
    // The normal vehicle state never participates in the demo visualisation.
    private var visualState: VehicleState {
        var state = VehicleState()
        state.online = true
        state.simulatedLocked = locked
        state.simulatedEngineRunning = engine
        state.rpmValid = true
        state.rpm = engine ? 850 : 0
        state.doorsValid = true
        state.doorKnownMask = 0x7E
        if driverDoor { state.doorOpenMask |= 0x02 }
        if passengerDoor { state.doorOpenMask |= 0x04 }
        if rearDriverDoor { state.doorOpenMask |= 0x08 }
        if rearPassengerDoor { state.doorOpenMask |= 0x10 }
        if hood { state.doorOpenMask |= 0x20 }
        if trunk { state.doorOpenMask |= 0x40 }
        state.lightsValid = true
        state.headlightsOn = headlights
        state.parkingLightsValid = true
        state.parkingLightsOn = headlights
        state.turnsValid = true
        state.leftSignalOn = leftTurn
        state.rightSignalOn = rightTurn
        return state
    }

    // A single change observer refreshes the widget for all demo controls.
    private var visualKey: String {
        [locked, engine, driverDoor, passengerDoor, rearDriverDoor,
         rearPassengerDoor, trunk, hood, leftTurn, rightTurn, headlights]
            .map { $0 ? "1" : "0" }.joined()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JOURNEY")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .tracking(3)
                    Text(JL("المحاكاة على الشاشة الرئيسية", "Home screen simulator"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("DEMO", systemImage: "testtube.2")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.orange.opacity(0.12), in: Capsule())
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(JL("إعدادات JOURNEY", "JOURNEY settings"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(JourneyTheme.surface.opacity(0.95))

            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        CarVisualView(
                            state: visualState,
                            demoDriverRearOpen: rearDriverDoor,
                            demoHoodOpen: hood
                        )
                        .padding(.horizontal, -9)
                        .animation(.easeInOut(duration: 0.18), value: visualKey)

                        HStack(spacing: 8) {
                            stateChip(
                                locked ? JL("مقفلة", "Locked") : JL("مفتوحة", "Unlocked"),
                                icon: locked ? "lock.fill" : "lock.open.fill",
                                active: !locked
                            )
                            stateChip(
                                engine ? JL("المحرك يعمل", "Engine running") : JL("المحرك مطفأ", "Engine off"),
                                icon: "engine.combustion.fill",
                                active: engine
                            )
                        }
                    }

                    VStack(spacing: 10) {
                        Text(JL("التحكم التجريبي", "Demo controls"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            actionButton(JL("فتح القفل", "Unlock"), icon: "lock.open.fill", active: !locked) {
                                locked = false
                            }
                            actionButton(JL("قفل", "Lock"), icon: "lock.fill", active: locked) {
                                locked = true
                            }
                            actionButton(engine ? JL("إطفاء", "Stop") : JL("تشغيل", "Start"),
                                         icon: "engine.combustion.fill", active: engine) {
                                engine.toggle()
                            }
                        }

                        Text(JL("الأبواب والصندوق", "Doors and liftgate"))
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVGrid(columns: columns, spacing: 8) {
                            toggleButton(JL("باب السائق", "Driver"), icon: "car.side", value: $driverDoor)
                            toggleButton(JL("باب الراكب", "Passenger"), icon: "car.side", value: $passengerDoor)
                            toggleButton(JL("خلف السائق", "Rear driver"), icon: "car.side", value: $rearDriverDoor)
                            toggleButton(JL("خلف الراكب", "Rear passenger"), icon: "car.side", value: $rearPassengerDoor)
                            toggleButton(JL("الصندوق", "Liftgate"), icon: "shippingbox", value: $trunk)
                            toggleButton(JL("البنيد", "Hood"), icon: "wrench.adjustable", value: $hood)
                        }

                        Text(JL("الإضاءة والإشارات", "Lights and signals"))
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVGrid(columns: columns, spacing: 8) {
                            toggleButton(JL("الأيت والبروجكتر", "Lights"), icon: "lightbulb.fill", value: $headlights)
                            toggleButton(JL("إشارة يسار", "Left turn"), icon: "arrow.turn.up.left", value: $leftTurn)
                            toggleButton(JL("إشارة يمين", "Right turn"), icon: "arrow.turn.up.right", value: $rightTurn)
                            actionButton(JL("فلشر", "Hazards"), icon: "hazardsign.fill",
                                         active: leftTurn && rightTurn) {
                                let newValue = !(leftTurn && rightTurn)
                                leftTurn = newValue
                                rightTurn = newValue
                            }
                        }
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

                    Label(
                        JL("وضع تجربة فقط: صورة السيارة تتغير، ولا تنرسل أي أوامر للـ ESP.", "Simulation only: the car image reacts without sending commands to the ESP."),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    Button {
                        enabled = false
                    } label: {
                        Label(JL("رجوع للوضع الرسمي", "Return to live mode"), systemImage: "arrow.uturn.backward.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(.horizontal, 14)
                .padding(.top, 7)
                .padding(.bottom, 20)
            }
        }
        .onAppear { mqtt.syncSelectedWidget(force: true) }
        .onChange(of: visualKey) { _, _ in
            mqtt.syncSelectedWidget(force: true)
        }
        .sheet(isPresented: $showingSettings) {
            MQTTSettingsView()
                .environmentObject(mqtt)
                .environmentObject(devices)
        }
    }

    private func stateChip(_ title: String, icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.bold())
            .foregroundStyle(active ? .cyan : JourneyTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(JourneyTheme.surface.opacity(0.85), in: Capsule())
    }

    private func toggleButton(_ title: String, icon: String, value: Binding<Bool>) -> some View {
        actionButton(title, icon: icon, active: value.wrappedValue) {
            value.wrappedValue.toggle()
        }
    }

    private func actionButton(_ title: String, icon: String, active: Bool,
                              action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { action() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(active ? JL("شغّال", "ON") : JL("مطفأ", "OFF"))
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(active ? Color.cyan : JourneyTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 69)
            .padding(.horizontal, 4)
            .background(active ? Color.cyan.opacity(0.18) : JourneyTheme.surface.opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13)
                .stroke(active ? Color.cyan.opacity(0.6) : JourneyTheme.ink.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
