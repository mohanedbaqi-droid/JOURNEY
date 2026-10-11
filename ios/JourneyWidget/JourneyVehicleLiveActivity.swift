import ActivityKit
import SwiftUI
import WidgetKit

/// Separate from the normal Home Screen widget: ActivityKit carries the data
/// from the host app, even when App Group file sharing is unavailable.
struct JourneyVehicleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            // iOS sizes Lock Screen Live Activities within a system-managed
            // area (typically up to ~160pt tall). Spend the available space on
            // larger text and two real controls rather than empty margins.
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "car.side.fill")
                        .foregroundStyle(.cyan)
                    Text("JOURNEY")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
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
                HStack(spacing: 6) {
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

                HStack(spacing: 9) {
                    Button(intent: JourneyActivityUnlockIntent(deviceID: context.attributes.vehicleID)) {
                        controlLabel("فتح", systemName: "lock.open.fill", tint: .cyan)
                    }
                    .buttonStyle(.plain)
                    .disabled(!context.state.online && !context.state.demoMode)

                    Button(intent: JourneyActivityLockIntent(deviceID: context.attributes.vehicleID)) {
                        controlLabel("قفل", systemName: "lock.fill", tint: .orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(!context.state.online && !context.state.demoMode)
                }
                .frame(height: 38)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

    private func controlLabel(_ label: String, systemName: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName).font(.system(size: 16, weight: .bold))
            Text(label).font(.system(size: 15, weight: .bold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(tint.opacity(0.42), lineWidth: 1)
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
