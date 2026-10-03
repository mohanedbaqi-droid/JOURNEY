package com.journey.control

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.util.UUID

class JourneyBleManager(private val context:Context, private val onState:(String)->Unit){
 private val adapter=(context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
 private var gatt:BluetoothGatt?=null; private var cmd:BluetoothGattCharacteristic?=null
 private val service=UUID.fromString(JourneyProtocol.SERVICE_UUID); private val command=UUID.fromString(JourneyProtocol.COMMAND_UUID); private val state=UUID.fromString(JourneyProtocol.STATE_UUID)
 @SuppressLint("MissingPermission") fun start(phoneId:String){
  if(Build.VERSION.SDK_INT>=31 && context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)!=PackageManager.PERMISSION_GRANTED)return
  adapter.bluetoothLeScanner?.startScan(object:ScanCallback(){
   override fun onScanResult(t:Int,r:ScanResult){ if(r.scanRecord?.serviceUuids?.any{it.uuid==service}==true){adapter.bluetoothLeScanner.stopScan(this);connect(r.device,phoneId)} }
  })
 }
 @SuppressLint("MissingPermission") private fun connect(d:BluetoothDevice,phoneId:String){gatt=d.connectGatt(context,false,object:BluetoothGattCallback(){
  override fun onConnectionStateChange(g:BluetoothGatt,s:Int,n:Int){if(n==BluetoothProfile.STATE_CONNECTED)g.discoverServices()}
  override fun onServicesDiscovered(g:BluetoothGatt,s:Int){val svc=g.getService(service)?:return;cmd=svc.getCharacteristic(command);val st=svc.getCharacteristic(state)?:return;g.setCharacteristicNotification(st,true);st.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))?.let{it.value=BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE;g.writeDescriptor(it)};send(JourneyProtocol.command(phoneId,"owner_status"))}
  @Deprecated("Deprecated in Java") override fun onCharacteristicChanged(g:BluetoothGatt,c:BluetoothGattCharacteristic){if(c.uuid==state)onState(c.value.toString(Charsets.UTF_8))}
 },BluetoothDevice.TRANSPORT_LE)}
 @SuppressLint("MissingPermission") fun send(payload:String){val c=cmd?:return;c.value=payload.toByteArray();c.writeType=BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT;gatt?.writeCharacteristic(c)}
}
