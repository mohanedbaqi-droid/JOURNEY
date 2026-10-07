import SwiftUI
import WidgetKit

private struct JourneyWidgetEntry: TimelineEntry {
    let date: Date
    let vehicle: JourneyWidgetSnapshot
    let message: String?
}
private struct JourneyWidgetProvider: TimelineProvider {
    func entry(_ date: Date, _ snapshot: JourneyWidgetSnapshot) -> JourneyWidgetEntry {
        JourneyWidgetEntry(date: date, vehicle: snapshot.expired(at: date), message: JourneyWidgetStore.status(deviceID: snapshot.deviceID, at: date))
    }
    func placeholder(in context: Context) -> JourneyWidgetEntry { entry(Date(), JourneyWidgetSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (JourneyWidgetEntry) -> Void) {
        completion(entry(Date(), JourneyWidgetStore.read() ?? JourneyWidgetSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<JourneyWidgetEntry>) -> Void) {
        let now = Date(), snapshot = JourneyWidgetStore.read() ?? JourneyWidgetSnapshot()
        let deadlines = [(snapshot.obdAt, 5.1), (snapshot.bodyAt, 5.1), (snapshot.healthAt, 10.1), (snapshot.gpsAt, 12.1), (snapshot.stateAt, 12.1)]
        let dates = [now] + deadlines.compactMap { date, lifetime -> Date? in
            guard let date else { return nil }; let expiry = date.addingTimeInterval(lifetime)
            return expiry > now ? expiry : nil
        }.sorted() + [now.addingTimeInterval(30.1)]
        completion(Timeline(entries: dates.map { entry($0, snapshot) }, policy: .after(now.addingTimeInterval(900))))
    }
}
private struct JourneyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JourneyWidgetEntry
    private var s: JourneyWidgetSnapshot { entry.vehicle }
    private func t(_ ar: String, _ en: String) -> String { s.text(ar, en) }
    private func flag(_ value: Bool?, _ yes: String, _ no: String) -> String { value.map { $0 ? yes : no } ?? "—" }
    private func integer(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    private func decimal(_ value: Double?) -> String { value.flatMap { $0.isFinite ? String(format: "%.1f", $0) : nil } ?? "—" }
    private var temperature: String { s.coolant.map { s.temperatureUnit == "f" ? String(Int(Double($0) * 1.8 + 32)) + "°F" : "\($0)°C" } ?? "—" }
    private var speed: String { s.speed.map { s.speedUnit == "mph" ? String(Int(Double($0) * 0.621371)) + " mph" : "\($0) km/h" } ?? "—" }
    var body: some View {
        Group {
            switch family {
            case .systemLarge: large
            case .systemSmall: small
            case .accessoryCircular: Image(systemName: s.online ? "car.fill" : "car")
            case .accessoryInline: Text(s.name + " · " + integer(s.rpm) + " RPM")
            case .accessoryRectangular: VStack(alignment: .leading) { Text(s.name).bold(); Text(integer(s.rpm) + " RPM · " + temperature) }
            default: medium
            }
        }
        .foregroundStyle(.white)
        .environment(\.layoutDirection, s.english ? .leftToRight : .rightToLeft)
        .containerBackground(for: .widget) { LinearGradient(colors: [Color(red: 0.02, green: 0.07, blue: 0.11), Color(red: 0.03, green: 0.17, blue: 0.21), .black], startPoint: .topLeading, endPoint: .bottomTrailing) }
        .widgetURL(URL(string: "journeycontrol://widget/open"))
    }
    private var header: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 1) { Text("JOURNEY").font(.system(size: 14, weight: .bold)); Text(s.name).font(.system(size: 10)).lineLimit(1) }
            Spacer(minLength: 2)
            Text(s.online ? t("متصل", "Live") : t("غير متصل", "Offline")).font(.system(size: 9)).foregroundStyle(s.online ? .cyan : .gray)
            Button(intent: JourneyRefreshIntent(deviceID: s.deviceID)) { Image(systemName: "arrow.clockwise").font(.system(size: 13)).foregroundStyle(.cyan) }.buttonStyle(.plain)
        }
    }
    private var footer: some View {
        VStack(spacing: 2) {
            if let message = entry.message { Text(message).font(.system(size: 9)).foregroundStyle(.cyan).lineLimit(2) }
            HStack(spacing: 3) {
                Text(t("آخر قراءة", "Last reading"))
                if let date = s.stateAt { Text(date, style: .time) } else { Text("—") }
                Spacer(minLength: 0)
                if !JourneyWidgetStore.available { Text(t("المشاركة غير متاحة", "Sharing unavailable")) }
            }.font(.system(size: 8)).foregroundStyle(.white.opacity(0.55))
        }
    }
    private var actions: some View {
        HStack(spacing: 5) {
            Button(intent: JourneyLockIntent(deviceID: s.deviceID)) { action("lock.fill", t("قفل", "Lock"), .cyan) }
            Button(intent: JourneyUnlockIntent(deviceID: s.deviceID)) { action("lock.open.fill", t("فتح", "Unlock"), .cyan) }
            Button(intent: JourneyStartIntent(deviceID: s.deviceID)) { action("faceid", t("تشغيل", "Start"), .orange) }
        }.buttonStyle(.plain).disabled(s.deviceID.isEmpty)
    }
    private func action(_ icon: String, _ title: String, _ tint: Color) -> some View {
        HStack(spacing: 3) { Image(systemName: icon); Text(title).lineLimit(1).minimumScaleFactor(0.7) }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            .frame(maxWidth: .infinity).frame(height: 29)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(value).font(.system(size: 13, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7); Text(title).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var small: some View {
        VStack(spacing: 4) { header; JourneyWidgetCar(s: s).frame(maxHeight: 57); HStack { metric("RPM", integer(s.rpm)); metric(t("حرارة", "Coolant"), temperature) }; actions; footer }
    }
    private var medium: some View {
        VStack(spacing: 5) {
            header
            HStack(spacing: 6) {
                VStack(spacing: 5) { HStack { metric("RPM", integer(s.rpm)); metric(t("سرعة", "Speed"), speed) }; HStack { metric(t("حرارة", "Coolant"), temperature); metric(t("بنزين", "Fuel"), s.fuel.map { "\($0)%" } ?? "—") } }
                JourneyWidgetCar(s: s).frame(width: 135)
            }.frame(maxHeight: .infinity)
            actions; footer
        }
    }
    private var large: some View {
        VStack(spacing: 6) {
            header
            HStack(spacing: 8) {
                JourneyWidgetCar(s: s).frame(width: 154)
                VStack(alignment: .leading, spacing: 5) {
                    row(t("المحرك", "Engine"), s.rpm.map { $0 > 0 ? t("شغال", "Running") : t("متوقف", "Stopped") } ?? "—")
                    row(t("القفل", "Locks"), flag(s.locked, t("مقفلة", "Locked"), t("مفتوحة", "Unlocked")))
                    row(t("طاقة الريموت", "Remote power"), flag(s.remotePowered, t("شغال", "On"), t("طافي", "Off")))
                    row("OBD", s.obdConnected ? t("متصل", "Connected") : "—")
                }
            }.frame(height: 80)
            HStack { metric("RPM", integer(s.rpm)); metric(t("السرعة", "Speed"), speed); metric(t("حرارة المحرك", "Coolant"), temperature) }
            HStack { metric(t("البنزين", "Fuel"), s.fuel.map { "\($0)%" } ?? "—"); metric(t("بطارية السيارة", "Vehicle battery"), s.battery.map { decimal($0) + " V" } ?? "—"); metric(t("حرارة ESP", "ESP temperature"), s.espTemperature.map { decimal($0) + "°C" } ?? "—") }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                door(t("باب السائق", "Driver door"), 2); door(t("باب الراكب", "Passenger door"), 4)
                door(t("خلف السائق", "Rear driver"), 8); door(t("خلف الراكب", "Rear passenger"), 16)
                door(t("الصندوق", "Liftgate"), 64)
                row(t("بطارية ESP", "ESP battery"), s.espBattery.map { decimal($0) + "%" } ?? "—")
                row(t("الواطي", "Low beam"), flag(s.lowBeam, t("شغال", "On"), t("طافي", "Off")))
                row(t("السكن", "Parking lights"), flag(s.parking, t("شغال", "On"), t("طافي", "Off")))
                row(t("إشارة يسار", "Left signal"), flag(s.leftTurn, t("شغالة", "On"), t("طافية", "Off")))
                row(t("إشارة يمين", "Right signal"), flag(s.rightTurn, t("شغالة", "On"), t("طافية", "Off")))
            }
            HStack { Text(s.latitude.flatMap { lat in s.longitude.map { String(format: "GPS %.4f, %.4f", lat, $0) } } ?? t("GPS غير متاح", "GPS unavailable")); Spacer(); Text(s.firmware.isEmpty ? "ESP —" : "ESP " + s.firmware) }.font(.system(size: 8)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            actions; footer
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) { Text(label).foregroundStyle(.white.opacity(0.65)); Spacer(minLength: 1); Text(value).foregroundStyle(.cyan) }.font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
    }
    private func door(_ label: String, _ bit: Int) -> some View { row(label, flag(s.door(bit), t("مفتوح", "Open"), t("مغلق", "Closed"))) }
}
private struct JourneyWidgetCar: View {
    let s: JourneyWidgetSnapshot
    private func layer(_ name: String, _ visible: Bool = true) -> some View {
        Image("JourneyLayer" + name).resizable().aspectRatio(1920.0 / 1200.0, contentMode: .fit).opacity(visible ? 1 : 0)
    }
    var body: some View {
        GeometryReader { proxy in
            let scale = max(0, proxy.size.width - 8) / 1794
            ZStack {
                layer("Liftgate", s.door(64) == true)
                layer("DriverRearDoor", s.door(8) == true)
                layer("PassengerRearDoor", s.door(16) == true)
                layer("Body")
                layer("DriverMirror", s.door(2) != true)
                layer("PassengerMirror", s.door(4) != true)
                layer("DriverDoor", s.door(2) == true)
                layer("PassengerDoor", s.door(4) == true)
                layer("RedDRL", (s.rpm ?? 0) > 0 && s.lowBeam == false)
                layer("LowBeam", s.lowBeam == true)
                layer("Projectors", s.lowBeam == true || s.parking == true)
                layer("PassengerDRL", (s.rpm ?? 0) > 0 && s.rightTurn == false)
                layer("DriverDRL", (s.rpm ?? 0) > 0 && s.leftTurn == false)
            }.frame(width: 1920 * scale, height: 1200 * scale)
                .position(x: proxy.size.width / 2, y: 600 * scale - 46 * scale)
        }.aspectRatio(1794.0 / 1165.0, contentMode: .fit)
    }
}
struct JourneyHomeWidget: Widget {
    let kind = "JourneyHomeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JourneyWidgetProvider()) { JourneyWidgetView(entry: $0) }
            .configurationDisplayName("JOURNEY")
            .description("بيانات السيارة وأزرار الفتح والقفل والتشغيل مع Face ID.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
@main struct JourneyWidgetBundle: WidgetBundle { var body: some Widget { JourneyHomeWidget() } }
