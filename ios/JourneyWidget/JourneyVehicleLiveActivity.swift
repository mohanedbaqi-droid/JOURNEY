import ActivityKit
import SwiftUI
import WidgetKit

/// Separate from the normal Home Screen widget: ActivityKit carries the data
/// from the host app, even when App Group file sharing is unavailable.
struct JourneyVehicleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            // A Live Activity is one system-managed surface, not two separately
            // resizable widgets. Let the owner choose which content density the
            // app sends to the extension through the ActivityKit state.
            let compact = context.state.layoutStyle == "compact"
            VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                HStack(spacing: 7) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: compact ? 14 : 16, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("JOURNEY")
                        .font(.system(size: compact ? 16 : 18, weight: .heavy, design: .rounded))
                    if context.state.demoMode {
                        Text("DEMO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 3)
                    Label(context.state.online ? "ONLINE" : "OFFLINE",
                          systemImage: context.state.online ? "checkmark.circle.fill" : "wifi.slash")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(context.state.online ? .cyan : .orange)
                }

                if compact {
                    // Compact: one row for the essentials, one for the controls.
                    HStack(spacing: 7) {
                        Label(context.state.locked.map { $0 ? "مقفلة" : "مفتوحة" } ?? "—",
                              systemImage: context.state.locked == true ? "lock.fill" : "lock.open.fill")
                        Spacer(minLength: 0)
                        Label(context.state.engineRunning.map { $0 ? "شغال" : "مطفأ" } ?? "—",
                              systemImage: "engine.combustion.fill")
                        Spacer(minLength: 0)
                        Label("\(context.state.openDoorCount)", systemImage: "door.left.hand.open")
                            .foregroundStyle(context.state.openDoorCount > 0 ? .orange : .cyan)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.vertical, 5)
                } else {
                    // Detailed: larger readouts with lighting, signals and
                    // reading timestamp, using the height iOS actually grants.
                    HStack(spacing: 7) {
                        metric(context.state.locked.map { $0 ? "مقفلة" : "مفتوحة" } ?? "—",
                               caption: "القفل",
                               icon: context.state.locked == true ? "lock.fill" : "lock.open.fill")
                        metric(context.state.engineRunning.map { $0 ? "شغال" : "مطفأ" } ?? "—",
                               caption: "المحرك", icon: "engine.combustion.fill")
                        metric("\(context.state.openDoorCount)",
                               caption: "أبواب مفتوحة", icon: "door.left.hand.open")
                        metric(context.state.rpm.map(String.init) ?? "—",
                               caption: "RPM", icon: "gauge.with.dots.needle.67percent")
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(context.state.lowBeam == true ? .cyan : .gray)
                        Text(context.state.lowBeam.map { $0 ? "أيت شغال" : "أيت مطفأ" } ?? "—")
                        Image(systemName: "arrow.turn.up.left")
                            .foregroundStyle(context.state.leftTurn == true ? .orange : .gray)
                        Image(systemName: "arrow.turn.up.right")
                            .foregroundStyle(context.state.rightTurn == true ? .orange : .gray)
                        Spacer(minLength: 0)
                        if let at = context.state.lastReading {
                            Text(at, style: .time).foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                }

                // Both sizes retain the lock and unlock LiveActivityIntents.
                // iOS may require device unlock before a real control runs.
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
                .frame(height: 40)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 8 : 9)
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
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(tint.opacity(0.42), lineWidth: 1)
        }
    }

    private func metric(_ value: String, caption: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
                .foregroundStyle(.cyan)
            Text(value).font(.system(size: 14, weight: .bold)).lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(caption).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}
