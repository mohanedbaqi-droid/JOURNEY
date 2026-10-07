package com.journey.control
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class TelemetryTest {
 @Test fun thermalThresholdRequiresDeviceReportAndSurvivesPartialPackets(){
  val old=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"partialState":true,"espHealthPacket":true,"espTemperatureValid":true,"espTemperatureC":51,"espTempWarningC":50,"espThermalLevel":1}"""),1000)
  assertEquals(50,old.espTempWarningC)
  val heartbeat=JourneyStateDecoder.merge(old,JSONObject("""{"p":1}"""),2000)
  assertEquals(50,heartbeat.espTempWarningC);assertEquals(1000L,heartbeat.lastHealth)
  val changed=JourneyStateDecoder.merge(heartbeat,JSONObject("""{"partialState":true,"espHealthPacket":true,"espTemperatureValid":true,"espTemperatureC":51,"espTempWarningC":60,"espThermalLevel":0}"""),3000)
  assertEquals(60,changed.espTempWarningC);assertEquals(0,changed.espThermalLevel)
  assertNull(JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"espTempWarningC":99}"""),1000).espTempWarningC)
 }

 @Test fun healthPacketsDoNotRefreshObdAndExpireIndependently(){
  val old=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"ot":1,"rv":true,"r":800,"bv":13.6}"""),1000)
  val health=JourneyStateDecoder.merge(old,JSONObject("""{"partialState":true,"espHealthPacket":true,"espTemperatureValid":true,"espTemperatureC":70.5,"espThermalLevel":1,"espBatteryValid":false,"firmwareVersion":"12.77"}"""),6000).expire(6000)
  assertEquals(70.5,health.espTemperature!!,0.01);assertNull(health.espBatteryVoltage);assertFalse(health.rpmValid)
  assertEquals(13.6,health.battery,0.01)
  val heartbeat=JourneyStateDecoder.merge(health,JSONObject("""{"p":1}"""),17000).expire(17000)
  assertTrue(heartbeat.online);assertNull(heartbeat.espTemperature);assertEquals(-1,heartbeat.espThermalLevel)
 }
 @Test fun gaugeReadingIsSeparateFromVehicleBattery(){
  val s=JourneyStateDecoder.merge(VehicleState(battery=13.6),JSONObject("""{"partialState":true,"espHealthPacket":true,"espTemperatureValid":false,"espBatteryValid":true,"espBatteryVoltage":3.8,"espBatteryPercent":62.5}"""),1000)
  assertEquals(3.8,s.espBatteryVoltage!!,0.01);assertEquals(62.5,s.espBatteryPercent!!,0.01);assertEquals(13.6,s.battery,0.01);assertNull(s.espTemperature)
 }

 @Test fun firmwareVersionMustBeReportedByEsp(){
  val noVersion=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"p":1,"ac":1}"""),1000)
  assertEquals("",noVersion.firmwareVersion)
  val version=JourneyStateDecoder.merge(noVersion,JSONObject("""{"partialState":true,"fw":"12.77"}"""),1100)
  assertEquals("12.77",version.firmwareVersion)
  assertEquals("12.77",JourneyStateDecoder.merge(version,JSONObject("""{"bp":1,"dv":true}"""),1200).firmwareVersion)
 }
 @Test fun independentDoorBitsAndLights(){
  val s=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"bp":1,"dm":86,"dk":86,"dv":true,"lv":true,"pl":true,"pv":true,"lo":false,"iv":true,"il":true,"ir":false}"""),1000)
  assertTrue(s.doorOpen(2));assertTrue(s.doorOpen(4));assertTrue(s.doorOpen(16));assertTrue(s.doorOpen(64));assertFalse(s.doorKnown(8))
  assertTrue(s.projectors);assertFalse(s.lowBeam);assertTrue(s.leftTurn);assertFalse(s.rightTurn)
 }
 @Test fun ownerHeartbeatCannotKeepTelemetryAlive(){
  val live=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"ot":1,"r":820,"rv":true,"sv":true,"v":0,"tv":true,"t":89}"""),1000)
  assertTrue(live.drl)
  val owner=JourneyStateDecoder.merge(live,JSONObject("""{"p":1,"ac":1,"on":1}"""),7000).expire(7000)
  assertTrue(owner.online);assertFalse(owner.rpmValid);assertFalse(owner.drl)
 }
 @Test fun missingDoorMapNeverPretendsToKnowDoors(){
  val s=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"bp":1,"do":1,"dv":true}"""),1000)
  assertFalse(s.doorKnown(2));assertFalse(s.doorOpen(2))
 }
 @Test fun bodyDoesNotEraseEngineAndCoreDoesNotEraseBody(){
  val engine=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"ot":1,"r":800,"rv":true}"""),1000)
  val body=JourneyStateDecoder.merge(engine,JSONObject("""{"bp":1,"dv":true,"dm":2,"dk":86,"lv":true,"pv":true,"pl":true}"""),1500)
  val core=JourneyStateDecoder.merge(body,JSONObject("""{"partialState":true,"coreStatePacket":true,"remotePowered":true,"simulatedDoorsOpen":false}"""),1600)
  assertTrue(core.drl);assertTrue(core.doorOpen(2));assertTrue(core.projectors);assertTrue(core.remotePowered)
 }
 @Test fun writeOrHeartbeatCannotFakeGreenFeedback(){
  val s=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"p":1,"ev":"lock","on":1}"""),1000)
  assertFalse(s.feedbackLock)
  val pulse=JourneyStateDecoder.merge(s,JSONObject("""{"partialState":true,"coreStatePacket":true,"feedbackLock":true}"""),1100)
  assertTrue(pulse.feedbackLock);assertFalse(pulse.expire(3000).feedbackLock)
 }
 @Test fun stoppedIsDifferentFromMissing(){
  val zero=JourneyStateDecoder.merge(VehicleState(),JSONObject("""{"ot":1,"r":0,"rv":true}"""),1000)
  assertTrue(zero.rpmValid);assertFalse(zero.engineRunning)
  val missing=JourneyStateDecoder.merge(zero,JSONObject("""{"ot":1,"r":800,"rv":false}"""),2000)
  assertFalse(missing.rpmValid);assertFalse(missing.engineRunning)
 }
}
