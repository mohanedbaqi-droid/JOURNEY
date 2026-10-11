import ActivityKit
import Foundation
import UIKit

/// Live Activities let the host app transmit status directly to the Lock Screen
/// without reading the widget extension's App Group container.
/// No ESP commands originate from this service.
@MainActor
final class JourneyLiveActivityService {
    static let shared = JourneyLiveActivityService()
    private let defaults = UserDefaults.standard
    private var pending: JourneyWidgetSnapshot?
    private var busy = false
    private var lastState: JourneyActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast

    var authorized: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func refresh(_ snapshot: JourneyWidgetSnapshot) {
        pending = snapshot
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            while let current = pending {
                pending = nil
                await apply(current)
            }
            busy = false
        }
    }

    private func apply(_ snapshot: JourneyWidgetSnapshot) async {
        let existing = Activity<JourneyActivityAttributes>.activities
        guard defaults.bool(forKey: "journey.liveActivity.enabled") else {
            for activity in existing {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            lastState = nil
            return
        }
        guard authorized else { return }

        // A stale BLE/MQTT packet must never present itself as a live reading.
        let value = snapshot.expired(at: Date())
        let state = JourneyActivityAttributes.ContentState(
            demoMode: value.demoMode,
            online: value.online,
            locked: value.locked,
            engineRunning: value.rpm.map { $0 > 0 },
            rpm: value.rpm,
            coolantC: value.coolant,
            batteryV: value.battery,
            espTemperatureC: value.espTemperature,
            doorKnownMask: value.doorKnownMask,
            doorOpenMask: value.doorOpenMask,
            lowBeam: value.lowBeam,
            leftTurn: value.leftTurn,
            rightTurn: value.rightTurn,
            lastReading: value.stateAt,
            layoutStyle: defaults.string(forKey: "journey.liveActivity.layout") ?? "detailed"
        )
        let now = Date()
        var comparable = state
        comparable.lastReading = lastState?.lastReading
        if let previous = lastState, comparable == previous,
           now.timeIntervalSince(lastUpdate) < 60 {
            return
        }
        // Lock Screen buttons must show lock/unlock changes without waiting
        // for the normal telemetry throttle. Only delay routine packets when
        // none of the visible, user-critical states has changed.
        if now.timeIntervalSince(lastUpdate) < 3,
           let previous = lastState,
           previous.locked == state.locked,
           previous.engineRunning == state.engineRunning,
           previous.doorOpenMask == state.doorOpenMask,
           previous.lowBeam == state.lowBeam,
           previous.leftTurn == state.leftTurn,
           previous.rightTurn == state.rightTurn,
           previous.demoMode == state.demoMode,
           previous.layoutStyle == state.layoutStyle {
            return
        }

        for activity in existing where activity.attributes.vehicleID != value.deviceID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let content = ActivityContent(
            state: state,
            staleDate: value.demoMode ? nil : (value.stateAt?.addingTimeInterval(12))
        )
        if let activity = Activity<JourneyActivityAttributes>.activities.first(
            where: { $0.attributes.vehicleID == value.deviceID }
        ) {
            await activity.update(content)
            lastState = state
            lastUpdate = now
        } else {
            // iOS only allows an app to start a Live Activity in the foreground.
            guard UIApplication.shared.applicationState == .active else { return }
            do {
                let attrs = JourneyActivityAttributes(
                    vehicleID: value.deviceID,
                    vehicleName: value.name
                )
                _ = try Activity.request(attributes: attrs, content: content, pushType: nil)
                lastState = state
                lastUpdate = now
            } catch {
                // A disabled/unsupported Live Activity must never disrupt vehicle control.
                print("[JOURNEY] Unable to start Live Activity: \(error.localizedDescription)")
            }
        }
    }
}
