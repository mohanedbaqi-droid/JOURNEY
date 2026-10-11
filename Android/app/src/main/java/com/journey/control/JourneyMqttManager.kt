package com.journey.control

import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import java.util.UUID

/**
 * TLS-only Android cloud transport compatible with the iPhone app:
 * journey/+/state and journey/<deviceId>/cmd.
 *
 * Cloud commands are sent only when the selected ESP has produced a fresh,
 * non-retained state packet and the broker connection is established.
 * A broker ACK means message delivery, not physical button feedback.
 */
class JourneyMqttManager(
 private val onPacket:(String,String)->Unit,
 private val onStatus:(Boolean,String)->Unit
) {
 @Volatile private var client:MqttAsyncClient?=null
 @Volatile private var running=false

 fun connect(host:String,port:Int,username:String,password:String) {
  stop()
  val trimmed=host.trim()
  if(trimmed.isEmpty()||port !in 1..65535||trimmed.contains("/")||trimmed.contains(":")){
   onStatus(false,"MQTT_CONFIG_INVALID")
   return
  }
  try {
   val m=MqttAsyncClient("ssl://$trimmed:$port","journey-android-${UUID.randomUUID()}",MemoryPersistence())
   client=m;running=true
   m.setCallback(object:MqttCallbackExtended {
    override fun connectComplete(reconnect:Boolean,serverURI:String) {
     if(!running||client!==m)return
     runCatching{m.subscribe("journey/+/state",1)}
      .onFailure{onStatus(false,"MQTT_SUBSCRIBE_FAILED")}
     onStatus(true,"MQTT_CONNECTED")
    }
    override fun connectionLost(cause:Throwable?) {
     if(running&&client===m)onStatus(false,"MQTT_DISCONNECTED")
    }
    override fun messageArrived(topic:String,message:MqttMessage) {
     if(!running || client!==m || message.isRetained)return
     val parts=topic.split("/")
     if(parts.size!=3||parts[0]!="journey"||parts[1].isBlank()||parts[2]!="state")return
     if(message.payload.size>32768)return
     onPacket(parts[1],String(message.payload,Charsets.UTF_8))
    }
    override fun deliveryComplete(token:IMqttDeliveryToken?) {}
   })
   val options=MqttConnectOptions().apply {
    isCleanSession=true
    isAutomaticReconnect=true
    connectionTimeout=12
    keepAliveInterval=30
    if(username.isNotBlank())userName=username
    if(password.isNotEmpty())this.password=password.toCharArray()
   }
   onStatus(false,"MQTT_CONNECTING")
   m.connect(options,null,object:IMqttActionListener{
    override fun onSuccess(asyncActionToken:IMqttToken?) {}
    override fun onFailure(asyncActionToken:IMqttToken?,exception:Throwable?) {
     if(running&&client===m)onStatus(false,"MQTT_CONNECTION_FAILED")
    }
   })
  } catch(_:Exception) {
   onStatus(false,"MQTT_CONNECTION_FAILED")
  }
 }

 fun isConnected():Boolean=runCatching{running&&client?.isConnected==true}.getOrDefault(false)

 fun publish(deviceID:String,payload:String):Boolean {
  if(!isConnected() || deviceID.isBlank() ||
     deviceID.any{it=='/'||it=='#'||it=='+'} || payload.length>8192)return false
  val m=client?:return false
  return runCatching{
   m.publish("journey/$deviceID/cmd",MqttMessage(payload.toByteArray(Charsets.UTF_8)).apply{
    qos=1
    isRetained=false
   })
   true
  }.getOrDefault(false)
 }

 fun stop() {
  running=false
  val old=client
  client=null
  if(old!=null){
   runCatching{old.disconnectForcibly()}
   runCatching{old.close()}
  }
  onStatus(false,"MQTT_DISCONNECTED")
 }
}
