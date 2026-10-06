import Foundation
func JL(_ ar: String, _ en: String) -> String { en }
@main struct TelemetryDecoderTests {
 static func main() throws {
   let decode = JSONDecoder()
   let body = try decode.decode(VehicleState.self, from: Data(#"{"bp":1,"dv":true,"lv":false,"iv":true,"do":1,"lk":0,"lo":true,"il":true,"ir":false,"dg":"test"}"#.utf8))
   precondition(body.bodyStatePacket && body.partialState && body.doorsValid && body.simulatedDoorsOpen)
   precondition(!body.simulatedLocked && !body.lightsValid && body.turnsValid && body.leftSignalOn)
   let stale = try decode.decode(VehicleState.self, from: Data(#"{"ot":1,"oc":1,"r":851,"rv":false,"tv":true,"sv":false}"#.utf8))
   precondition(!stale.rpmValid && stale.engineStateText == "Unavailable")
   let zero = try decode.decode(VehicleState.self, from: Data(#"{"ot":1,"oc":1,"r":0,"rv":true}"#.utf8))
   precondition(zero.rpmValid && zero.engineStateText == "Stopped")
   let doors = try decode.decode(VehicleState.self, from: Data(#"{"bp":1,"dv":true,"dm":86,"dk":86,"lv":true,"pv":true,"pl":true,"lo":false}"#.utf8))
   precondition(doors.driverFrontOpen && doors.passengerFrontOpen && doors.passengerRearOpen && doors.liftgateOpen)
   precondition(!doors.driverRearOpen && !doors.doorIsKnown(8))
   precondition(doors.projectorsOn && !doors.lowBeamOn)
   var expired = doors; expired.doorsValid = false; expired.lightsValid = false
   precondition(!expired.driverFrontOpen && !expired.projectorsOn)
   precondition(body.doorKnownMask == 0 && !body.driverFrontOpen) // Older firmware cannot pretend to know individual doors.
   var running = zero; running.rpm = 800; running.simulatedEngineRunning = true
   precondition(running.drlOn)
   running.rpmValid = false; precondition(!running.drlOn)
   let full = try decode.decode(VehicleState.self, from: Data(#"{"doorOpenMask":2,"doorKnownMask":86,"doorsValid":true,"parkingLightsOn":false,"parkingLightsValid":true,"lightsValid":true,"headlightsOn":true}"#.utf8))
   precondition(full.driverFrontOpen && !full.passengerFrontOpen && full.projectorsOn && full.lowBeamOn)
   print("Telemetry decoder checks passed")
 }
}
