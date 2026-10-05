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
   print("Telemetry decoder checks passed")
 }
}
