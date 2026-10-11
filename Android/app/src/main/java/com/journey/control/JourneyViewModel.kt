package com.journey.control

import android.app.Application
import android.content.Context
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.UUID

class JourneyViewModel(app:Application):AndroidViewModel(app){
 private val prefs=app.getSharedPreferences("journey",Context.MODE_PRIVATE)
 val phoneId:String=prefs.getString("phoneID",null)?:UUID.randomUUID().toString().also{
  prefs.edit().putString("phoneID",it).apply()
 }
 private val _realState=MutableStateFlow(VehicleState())
 private val _state=MutableStateFlow(VehicleState())
 val state:StateFlow<VehicleState> = _state
 private val _status=MutableStateFlow("DISCONNECTED")
 val status:StateFlow<String> = _status
 val english=MutableStateFlow(prefs.getBoolean("english",false))
 val angled=MutableStateFlow(prefs.getBoolean("angled",false))
 val dark=MutableStateFlow(prefs.getBoolean("dark",true))
 val demoEnabled=MutableStateFlow(prefs.getBoolean(JourneyDemoStore.ENABLED,false))
 val demoState=MutableStateFlow(JourneyDemoStore.read(prefs))
 val lockStatusEnabled=MutableStateFlow(prefs.getBoolean("lockStatus.enabled",false))
 val mqttHost=MutableStateFlow(prefs.getString("mqtt.host","")?:"")
 val mqttPort=MutableStateFlow(prefs.getInt("mqtt.port",8883))
 val mqttUsername=MutableStateFlow(prefs.getString("mqtt.username","")?:"")
 val selectedDeviceID=MutableStateFlow(prefs.getString("mqtt.deviceID","")?:"")
 val mqttStatus=MutableStateFlow("MQTT_DISCONNECTED")
 private var lastCloudPacketAt=0L
 private val mqtt=JourneyMqttManager({device,packet->
  viewModelScope.launch {
   if(!demoEnabled.value && device==selectedDeviceID.value && device.isNotBlank()){
    val j=runCatching{JSONObject(packet)}.getOrNull()
    if(j!=null && j.optBoolean("cloudConnected",true)){
     lastCloudPacketAt=SystemClock.elapsedRealtime()
     mergeState(packet,"MQTT")
    }
   }
  }
 },{connected,message->
  viewModelScope.launch{
   mqttStatus.value=message
   if(connected)_status.value="MQTT_CONNECTED"
   else if(!demoEnabled.value && _status.value=="MQTT_CONNECTED")_status.value="DISCONNECTED"
  }
 })
 val ble=JourneyBleManager(app,{json->mergeState(json)},{connected,message->
  if(!demoEnabled.value){
   _status.value=message
   if(!connected && !cloudFresh()){
    _realState.value=_realState.value.copy(
     online=false,feedbackLock=false,feedbackUnlock=false,
     feedbackStart=false,feedbackAlarm=false
    )
    publish(_realState.value)
   }
  }
 })

 init{
  if(demoEnabled.value){
   _state.value=demoState.value.toVehicleState()
   _status.value="DEMO"
  } else if(mqttHost.value.isNotBlank() && selectedDeviceID.value.isNotBlank()){
   connectMqtt()
  }
  viewModelScope.launch {
   while(true){
    delay(500)
    val enabled=prefs.getBoolean(JourneyDemoStore.ENABLED,false)
    if(enabled!=demoEnabled.value) {
     setDemo(enabled,store=false)
    }
    if(demoEnabled.value){
     val updated=JourneyDemoStore.read(prefs)
     if(updated!=demoState.value) {
      demoState.value=updated
      publish(updated.toVehicleState())
     }
    } else {
     val expired=_realState.value.expire(SystemClock.elapsedRealtime())
     if(expired!=_realState.value){
      _realState.value=expired
      publish(expired)
     }
    }
   }
  }
 }

 private fun publish(next:VehicleState){
  _state.value=next
  JourneyHomeWidget.storeRealState(getApplication(),next)
  JourneyHomeWidget.refreshAll(getApplication())
  if(lockStatusEnabled.value)JourneyStatusNotification.update(getApplication(),next,demoEnabled.value)
 }

 fun setLanguage(value:Boolean){english.value=value;prefs.edit().putBoolean("english",value).apply();JourneyHomeWidget.refreshAll(getApplication())}
 fun setAppearance(value:Boolean){angled.value=value;prefs.edit().putBoolean("angled",value).apply()}
 fun setDark(value:Boolean){dark.value=value;prefs.edit().putBoolean("dark",value).apply()}

 fun setLockStatusEnabled(value:Boolean){
  lockStatusEnabled.value=value
  prefs.edit().putBoolean("lockStatus.enabled",value).apply()
  if(value)JourneyStatusNotification.update(getApplication(),_state.value,demoEnabled.value)
  else JourneyStatusNotification.cancel(getApplication())
 }

 fun setDemo(value:Boolean,store:Boolean=true){
  if(store)prefs.edit().putBoolean(JourneyDemoStore.ENABLED,value).apply()
  if(demoEnabled.value==value)return
  demoEnabled.value=value
  if(value){
   // Stop scanning, disconnect GATT and drop the write queue before we
   // render or accept simulated commands.
   ble.stop()
   mqtt.stop()
   lastCloudPacketAt=0L
   demoState.value=JourneyDemoStore.read(prefs)
   _status.value="DEMO"
   publish(demoState.value.toVehicleState())
  } else {
   _status.value="DISCONNECTED"
   // Old physical packets cannot be presented as a new connection.
   _realState.value=VehicleState()
   publish(_realState.value)
   connect()
   connectMqtt()
  }
 }
 fun toggleDemo(key:String){
  if(!demoEnabled.value)return
  val changed=demoState.value.toggle(key)
  if(changed==demoState.value)return
  JourneyDemoStore.save(prefs,changed)
  demoState.value=changed
  publish(changed.toVehicleState())
 }

 fun setDemoLocked(value:Boolean){
  if(!demoEnabled.value)return
  val next=demoState.value.copy(locked=value)
  JourneyDemoStore.save(prefs,next)
  demoState.value=next
  publish(next.toVehicleState())
 }

 fun connect(){
  if(demoEnabled.value)return
  ble.start(phoneId)
 }

 private fun cloudFresh()=mqtt.isConnected() &&
   SystemClock.elapsedRealtime()-lastCloudPacketAt in 0..8000 &&
   selectedDeviceID.value.isNotBlank()

 fun configureMqtt(host:String,port:Int,user:String,password:String,deviceID:String){
  val safeHost=host.trim()
  val safeDevice=deviceID.trim()
  if(port !in 1..65535 || safeHost.length>200 || safeDevice.length>120 ||
     safeDevice.any{it=='/'||it=='#'||it=='+'}){
   mqttStatus.value="MQTT_CONFIG_INVALID"
   return
  }
  mqttHost.value=safeHost
  mqttPort.value=port
  mqttUsername.value=user.trim()
  selectedDeviceID.value=safeDevice
  prefs.edit().putString("mqtt.host",safeHost).putInt("mqtt.port",port)
   .putString("mqtt.username",user.trim()).putString("mqtt.deviceID",safeDevice).apply()
  if(password.isNotEmpty())JourneyMqttSecrets.save(getApplication(),password)
  connectMqtt(password)
 }

 fun connectMqtt(password:String?=null){
  if(demoEnabled.value)return
  if(mqttHost.value.isBlank() || selectedDeviceID.value.isBlank()){
   mqttStatus.value="MQTT_NOT_CONFIGURED"
   return
  }
  mqtt.connect(mqttHost.value,mqttPort.value,mqttUsername.value,
   password?:JourneyMqttSecrets.read(getApplication()))
 }
 fun disconnectMqtt(){
  mqtt.stop()
  lastCloudPacketAt=0L
  mqttStatus.value="MQTT_DISCONNECTED"
 }

 fun setLocalPriority(order:List<String>){
  if(order.size==3 && order.toSet()==setOf("BLE","WIFI","CELLULAR")){
   prefs.edit().putString("connectionPriority.local",order.joinToString(",")).apply()
  }
 }

 private fun dispatch(action:String,extras:JSONObject,allowStart:Boolean):Boolean {
  if(demoEnabled.value || (action=="remote_start"&&!allowStart))return false
  if(!_realState.value.online){
   _status.value="NO_CONNECTION"
   return false
  }
  val payload=JourneyProtocol.command(phoneId,action,extras)
  val order=(prefs.getString("connectionPriority.local","CELLULAR,WIFI,BLE")
   ?:"CELLULAR,WIFI,BLE").split(",")
  val bleFirst=action in listOf("keyless_lock","keyless_unlock","remote_power_on","remote_power_off")
  val sent=if(bleFirst)ble.send(payload) ||
   (cloudFresh() && mqtt.publish(selectedDeviceID.value,payload))
  else{
   var done=false
   for(route in order){
    if(!done)done=if(route=="BLE")ble.send(payload)
      else cloudFresh() && mqtt.publish(selectedDeviceID.value,payload)
   }
   done || (cloudFresh() && mqtt.publish(selectedDeviceID.value,payload)) || ble.send(payload)
  }
  _status.value=if(sent)"SENT_WAITING_ESP"else "NO_CONNECTION"
  return sent
 }

 /** All normal app commands are forbidden in demo, and remote start must go
  * through Android BiometricPrompt (see MainActivity). */
 fun send(action:String,extras:JSONObject=JSONObject()):Boolean =
  dispatch(action,extras,false)

 /** Called only after Android's BiometricPrompt reports success. */
 fun authorizedStart():Boolean {
  if(demoEnabled.value){
   toggleDemo("engine")
   return true
  }
  return dispatch("remote_start",JSONObject(),true)
 }

 private fun mergeState(packet:String,source:String="BLE"){
  if(demoEnabled.value)return
  runCatching {
   val old=_realState.value
   val next=JourneyStateDecoder.merge(old,JSONObject(packet),SystemClock.elapsedRealtime())
   if(next.lastHealth!=old.lastHealth&&next.espTemperature!=null&&next.espThermalLevel>0&&next.espThermalLevel>old.espThermalLevel)
    EspHealthNotifications.show(getApplication(),next,english.value)
   _realState.value=next
   publish(next)
   _status.value=if(source=="MQTT")"MQTT_CONNECTED"else "CONNECTED"
  }.onFailure{_status.value="INVALID_PACKET"}
 }

 override fun onCleared(){
  ble.stop()
  mqtt.stop()
  super.onCleared()
 }
}
