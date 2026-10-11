import Foundation
import SwiftUI
import WatchConnectivity

/// Watch-side status and commands. The paired iPhone owns ESP authorization;
/// the watch never makes a direct BLE/MQTT connection to the vehicle.
@MainActor
final class JourneyWatchConnection: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var vehicle = JourneyWatchStatus()
    @Published private(set) var reachable = false
    @Published private(set) var busy = false
    @Published private(set) var message = "بانتظار JOURNEY على الآيفون"

    private let session = WCSession.default
    private let cachedKey = "journey.watch.lastVehicleStatus"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cachedKey),
           let status = try? JSONDecoder().decode(JourneyWatchStatus.self, from: data) {
            vehicle = status
        }
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else {
            message = "Apple Watch غير مدعومة"
            return
        }
        session.delegate = self
        if session.activationState == .notActivated {
            session.activate()
        } else {
            reachable = session.isReachable
            if let data = session.receivedApplicationContext["journey.status"] as? Data {
                accept(data)
            }
        }
    }

    func refresh() {
        guard session.activationState == .activated, session.isReachable else {
            reachable = false
            message = "افتح JOURNEY على الآيفون لتحديث البيانات"
            return
        }
        session.sendMessage(["type": "refresh"], replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.message = reply["message"] as? String ?? "انطلب التحديث"
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.message = "تعذر التحديث؛ تأكد من اتصال الآيفون" }
        })
    }

    func command(_ action: String) {
        guard ["lock", "unlock", "start"].contains(action) else { return }
        // Start only notifies the iPhone to request a fresh Face ID.
        // The watch itself never authorizes or sends a remote-start frame.
        guard !busy else { return }
        guard session.activationState == .activated, session.isReachable else {
            message = "الآيفون غير متاح حالياً؛ ما انرسل أي أمر"
            return
        }
        guard !vehicle.deviceID.isEmpty else {
            message = "اختَر سيارة في JOURNEY أولاً"
            return
        }

        busy = true
        message = action == "lock" ? "جاري طلب القفل..." :
            (action == "unlock" ? "جاري طلب الفتح..." : "جاري إرسال طلب Face ID للآيفون...")
        session.sendMessage([
            "type": "command",
            "action": action,
            "deviceID": vehicle.deviceID
        ], replyHandler: { [weak self] reply in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.message = reply["message"] as? String ?? "تم استلام الرد"
                // Wait for the authoritative snapshot; a successful message
                // delivery does NOT prove the real vehicle locked/unlocked.
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.busy = false
                self?.message = "ما وصل الأمر للآيفون؛ لم يتأكد تنفيذه"
            }
        })
    }

    private func accept(_ data: Data) {
        guard let status = try? JSONDecoder().decode(JourneyWatchStatus.self, from: data) else { return }
        vehicle = status
        UserDefaults.standard.set(data, forKey: cachedKey)
        message = status.demoMode ? "وضع الديمو — بدون أوامر حقيقية" :
            (status.fresh() ? "بيانات من الآيفون" : "آخر بيانات معروفة")
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if let data = session.receivedApplicationContext["journey.status"] as? Data {
                self.accept(data)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if self.reachable { self.refresh() }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["journey.status"] as? Data else { return }
        Task { @MainActor in self.accept(data) }
    }
}

@main
struct JourneyWatchApp: App {
    @StateObject private var connection = JourneyWatchConnection()

    var body: some Scene {
        WindowGroup {
            JourneyWatchHome()
                .environmentObject(connection)
        }
    }
}

private struct JourneyWatchHome: View {
    @EnvironmentObject private var bridge: JourneyWatchConnection

    private var vehicle: JourneyWatchStatus { bridge.vehicle }
    private var live: Bool { vehicle.fresh() }
    private var cyan: Color { Color(red: 0.19, green: 0.83, blue: 0.99) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(cyan)
                    Text("JOURNEY")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                    Spacer(minLength: 1)
                    if vehicle.demoMode {
                        Text("DEMO")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.orange)
                    } else {
                        Circle()
                            .fill(live ? .green : .orange)
                            .frame(width: 7, height: 7)
                    }
                }

                Image(systemName: "car.front.waves.up.fill")
                    .font(.system(size: 43, weight: .ultraLight))
                    .foregroundStyle(cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)

                Text(vehicle.vehicleName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    statusTile(
                        vehicle.locked.map { $0 ? "مقفلة" : "مفتوحة" } ?? "—",
                        caption: "القفل",
                        symbol: vehicle.locked == true ? "lock.fill" : "lock.open.fill"
                    )
                    statusTile(
                        vehicle.running.map { $0 ? "شغال" : "مطفأ" } ?? "—",
                        caption: "المحرك", symbol: "engine.combustion.fill"
                    )
                }

                HStack(spacing: 6) {
                    statusTile("\(vehicle.openDoorCount)", caption: "أبواب مفتوحة", symbol: "door.left.hand.open")
                    statusTile(vehicle.rpm.map(String.init) ?? "—", caption: "RPM", symbol: "gauge.with.dots.needle.67percent")
                }

                HStack(spacing: 5) {
                    Button { bridge.command("unlock") } label: {
                        Label("فتح", systemImage: "lock.open.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(cyan)
                    Button { bridge.command("lock") } label: {
                        Label("قفل", systemImage: "lock.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.orange)
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 13, weight: .bold))
                .disabled(bridge.busy || !live || !bridge.reachable)

                Button { bridge.command("start") } label: {
                    Label("تشغيل — Face ID على الآيفون", systemImage: "engine.combustion.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(vehicle.headlights == true ? cyan : .gray)
                    Image(systemName: "arrow.turn.up.left")
                        .foregroundStyle(vehicle.leftTurn == true ? .orange : .gray)
                    Image(systemName: "arrow.turn.up.right")
                        .foregroundStyle(vehicle.rightTurn == true ? .orange : .gray)
                    Spacer(minLength: 0)
                    Button { bridge.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(cyan)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 6)

                Text(bridge.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
        .onAppear { bridge.activate() }
        .containerBackground(.black.gradient, for: .navigation)
    }

    private func statusTile(_ value: String, caption: String, symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(cyan)
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
    }
}
