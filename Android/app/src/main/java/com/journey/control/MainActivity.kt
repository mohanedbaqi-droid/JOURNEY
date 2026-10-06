package com.journey.control
import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels

class MainActivity:ComponentActivity(){
 private val vm by viewModels<JourneyViewModel>()
 private val permissions=registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()){if(vm.ble.permitted())vm.connect()}
 override fun onCreate(b:Bundle?){super.onCreate(b);setContent{JourneyApp(vm)};requestBle()}
 private fun requestBle(){val p=mutableListOf<String>();if(Build.VERSION.SDK_INT>=31){p+=Manifest.permission.BLUETOOTH_SCAN;p+=Manifest.permission.BLUETOOTH_CONNECT}else if(Build.VERSION.SDK_INT>=23)p+=Manifest.permission.ACCESS_FINE_LOCATION;if(Build.VERSION.SDK_INT>=33)p+=Manifest.permission.POST_NOTIFICATIONS;if(p.isEmpty())vm.connect()else permissions.launch(p.toTypedArray())}
}
