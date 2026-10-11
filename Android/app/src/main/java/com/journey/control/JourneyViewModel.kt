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
 val ble=JourneyBleManager(app,{json->mergeState(json)},{connected,message->
  if(!demoEnabled.value){
   _status.value=message
   if(!connected){
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
   demoState.value=JourneyDemoStore.read(prefs)
   _status.value="DEMO"
   publish(demoState.value.toVehicleState())
  } else {
   _status.value="DISCONNECTED"
   // Old physical packets cannot be presented as a new connection.
   _realState.value=VehicleState()
   publish(_realState.value)
   connect()
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

 /** All normal app commands are forbidden in demo, and remote start must go
  * through Android BiometricPrompt (see MainActivity). */
 fun send(action:String,extras:JSONObject=JSONObject()):Boolean {
  if(demoEnabled.value || action=="remote_start")return false
  if(!_realState.value.online){
   _status.value="NO_CONNECTION"
   return false
  }
  if(!ble.send(JourneyProtocol.command(phoneId,action,extras))){
   _status.value="NO_CONNECTION"
   return false
  }
  _status.value="SENT_WAITING_ESP"
  return true
 }

 /** Called only after Android's BiometricPrompt reports success. */
 fun authorizedStart():Boolean {
  if(demoEnabled.value){
   toggleDemo("engine")
   return true
  }
  if(!_realState.value.online){
   _status.value="NO_CONNECTION"
   return false
  }
  val sent=ble.send(JourneyProtocol.command(phoneId,"remote_start"))
  _status.value=if(sent)"SENT_WAITING_ESP" else "NO_CONNECTION"
  return sent
 }

 private fun mergeState(packet:String){
  if(demoEnabled.value)return
  runCatching {
   val old=_realState.value
   val next=JourneyStateDecoder.merge(old,JSONObject(packet),SystemClock.elapsedRealtime())
   if(next.lastHealth!=old.lastHealth&&next.espTemperature!=null&&next.espThermalLevel>0&&next.espThermalLevel>old.espThermalLevel)
    EspHealthNotifications.show(getApplication(),next,english.value)
   _realState.value=next
   publish(next)
   _status.value="CONNECTED"
  }.onFailure{_status.value="INVALID_PACKET"}
 }

 override fun onCleared(){
  ble.stop()
  super.onCleared()
 }
}
