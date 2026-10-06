package com.journey.control
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class TelemetryTest {
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
