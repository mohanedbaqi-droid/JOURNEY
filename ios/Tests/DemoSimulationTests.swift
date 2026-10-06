import Foundation
func JL(_ ar: String, _ en: String) -> String { en }
@main struct DemoSimulationTests {
    static func main() throws {
        var s = DemoVehicleSimulation.initialState()
        precondition(s.rpmValid && s.rpm == 0 && !s.simulatedEngineRunning)
        DemoVehicleSimulation.toggle("driverFront", state: &s)
        precondition(s.demoDriverFrontOpen && !s.demoPassengerFrontOpen && s.simulatedDoorsOpen)
        DemoVehicleSimulation.toggle("liftgate", state: &s)
        DemoVehicleSimulation.toggle("hood", state: &s)
        precondition(s.demoLiftgateOpen && s.demoHoodOpen)
        precondition(DemoVehicleSimulation.apply("lock", state: &s))
        precondition(s.simulatedLocked && s.demoDriverFrontOpen) // Lock does not physically shut a door.
        DemoVehicleSimulation.toggle("driverFront", state: &s)
        precondition(!s.simulatedDoorsOpen && s.demoLiftgateOpen && s.demoHoodOpen)
        DemoVehicleSimulation.toggle("leftSignal", state: &s)
        precondition(s.leftSignalOn && !s.rightSignalOn)
        DemoVehicleSimulation.toggle("hazard", state: &s)
        precondition(s.leftSignalOn && s.rightSignalOn)
        DemoVehicleSimulation.toggle("hazard", state: &s)
        precondition(!s.leftSignalOn && !s.rightSignalOn)
        precondition(DemoVehicleSimulation.apply("remote_start", state: &s))
        precondition(s.rpm == 780 && s.simulatedEngineRunning && s.demoDRLOn)
        precondition(DemoVehicleSimulation.apply("remote_start", state: &s))
        precondition(s.rpm == 0 && !s.simulatedEngineRunning)
        precondition(!DemoVehicleSimulation.apply("ota_url", state: &s))
        DemoVehicleSimulation.toggle("reset", state: &s)
        precondition(!s.demoLiftgateOpen && !s.demoHoodOpen && !s.simulatedDoorsOpen)
        let decoded = try JSONDecoder().decode(VehicleState.self, from: Data("{}".utf8))
        precondition(!decoded.demoDriverFrontOpen && !decoded.demoHoodOpen)
        print("Demo simulation checks passed")
    }
}
