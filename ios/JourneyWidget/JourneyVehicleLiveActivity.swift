import ActivityKit
import SwiftUI
import WidgetKit

/// Separate from the normal Home Screen widget: ActivityKit carries the data
/// from the host app, even when App Group file sharing is unavailable.
struct JourneyVehicleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "car.side.fill")
                        .foregroundStyle(.cyan)
                    Text("JOURNEY")
                        .font(.headline.bold())
                    if context.state.demoMode {
                        Text("DEMO")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Label(context.state.online ? "ONLINE" : "OFFLINE",
                          systemImage: context.state.online ? "checkmark.circle.fill" : "wifi.slash")
                        .font(.caption2.bold())
                        .foregroundStyle(context.state.online ? .cyan : .orange)
                }
                HStack(spacing: 12) {
                    metric(context.state.locked.map { $0 ? "مقفلة" : "مفتوحة" } ?? "—",
                           caption: "القفل",
                           icon: context.state.locked == true ? "lock.fill" : "lock.open.fill")
                    metric(context.state.engineRunning.map { $0 ? "شغال" : "مطفأ" } ?? "—",
                           caption: "المحرك",
                           icon: "engine.combustion.fill")
                    metric("\(context.state.openDoorCount)", caption: "أبواب مفتوحة", icon: "door.left.hand.open")
                    metric(context.state.rpm.map(String.init) ?? "—", caption: "RPM", icon: "gauge.with.dots.needle.67percent")
                }
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                    Text(context.state.lowBeam.map { $0 ? "أيت شغال" : "أيت مطفأ" } ?? "—")
                    Image(systemName: "arrow.turn.up.left")
                        .foregroundStyle(context.state.leftTurn == true ? .orange : .gray)
                    Image(systemName: "arrow.turn.up.right")
                        .foregroundStyle(context.state.rightTurn == true ? .orange : .gray)
                    Spacer()
                    if let last = context.state.lastReading {
                        Text(last, style: .time).foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                Text(context.state.demoMode
                    ? "محاكاة فقط — بدون أوامر للسيارة"
                    : "آخر قراءة معروفة — افتح JOURNEY للتحديث")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(13)
            .foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.035, green: 0.09, blue: 0.13))
            .activitySystemActionForegroundColor(.cyan)
            .widgetURL(URL(string: "journeycontrol://widget/open"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("JOURNEY", systemImage: "car.fill").foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.demoMode ? "DEMO" : (context.state.online ? "LIVE" : "OFFLINE"))
                        .foregroundStyle(context.state.demoMode ? .orange : .cyan)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.locked == true ? "مقفلة" : "مفتوحة")
                        Spacer()
                        Text(context.state.engineRunning == true ? "محرك شغال" : "محرك مطفأ")
                        Spacer()
                        Text("\(context.state.openDoorCount) أبواب")
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "car.fill").foregroundStyle(.cyan)
            } compactTrailing: {
                Image(systemName: context.state.locked == true ? "lock.fill" : "lock.open.fill")
            } minimal: {
                Image(systemName: "car.fill")
            }
            .widgetURL(URL(string: "journeycontrol://widget/open"))
        }
    }

    private func metric(_ value: String, caption: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption)
                .foregroundStyle(.cyan)
            Text(value).font(.caption.bold()).lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(caption).font(.system(size: 9)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}
