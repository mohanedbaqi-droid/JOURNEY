package com.journey.control

import org.json.JSONObject

data class VehicleState(
    val online:Boolean=false, val locked:Boolean=true, val engineRunning:Boolean=false, val doorsOpen:Boolean=false,
    val doorOpenMask:Int=0, val doorKnownMask:Int=0, val doorsValid:Boolean=false,
    val headlightsOn:Boolean=false, val parkingLightsOn:Boolean=false, val parkingLightsValid:Boolean=false,
    val lightsValid:Boolean=false, val turnsValid:Boolean=false, val leftSignal:Boolean=false, val rightSignal:Boolean=false,
    val rpmValid:Boolean=false, val speedValid:Boolean=false, val coolantValid:Boolean=false, val fuelValid:Boolean=false,
    val feedbackLock:Boolean=false, val feedbackUnlock:Boolean=false, val feedbackStart:Boolean=false, val feedbackAlarm:Boolean=false,
    val remotePowered:Boolean=false, val rpm:Int=0, val speed:Int=0, val coolant:Int=0, val fuel:Int=0,
    val battery:Double=0.0, val obdConnected:Boolean=false, val obdStatus:String="waiting", val diagnostics:String="",
    val wifiEnabled:Boolean=false, val wifiConnected:Boolean=false, val wifiSsid:String="", val wifiStatus:String="off",
    val cellularEnabled:Boolean=false, val cellularStatus:String="off", val cellularNetwork:String="",
    val hotspotEnabled:Boolean=false, val hotspotRunning:Boolean=false, val internetRoute:String="NONE",
    val latitude:Double=0.0, val longitude:Double=0.0, val gpsValid:Boolean=false,
    val ownerKnown:Boolean=false, val ownerCount:Int=0, val adminPhone:String="", val pendingPhone:String="", val lastEvent:String="waiting",
    val connectionPriority:String="CELLULAR,WIFI,BLE", val dtc:String="", val adapterList:String="", val wifiList:String="",
    val lastPacket:Long=0, val lastObd:Long=0, val lastBody:Long=0, val lastFeedback:Long=0
) {
    fun doorKnown(bit:Int)=online && doorsValid && doorKnownMask.and(bit)!=0
    fun doorOpen(bit:Int)=doorKnown(bit) && doorOpenMask.and(bit)!=0
    val drl get()=online && rpmValid && engineRunning
    val lowBeam get()=online && lightsValid && headlightsOn
    val projectors get()=online && lightsValid && (headlightsOn || (parkingLightsValid && parkingLightsOn))
    val leftTurn get()=online && turnsValid && leftSignal
    val rightTurn get()=online && turnsValid && rightSignal
    fun expire(now:Long):VehicleState {
        val linked=online && now-lastPacket<=12000
        val obdFresh=linked && now-lastObd<=4000
        val bodyFresh=linked && now-lastBody<=4000
        val feedbackFresh=linked && now-lastFeedback<=1500
        return copy(online=linked,rpmValid=rpmValid&&obdFresh,speedValid=speedValid&&obdFresh,coolantValid=coolantValid&&obdFresh,
            engineRunning=engineRunning&&obdFresh,fuelValid=fuelValid&&obdFresh,doorsValid=doorsValid&&bodyFresh,lightsValid=lightsValid&&bodyFresh,turnsValid=turnsValid&&bodyFresh,
            feedbackLock=feedbackLock&&feedbackFresh,feedbackUnlock=feedbackUnlock&&feedbackFresh,feedbackStart=feedbackStart&&feedbackFresh,feedbackAlarm=feedbackAlarm&&feedbackFresh)
    }
}

/** Typed partial packets preserve independent telemetry and owner state. */
object JourneyStateDecoder {
    fun merge(old:VehicleState, j:JSONObject, now:Long):VehicleState {
        fun b(full:String, compact:String="", fallback:Boolean=false):Boolean {
            val key=if(j.has(full))full else if(compact.isNotEmpty()&&j.has(compact))compact else return fallback
            return when(val v=j.opt(key)){is Boolean->v;is Number->v.toInt()!=0;else->fallback}
        }
        fun i(full:String, compact:String="", fallback:Int=0)=when{j.has(full)->j.optInt(full,fallback);compact.isNotEmpty()&&j.has(compact)->j.optInt(compact,fallback);else->fallback}
        fun t(full:String, compact:String="", fallback:String="")=when{j.has(full)->j.optString(full,fallback);compact.isNotEmpty()&&j.has(compact)->j.optString(compact,fallback);else->fallback}
        val full=!b("partialState") && !j.has("p") && !j.has("ot") && !j.has("bp") && !b("wifiStatePacket") && !b("cellularStatePacket")
        val body=j.optInt("bp")==1 || full
        val obd=j.optInt("ot")==1 || b("obdTelemetryPacket") || full
        val feedback=j.has("feedbackLock") || j.has("feedbackUnlock") || j.has("feedbackStart") || j.has("feedbackAlarm")
        val rv=if(obd)b("rpmValid","rv") else old.rpmValid
        val rpm=i("rpm","r",old.rpm)
        val result=old.copy(
            online=true,lastPacket=now,lastBody=if(body)now else old.lastBody,lastObd=if(obd)now else old.lastObd,lastFeedback=if(feedback)now else old.lastFeedback,
            locked=b("simulatedLocked","lk",old.locked),remotePowered=b("remotePowered","rp",old.remotePowered),
            doorsOpen=if(body)b("simulatedDoorsOpen","do") else old.doorsOpen,
            doorOpenMask=if(body)i("doorOpenMask","dm") else old.doorOpenMask,doorKnownMask=if(body)i("doorKnownMask","dk") else old.doorKnownMask,
            doorsValid=if(body)b("doorsValid","dv") else old.doorsValid,
            headlightsOn=if(body)b("headlightsOn","lo") else old.headlightsOn,parkingLightsOn=if(body)b("parkingLightsOn","pl") else old.parkingLightsOn,
            parkingLightsValid=if(body)b("parkingLightsValid","pv") else old.parkingLightsValid,lightsValid=if(body)b("lightsValid","lv") else old.lightsValid,
            turnsValid=if(body)b("turnsValid","iv") else old.turnsValid,leftSignal=if(body)b("leftSignalOn","il") else old.leftSignal,rightSignal=if(body)b("rightSignalOn","ir") else old.rightSignal,
            rpm=if(obd)rpm else old.rpm,rpmValid=rv,engineRunning=if(obd)rv&&rpm>0 else old.engineRunning,
            speed=if(obd)i("speedKph","v",old.speed) else old.speed,speedValid=if(obd)b("speedValid","sv") else old.speedValid,
            coolant=if(obd)i("coolantC","t",old.coolant) else old.coolant,coolantValid=if(obd)b("coolantValid","tv") else old.coolantValid,
            fuel=i("fuelLevelPercent","fl",old.fuel),fuelValid=b("fuelLevelValid","fv",old.fuelValid),
            battery=if(j.has("bv"))j.optDouble("bv",old.battery) else j.optDouble("batteryVoltage",old.battery),
            obdConnected=b("obdConnected","oc",old.obdConnected),obdStatus=t("obdStatus","os",old.obdStatus),diagnostics=t("readDiagnostics","dg",old.diagnostics),
            feedbackLock=b("feedbackLock",fallback=old.feedbackLock),feedbackUnlock=b("feedbackUnlock",fallback=old.feedbackUnlock),feedbackStart=b("feedbackStart",fallback=old.feedbackStart),feedbackAlarm=b("feedbackAlarm",fallback=old.feedbackAlarm),
            wifiEnabled=b("wifiEnabled",fallback=old.wifiEnabled),wifiConnected=b("wifiConnected",fallback=old.wifiConnected),wifiSsid=t("wifiSSID",fallback=old.wifiSsid),wifiStatus=t("wifiStatus",fallback=old.wifiStatus),
            cellularEnabled=b("cellularEnabled",fallback=old.cellularEnabled),cellularStatus=t("cellularStatus",fallback=old.cellularStatus),cellularNetwork=t("cellularNetwork",fallback=old.cellularNetwork),hotspotEnabled=b("hotspotEnabled",fallback=old.hotspotEnabled),hotspotRunning=b("hotspotRunning",fallback=old.hotspotRunning),internetRoute=t("internetRoute",fallback=old.internetRoute),
            gpsValid=b("gpsValid",fallback=old.gpsValid),latitude=j.optDouble("latitude",old.latitude),longitude=j.optDouble("longitude",old.longitude),
            ownerKnown=old.ownerKnown||j.optInt("p")==1||j.has("authorizedPhoneCount"),ownerCount=i("authorizedPhoneCount","ac",old.ownerCount),adminPhone=t("ownerAdminPhone","oa",old.adminPhone),pendingPhone=t("pendingOwnerPhone","po",old.pendingPhone),
            lastEvent=t("lastEvent","ev",old.lastEvent),connectionPriority=t("connectionPriority",fallback=old.connectionPriority),
            dtc=if(j.has("diagnosticCodes"))j.opt("diagnosticCodes").toString() else old.dtc,
            adapterList=t("obdDiscoveredAdapters",fallback=old.adapterList),wifiList=t("wifiDiscoveredNetworks",fallback=old.wifiList)
        )
        return result
    }
}
