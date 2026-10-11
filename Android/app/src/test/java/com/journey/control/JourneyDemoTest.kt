package com.journey.control

import org.junit.Test
import org.junit.Assert.*

class JourneyDemoTest {
 @Test fun independentDoorsAndLightingDriveTheRealCarLayerModelWithoutEspPackets() {
  var d=JourneyDemoState()
  assertTrue(d.locked)
  assertEquals(0,d.doorMask)
  d=d.toggle("driverDoor").toggle("passengerDoor").toggle("rearDriverDoor")
      .toggle("rearPassengerDoor").toggle("trunk").toggle("hood")
      .toggle("lowBeam").toggle("leftTurn")
  val state=d.toVehicleState(5000L)
  assertTrue(state.online)
  assertEquals(0x7E,state.doorOpenMask)
  assertEquals(0x7E,state.doorKnownMask)
  listOf(2,4,8,16,32,64).forEach{assertTrue(state.doorOpen(it))}
  assertTrue(state.lowBeam)
  assertTrue(state.projectors)
  assertTrue(state.leftTurn)
  assertFalse(state.rightTurn)
  assertEquals("DEMO",state.firmwareVersion)
  assertTrue(state.doorsValid)
 }

 @Test fun hazardsToggleBothSignalsTogetherAndDoNotTouchOtherFields() {
  val start=JourneyDemoState(locked=true,driverDoor=true,leftTurn=true)
  val both=start.toggle("hazards")
  assertTrue(both.leftTurn)
  assertTrue(both.rightTurn)
  assertTrue(both.driverDoor)
  assertEquals(start.locked,both.locked)
  val none=both.toggle("hazards")
  assertFalse(none.leftTurn)
  assertFalse(none.rightTurn)
  assertTrue(none.driverDoor)
 }

 @Test fun demoStartShowsKnownStoppedAndRunningWithoutFakingDtcOrGps() {
  val stopped=JourneyDemoState().toVehicleState(1000L)
  assertTrue(stopped.rpmValid)
  assertFalse(stopped.engineRunning)
  assertEquals(0,stopped.rpm)
  val running=JourneyDemoState().toggle("engine").toVehicleState(2000L)
  assertTrue(running.engineRunning)
  assertEquals(850,running.rpm)
  assertFalse(running.gpsValid)
  assertEquals("",running.dtc)
 }

 @Test fun unknownDemoActionCannotMutateState() {
  val s=JourneyDemoState(driverDoor=true)
  assertEquals(s,s.toggle("send_to_esp"))
 }
}
