package com.journey.control

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject
import java.util.UUID

class JourneyViewModel(app:Application):AndroidViewModel(app){
    private val prefs=app.getSharedPreferences("journey",Context.MODE_PRIVATE)
    val phoneId:String=prefs.getString("phoneID",null)?:UUID.randomUUID().toString().also{prefs.edit().putString("phoneID",it).apply()}
    private val _state=MutableStateFlow(VehicleState()); val state:StateFlow<VehicleState> = _state
    private val _status=MutableStateFlow("غير متصل"); val status:StateFlow<String> = _status
    val ble=JourneyBleManager(app){json->mergeState(json)}
    fun connect(){ble.start(phoneId);_status.value="جاري البحث عن ESP"}
    fun send(action:String, extras:JSONObject=JSONObject()){ble.send(JourneyProtocol.command(phoneId,action,extras))}
    private fun mergeState(s:String){runCatching{
        val j=JSONObject(s); val old=_state.value
        _state.value=old.copy(
          online=j.optBoolean("online",old.online),
          locked=j.optBoolean("simulatedLocked",if(j.has("lk"))j.optInt("lk")==1 else old.locked),
          engineRunning=j.optBoolean("simulatedEngineRunning",if(j.has("er"))j.optInt("er")==1 else old.engineRunning),
          doorsOpen=j.optBoolean("simulatedDoorsOpen",if(j.has("do"))j.optInt("do")==1 else old.doorsOpen),
          remotePowered=j.optBoolean("remotePowered",if(j.has("rp"))j.optInt("rp")==1 else old.remotePowered),
          rpm=if(j.has("r"))j.optInt("r") else j.optInt("rpm",old.rpm),
          speed=if(j.has("v"))j.optInt("v") else j.optInt("speedKph",old.speed),
          coolant=if(j.has("t"))j.optInt("t") else j.optInt("coolantC",old.coolant),
          fuel=if(j.has("fl"))j.optInt("fl") else j.optInt("fuelLevelPercent",old.fuel),
          battery=if(j.has("bv"))j.optDouble("bv") else j.optDouble("batteryVoltage",old.battery),
          obdConnected=if(j.has("oc"))j.optInt("oc")==1 else j.optBoolean("obdConnected",old.obdConnected),
          obdStatus=if(j.has("os"))j.optString("os") else j.optString("obdStatus",old.obdStatus),
          wifiEnabled=j.optBoolean("wifiEnabled",old.wifiEnabled),wifiConnected=j.optBoolean("wifiConnected",old.wifiConnected),
          wifiSsid=j.optString("wifiSSID",old.wifiSsid),wifiStatus=j.optString("wifiStatus",old.wifiStatus),
          cellularEnabled=j.optBoolean("cellularEnabled",old.cellularEnabled),cellularStatus=j.optString("cellularStatus",old.cellularStatus),
          cellularNetwork=j.optString("cellularNetwork",old.cellularNetwork),hotspotEnabled=j.optBoolean("hotspotEnabled",old.hotspotEnabled),
          hotspotRunning=j.optBoolean("hotspotRunning",old.hotspotRunning),internetRoute=j.optString("internetRoute",old.internetRoute),
          ownerKnown=j.optBoolean("ownerStateKnown",old.ownerKnown),ownerCount=j.optInt("authorizedPhoneCount",old.ownerCount),
          lastEvent=j.optString("lastEvent",if(j.has("ev"))j.optString("ev") else old.lastEvent),
          connectionPriority=j.optString("connectionPriority",old.connectionPriority)
        ); _status.value="BLE متصل"
    }}
}
