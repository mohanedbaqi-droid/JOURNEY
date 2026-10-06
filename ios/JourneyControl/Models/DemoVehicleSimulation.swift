import Foundation

/// Deterministic local state for JOURNEY DEMO; it never uses a vehicle transport.
enum DemoVehicleSimulation {
    static func initialState() -> VehicleState {
        var state = VehicleState()
        state.online = true
        state.benchMode = true
        state.rpmValid = true; state.speedValid = true; state.coolantValid = true
        state.doorsValid = true; state.lightsValid = true; state.turnsValid = true
        state.bcmStateValid = true
        state.batteryVoltage = 12.6
        state.coolantC = 24
        state.fuelLevelPercent = 62; state.fuelLevelValid = true
        state.obdStatus = "DEMO"
        state.lastEvent = "DEMO"
        state.internetRoute = "NONE"
        state.ignitionState = "OFF"
        return state
    }

    static func toggle(_ item: String, state: inout VehicleState) {
        switch item {
        case "driverFront": state.demoDriverFrontOpen.toggle()
        case "passengerFront": state.demoPassengerFrontOpen.toggle()
        case "driverRear": state.demoDriverRearOpen.toggle()
        case "passengerRear": state.demoPassengerRearOpen.toggle()
        case "liftgate": state.demoLiftgateOpen.toggle()
        case "hood": state.demoHoodOpen.toggle()
        case "drl": state.demoDRLOn.toggle()
        case "headlights": state.headlightsOn.toggle()
        case "leftSignal": state.leftSignalOn.toggle()
        case "rightSignal": state.rightSignalOn.toggle()
        case "hazard":
            let enabled = !(state.leftSignalOn && state.rightSignalOn)
            state.leftSignalOn = enabled; state.rightSignalOn = enabled
        case "allDoors":
            let enabled = !(state.demoDriverFrontOpen && state.demoPassengerFrontOpen &&
                state.demoDriverRearOpen && state.demoPassengerRearOpen)
            state.demoDriverFrontOpen = enabled; state.demoPassengerFrontOpen = enabled
            state.demoDriverRearOpen = enabled; state.demoPassengerRearOpen = enabled
        case "reset": state = initialState()
        default: return
        }
        synchronizeOpenState(&state)
        state.lastEvent = "DEMO • \(item)"
    }

    @discardableResult
    static func apply(_ action: String, state: inout VehicleState) -> Bool {
        switch action {
        case "lock", "keyless_lock":
            state.simulatedLocked = true; state.feedbackLock = true
        case "unlock", "keyless_unlock":
            state.simulatedLocked = false; state.feedbackUnlock = true
        case "remote_start":
            state.simulatedEngineRunning.toggle()
            state.rpm = state.simulatedEngineRunning ? 780 : 0
            state.batteryVoltage = state.simulatedEngineRunning ? 14.2 : 12.6
            state.ignitionState = state.simulatedEngineRunning ? "ENGINE_RUNNING" : "OFF"
            state.demoDRLOn = state.simulatedEngineRunning
            state.feedbackStart = true
        case "remote_power_on": state.remotePowered = true
        case "remote_power_off": state.remotePowered = false
        case "doors": toggle("allDoors", state: &state)
        case "lights": toggle("headlights", state: &state)
        case "left_signal": toggle("leftSignal", state: &state)
        case "right_signal": toggle("rightSignal", state: &state)
        case "horn": state.hornActive = true; state.feedbackAlarm = true
        case "esp_settings", "maintenance_mode", "power_save", "connection_priority", "keyless_config": break
        default: return false
        }
        state.lastEvent = "DEMO • \(action)"
        return true
    }

    private static func synchronizeOpenState(_ state: inout VehicleState) {
        state.simulatedDoorsOpen = state.demoDriverFrontOpen || state.demoPassengerFrontOpen ||
            state.demoDriverRearOpen || state.demoPassengerRearOpen
    }
}
