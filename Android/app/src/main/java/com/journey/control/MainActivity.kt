package com.journey.control

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

class MainActivity:FragmentActivity(){
 private val vm by viewModels<JourneyViewModel>()
 private var pendingAction by mutableStateOf<String?>(null)
 private val permissions=registerForActivityResult(
  ActivityResultContracts.RequestMultiplePermissions()
 ){if(vm.ble.permitted() && !vm.demoEnabled.value)vm.connect()}

 override fun onCreate(b:Bundle?){
  super.onCreate(b)
  handleIntent(intent)
  setContent {
   JourneyApp(vm)
   val selected=pendingAction
   if(selected!=null){
    AlertDialog(onDismissRequest={pendingAction=null},
     title={Text(if(selected=="start")"تأكيد تشغيل السيارة"else "تأكيد الأمر")},
     text={Text(if(selected=="start")
      "التشغيل يحتاج بصمة الجهاز أو رقم القفل. لا يُرسل أمر قبل التأكيد."
      else "هل تريد تنفيذ ${if(selected=="lock")"قفل" else "فتح"} على السيارة المختارة؟")},
     confirmButton={
      TextButton(onClick={
       pendingAction=null
       if(selected=="start")authenticateStart()
       else if(vm.demoEnabled.value)vm.setDemoLocked(selected=="lock")
       else {
        val ok=vm.send(selected)
        if(!ok)Toast.makeText(this,"السيارة غير متصلة؛ لم يُرسل الأمر",Toast.LENGTH_SHORT).show()
       }
      }){Text("تأكيد")}
     },
     dismissButton={TextButton(onClick={pendingAction=null}){Text("إلغاء")}}
    )
   }
  }
  if(!vm.demoEnabled.value)requestBle()
 }

 override fun onNewIntent(intent:Intent){
  super.onNewIntent(intent)
  setIntent(intent)
  handleIntent(intent)
 }

 private fun handleIntent(intent:Intent?){
  val requested=intent?.getStringExtra(JourneyHomeWidget.EXTRA_ACTION)
  if(requested in listOf("lock","unlock","start"))pendingAction=requested
  intent?.removeExtra(JourneyHomeWidget.EXTRA_ACTION)
 }

 fun requestAction(action:String){
  if(action in listOf("lock","unlock","start"))pendingAction=action
 }

 private fun authenticateStart(){
  val authenticators=if(Build.VERSION.SDK_INT>=30)
   BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
  else BiometricManager.Authenticators.BIOMETRIC_STRONG
  if(BiometricManager.from(this).canAuthenticate(authenticators)!=BiometricManager.BIOMETRIC_SUCCESS){
   Toast.makeText(this,"فعّل بصمة الجهاز أو طريقة القفل الآمنة أولاً",Toast.LENGTH_LONG).show()
   return
  }
  val prompt=BiometricPrompt(this,ContextCompat.getMainExecutor(this),
   object:BiometricPrompt.AuthenticationCallback(){
    override fun onAuthenticationSucceeded(result:BiometricPrompt.AuthenticationResult){
     super.onAuthenticationSucceeded(result)
     if(!vm.authorizedStart())Toast.makeText(this@MainActivity,
      "تعذر تنفيذ التشغيل؛ تأكد من اتصال ESP",Toast.LENGTH_LONG).show()
    }
    override fun onAuthenticationError(errorCode:Int,errString:CharSequence){
     super.onAuthenticationError(errorCode,errString)
     Toast.makeText(this@MainActivity,"أُلغي التشغيل — لم يُرسل أمر",Toast.LENGTH_SHORT).show()
    }
   }
  )
  val info=BiometricPrompt.PromptInfo.Builder()
   .setTitle("JOURNEY — تأكيد التشغيل")
   .setSubtitle("لن يبدأ المحرك بدون المصادقة")
   .setAllowedAuthenticators(authenticators)
   .apply {if(Build.VERSION.SDK_INT<30)setNegativeButtonText("إلغاء")}
   .build()
  prompt.authenticate(info)
 }

 private fun requestBle(){
  val p=mutableListOf<String>()
  if(Build.VERSION.SDK_INT>=31){
   p+=Manifest.permission.BLUETOOTH_SCAN;p+=Manifest.permission.BLUETOOTH_CONNECT
  }else if(Build.VERSION.SDK_INT>=23)p+=Manifest.permission.ACCESS_FINE_LOCATION
  if(Build.VERSION.SDK_INT>=33)p+=Manifest.permission.POST_NOTIFICATIONS
  if(p.isEmpty())vm.connect()else permissions.launch(p.toTypedArray())
 }
}
