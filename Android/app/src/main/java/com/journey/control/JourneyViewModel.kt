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
 val phoneId:String=prefs.getString("phoneID",null)?:UUID.randomUUID().toString().also{prefs.edit().putString("phoneID",it).apply()}
 private val _state=MutableStateFlow(VehicleState());val state:StateFlow<VehicleState> = _state
 private val _status=MutableStateFlow("DISCONNECTED");val status:StateFlow<String> = _status
 val english=MutableStateFlow(prefs.getBoolean("english",false))
 val angled=MutableStateFlow(prefs.getBoolean("angled",false))
 val dark=MutableStateFlow(prefs.getBoolean("dark",true))
 val ble=JourneyBleManager(app,{json->mergeState(json)},{connected,message->_status.value=message;if(!connected)_state.value=_state.value.copy(online=false,feedbackLock=false,feedbackUnlock=false,feedbackStart=false,feedbackAlarm=false)})
 init{viewModelScope.launch{while(true){delay(500);_state.value=_state.value.expire(SystemClock.elapsedRealtime())}}}
 fun setLanguage(value:Boolean){english.value=value;prefs.edit().putBoolean("english",value).apply()}
 fun setAppearance(value:Boolean){angled.value=value;prefs.edit().putBoolean("angled",value).apply()}
 fun setDark(value:Boolean){dark.value=value;prefs.edit().putBoolean("dark",value).apply()}
 fun connect(){ble.start(phoneId)}
 fun send(action:String,extras:JSONObject=JSONObject()){
  if(!ble.send(JourneyProtocol.command(phoneId,action,extras))){_status.value="NO_CONNECTION";return}
  _status.value="SENT_WAITING_ESP"
 }
 private fun mergeState(s:String){runCatching{val old=_state.value;val next=JourneyStateDecoder.merge(old,JSONObject(s),SystemClock.elapsedRealtime());if(next.lastHealth!=old.lastHealth&&next.espTemperature!=null&&next.espThermalLevel>0&&next.espThermalLevel>old.espThermalLevel)EspHealthNotifications.show(getApplication(),next,english.value);_state.value=next;_status.value="CONNECTED"}.onFailure{_status.value="INVALID_PACKET"}}
 override fun onCleared(){ble.stop();super.onCleared()}
}
