package com.journey.control

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.util.UUID
import java.util.ArrayDeque

/** All GATT operations are serialized; a successful write is never actuator feedback. */
@SuppressLint("MissingPermission")
class JourneyBleManager(private val context:Context, private val onState:(String)->Unit, private val onStatus:(Boolean,String)->Unit){
 private val handler=Handler(Looper.getMainLooper())
 private val adapter=(context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
 private var gatt:BluetoothGatt?=null
 private var cmd:BluetoothGattCharacteristic?=null
 private var scan:ScanCallback?=null
 private val queue=ArrayDeque<ByteArray>()
 private var busy=false
 private var mtu=23
 private var phoneId=""
 private var active=false
 private var ready=false
 private var discovering=false
 private var scanTimeout:Runnable?=null
 private var writeTimeout:Runnable?=null
 private val service=UUID.fromString(JourneyProtocol.SERVICE_UUID)
 private val command=UUID.fromString(JourneyProtocol.COMMAND_UUID)
 private val state=UUID.fromString(JourneyProtocol.STATE_UUID)
 fun permitted():Boolean=Build.VERSION.SDK_INT<31 || (context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)==PackageManager.PERMISSION_GRANTED && context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED)
 fun start(id:String){handler.post{
  if(!permitted()){onStatus(false,"BLE_PERMISSION");return@post}
  if(adapter?.isEnabled!=true){onStatus(false,"BLE_DISABLED");return@post}
  stopScan();closeGatt();phoneId=id;active=true
  onStatus(false,"SEARCHING")
  val scanner=adapter.bluetoothLeScanner ?: return@post
  val callback=object:ScanCallback(){
   override fun onScanResult(type:Int,r:ScanResult){handler.post{if(scan===this){stopScan();connect(r.device)}}}
   override fun onScanFailed(error:Int){handler.post{stopScan();onStatus(false,"SCAN_ERROR_$error")}}
  };scan=callback
  runCatching{scanner.startScan(listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(service)).build()),ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),callback)}.onFailure{stopScan();onStatus(false,"SCAN_ERROR")}
  scanTimeout=Runnable{if(scan!=null){stopScan();onStatus(false,"NOT_FOUND")}}.also{handler.postDelayed(it,20000)}
 }}
 private fun stopScan(){scanTimeout?.let{handler.removeCallbacks(it)};scan?.let{if(permitted())runCatching{adapter?.bluetoothLeScanner?.stopScan(it)}};scan=null}
 private fun closeGatt(){ready=false;cmd=null;queue.clear();busy=false;discovering=false;mtu=23;writeTimeout?.let{handler.removeCallbacks(it)};if(permitted())runCatching{gatt?.disconnect();gatt?.close()};gatt=null}
 fun stop(){handler.post{active=false;stopScan();closeGatt();onStatus(false,"DISCONNECTED")}}
 private fun connect(device:BluetoothDevice){onStatus(false,"CONNECTING");gatt=device.connectGatt(context,false,callback)}
 private fun discover(g:BluetoothGatt){if(!discovering){discovering=true;if(!g.discoverServices())fail(g,"DISCOVERY_FAILED")}}
 private fun fail(g:BluetoothGatt,message:String){if(g!==gatt)return;closeGatt();onStatus(false,message);if(active)handler.postDelayed({if(active&&gatt==null&&scan==null)start(phoneId)},6000)}
 private val callback=object:BluetoothGattCallback(){
  override fun onConnectionStateChange(g:BluetoothGatt,status:Int,newState:Int){handler.post{
   if(g!==gatt){g.close();return@post}
   if(status==BluetoothGatt.GATT_SUCCESS && newState==BluetoothProfile.STATE_CONNECTED){if(!g.requestMtu(517))discover(g) else handler.postDelayed({if(g===gatt&&!discovering)discover(g)},3000)}
   else if(newState==BluetoothProfile.STATE_DISCONNECTED||status!=BluetoothGatt.GATT_SUCCESS)fail(g,"DISCONNECTED")
  }}
  override fun onMtuChanged(g:BluetoothGatt,newMtu:Int,status:Int){handler.post{if(g===gatt){if(status==BluetoothGatt.GATT_SUCCESS)mtu=newMtu;discover(g)}}}
  override fun onServicesDiscovered(g:BluetoothGatt,status:Int){handler.post{
   if(g!==gatt)return@post
   val svc=g.getService(service);cmd=svc?.getCharacteristic(command);val st=svc?.getCharacteristic(state)
   if(status!=BluetoothGatt.GATT_SUCCESS||cmd==null||st==null){fail(g,"SERVICE_MISSING");return@post}
   val descriptor=st.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))
   if(descriptor==null||!g.setCharacteristicNotification(st,true)){fail(g,"NOTIFICATIONS_FAILED");return@post}
   val ok=if(Build.VERSION.SDK_INT>=33)g.writeDescriptor(descriptor,BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)==BluetoothStatusCodes.SUCCESS else {descriptor.value=BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE;g.writeDescriptor(descriptor)}
   if(!ok)fail(g,"NOTIFICATIONS_FAILED")
  }}
  override fun onDescriptorWrite(g:BluetoothGatt,d:BluetoothGattDescriptor,status:Int){handler.post{
   if(g!==gatt)return@post
   if(status!=BluetoothGatt.GATT_SUCCESS){fail(g,"NOTIFICATIONS_FAILED");return@post}
   ready=true;onStatus(true,"CONNECTED");send(JourneyProtocol.command(phoneId,"owner_status"))
  }}
  @Deprecated("Deprecated in Java") override fun onCharacteristicChanged(g:BluetoothGatt,c:BluetoothGattCharacteristic){val bytes=c.value?.clone()?:return;deliver(g,c.uuid,bytes)}
  override fun onCharacteristicChanged(g:BluetoothGatt,c:BluetoothGattCharacteristic,value:ByteArray){deliver(g,c.uuid,value.clone())}
  override fun onCharacteristicWrite(g:BluetoothGatt,c:BluetoothGattCharacteristic,status:Int){handler.post{if(g===gatt){writeTimeout?.let{handler.removeCallbacks(it)};busy=false;if(status!=BluetoothGatt.GATT_SUCCESS){queue.clear();onStatus(true,"WRITE_FAILED")}else drain()}}}
 }
 private fun deliver(g:BluetoothGatt,id:UUID,value:ByteArray){handler.post{if(g===gatt&&id==state)onState(value.toString(Charsets.UTF_8))}}
 fun send(payload:String):Boolean {
  if(!ready||!permitted())return false
  val bytes=payload.toByteArray(Charsets.UTF_8)
  if(bytes.size>512||bytes.size>mtu-3){onStatus(true,"MTU_TOO_SMALL");return false}
  if(queue.size>=12){onStatus(true,"COMMAND_QUEUE_FULL");return false}
  queue.add(bytes);drain();return true
 }
 private fun drain(){
  if(busy||queue.isEmpty()||!ready)return
  val g=gatt?:return;val c=cmd?:return;val bytes=queue.removeFirst();busy=true
  val ok=if(Build.VERSION.SDK_INT>=33)g.writeCharacteristic(c,bytes,BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)==BluetoothStatusCodes.SUCCESS else {c.value=bytes;c.writeType=BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT;g.writeCharacteristic(c)}
  if(!ok){busy=false;queue.clear();onStatus(true,"WRITE_FAILED");return}
  writeTimeout=Runnable{if(g===gatt&&busy)fail(g,"WRITE_TIMEOUT")}.also{handler.postDelayed(it,5000)}
 }
}
