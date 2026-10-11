package com.journey.control

import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock

/**
 * Simulation lives in its own keys and never reads or overwrites real
 * vehicle packets, ESP credentials or phone ownership. Each action only
 * changes local preferences and the Android widget.
 */
data class JourneyDemoState(
    val locked:Boolean=true,
    val engine:Boolean=false,
    val driverDoor:Boolean=false,
    val passengerDoor:Boolean=false,
    val rearDriverDoor:Boolean=false,
    val rearPassengerDoor:Boolean=false,
    val trunk:Boolean=false,
    val hood:Boolean=false,
    val lowBeam:Boolean=false,
    val leftTurn:Boolean=false,
    val rightTurn:Boolean=false
) {
    val doorMask:Int get() =
        (if(driverDoor) 2 else 0) or
        (if(passengerDoor) 4 else 0) or
        (if(rearDriverDoor) 8 else 0) or
        (if(rearPassengerDoor) 16 else 0) or
        (if(hood) 32 else 0) or
        (if(trunk) 64 else 0)

    fun toggle(key:String):JourneyDemoState=when(key){
        "locked"->copy(locked=!locked)
        "engine"->copy(engine=!engine)
        "driverDoor"->copy(driverDoor=!driverDoor)
        "passengerDoor"->copy(passengerDoor=!passengerDoor)
        "rearDriverDoor"->copy(rearDriverDoor=!rearDriverDoor)
        "rearPassengerDoor"->copy(rearPassengerDoor=!rearPassengerDoor)
        "trunk"->copy(trunk=!trunk)
        "hood"->copy(hood=!hood)
        "lowBeam"->copy(lowBeam=!lowBeam)
        "leftTurn"->copy(leftTurn=!leftTurn)
        "rightTurn"->copy(rightTurn=!rightTurn)
        "hazards"->copy(leftTurn=!(leftTurn&&rightTurn),rightTurn=!(leftTurn&&rightTurn))
        else->this
    }

    fun toVehicleState(now:Long=SystemClock.elapsedRealtime())=VehicleState(
        online=true, locked=locked, engineRunning=engine, rpm=if(engine)850 else 0,
        speed=0, coolant=86, fuel=65, battery=12.6,
        doorOpenMask=doorMask, doorKnownMask=0x7E, doorsValid=true,
        headlightsOn=lowBeam, parkingLightsOn=lowBeam, parkingLightsValid=true,
        lightsValid=true, turnsValid=true, leftSignal=leftTurn, rightSignal=rightTurn,
        rpmValid=true, speedValid=true, coolantValid=true, fuelValid=true,
        remotePowered=true, obdStatus="DEMO", firmwareVersion="DEMO",
        espTemperature=36.0, espBatteryPercent=85.0, espBatteryVoltage=3.85,
        lastPacket=now,lastObd=now,lastBody=now,lastHealth=now,
        lastEvent="DEMO: local simulation only"
    )
}

object JourneyDemoStore {
    const val SETTINGS="journey"
    const val ENABLED="demo.enabled"
    private const val PREFIX="demo."
    private val keys=listOf("locked","engine","driverDoor","passengerDoor",
        "rearDriverDoor","rearPassengerDoor","trunk","hood","lowBeam","leftTurn","rightTurn")

    fun preferences(context:Context)=context.getSharedPreferences(SETTINGS,Context.MODE_PRIVATE)
    fun enabled(context:Context)=preferences(context).getBoolean(ENABLED,false)
    fun read(p:SharedPreferences)=JourneyDemoState(
        locked=p.getBoolean(PREFIX+"locked",true),
        engine=p.getBoolean(PREFIX+"engine",false),
        driverDoor=p.getBoolean(PREFIX+"driverDoor",false),
        passengerDoor=p.getBoolean(PREFIX+"passengerDoor",false),
        rearDriverDoor=p.getBoolean(PREFIX+"rearDriverDoor",false),
        rearPassengerDoor=p.getBoolean(PREFIX+"rearPassengerDoor",false),
        trunk=p.getBoolean(PREFIX+"trunk",false),
        hood=p.getBoolean(PREFIX+"hood",false),
        lowBeam=p.getBoolean(PREFIX+"lowBeam",false),
        leftTurn=p.getBoolean(PREFIX+"leftTurn",false),
        rightTurn=p.getBoolean(PREFIX+"rightTurn",false)
    )
    fun read(context:Context)=read(preferences(context))
    fun save(p:SharedPreferences,s:JourneyDemoState){
        p.edit()
            .putBoolean(PREFIX+"locked",s.locked)
            .putBoolean(PREFIX+"engine",s.engine)
            .putBoolean(PREFIX+"driverDoor",s.driverDoor)
            .putBoolean(PREFIX+"passengerDoor",s.passengerDoor)
            .putBoolean(PREFIX+"rearDriverDoor",s.rearDriverDoor)
            .putBoolean(PREFIX+"rearPassengerDoor",s.rearPassengerDoor)
            .putBoolean(PREFIX+"trunk",s.trunk)
            .putBoolean(PREFIX+"hood",s.hood)
            .putBoolean(PREFIX+"lowBeam",s.lowBeam)
            .putBoolean(PREFIX+"leftTurn",s.leftTurn)
            .putBoolean(PREFIX+"rightTurn",s.rightTurn)
            .apply()
    }
    fun apply(context:Context,action:String):Boolean {
        if(!enabled(context) || action !in keys && action!="hazards") return false
        val p=preferences(context)
        save(p,read(p).toggle(action))
        return true
    }
}
