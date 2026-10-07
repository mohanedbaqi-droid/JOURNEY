import Foundation
func JL(_ ar: String, _ en: String) -> String { en }
enum AppConfig { static let phoneID = "test-owner" }
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
   let health = try decode.decode(VehicleState.self, from: Data(#"{"partialState":true,"espHealthPacket":true,"espTemperatureValid":true,"espTemperatureC":70.5,"espThermalLevel":1,"espBatteryValid":false,"firmwareVersion":"12.77"}"#.utf8))
   precondition(health.partialState && health.espHealthPacket && health.espTemperatureC == 70.5 && health.espBatteryVoltage == nil && health.firmwareVersion == "12.77")
   let gauge = try decode.decode(VehicleState.self, from: Data(#"{"espHealthPacket":true,"espBatteryValid":true,"espBatteryVoltage":3.8,"espBatteryPercent":62.5}"#.utf8))
   precondition(gauge.espBatteryVoltage == 3.8 && gauge.espBatteryPercent == 62.5 && gauge.batteryVoltage == 0)
   let configured = try decode.decode(VehicleState.self, from: Data(#"{"espHealthPacket":true,"espTempWarningC":45,"espTemperatureValid":true,"espTemperatureC":46,"espThermalLevel":1}"#.utf8))
   precondition(configured.espTempWarningC == 45 && configured.espThermalLevel == 1)
   precondition(health.espTempWarningC == nil) // Older firmware cannot confirm this setting.
   let invalid = try decode.decode(VehicleState.self, from: Data(#"{"espTempWarningC":99}"#.utf8))
   precondition(invalid.espTempWarningC == nil)
   let command = VehicleCommand(action: .espSettings, espSettings: ESPRuntimeSettings(espTempWarningC: 45))
   let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as! [String: Any]
   precondition(encoded["action"] as? String == "esp_settings")
   let settings = encoded["espSettings"] as! [String: Any]
   precondition(settings.count == 1 && settings["espTempWarningC"] as? Int == 45) // Leave unrelated settings untouched.
   print("Telemetry decoder checks passed")
 }
}
