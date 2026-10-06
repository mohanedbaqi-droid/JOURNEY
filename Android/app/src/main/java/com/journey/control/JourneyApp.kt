package com.journey.control

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.*
import org.json.JSONArray
import org.json.JSONObject

private val Cyan=Color(0xFF35D9FF)
private val English=staticCompositionLocalOf{false}
@Composable private fun L(ar:String,en:String)=if(English.current)en else ar
@Composable fun JourneyApp(vm:JourneyViewModel){
 val s by vm.state.collectAsState();val en by vm.english.collectAsState();val dark by vm.dark.collectAsState();var tab by remember{mutableIntStateOf(2)}
 CompositionLocalProvider(English provides en,LocalLayoutDirection provides if(en)LayoutDirection.Ltr else LayoutDirection.Rtl){
  MaterialTheme(colorScheme=if(dark)darkColorScheme(primary=Cyan,background=Color.Black,surface=Color(0xFF06121E))else lightColorScheme(primary=Color(0xFF006881),surface=Color(0xFFECF5F8))){
   Scaffold(topBar={Header(vm,s){tab=5}},bottomBar={Nav(tab){tab=it}}){pad->Box(Modifier.padding(pad).fillMaxSize()){when(tab){0->About();1->Obd(vm,s);2->Home(vm,s);3->Car(vm,s);4->MapPage(s);else->Settings(vm,s)}}}
  }
 }
}
@Composable private fun Header(vm:JourneyViewModel,s:VehicleState,settings:()->Unit){
 val status by vm.status.collectAsState()
 Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.background).padding(horizontal=16.dp,vertical=8.dp)){
  Row(Modifier.fillMaxWidth(),Arrangement.SpaceBetween,Alignment.CenterVertically){IconButton(settings){Icon(Icons.Default.Menu,L("الإعدادات","Settings"),tint=Cyan)};Column(horizontalAlignment=Alignment.CenterHorizontally){Text("J O U R N E Y",fontWeight=FontWeight.Black,style=MaterialTheme.typography.headlineSmall);Text(L("سيارة جورني","Journey vehicle"),style=MaterialTheme.typography.labelMedium)};Icon(Icons.Default.Bluetooth,null,tint=if(s.online)Cyan else Color.Gray)}
  Text(statusText(status),color=if(s.online)Cyan else MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.labelSmall)
 }
}
@Composable private fun statusText(s:String):String=when(s){"CONNECTED"->L("BLE متصل","BLE connected");"SEARCHING"->L("جاري البحث عن ESP","Searching for ESP");"CONNECTING"->L("جاري الربط","Connecting");"SENT_WAITING_ESP"->L("تم الإرسال؛ بانتظار رد ESP","Sent; waiting for ESP");"BLE_PERMISSION"->L("اسمح بالبلوتوث من إعدادات التطبيق","Allow Bluetooth in app settings");"BLE_DISABLED"->L("فعّل البلوتوث","Enable Bluetooth");"NOT_FOUND"->L("لم نجد ESP؛ أعد البحث","ESP not found; search again");"NO_CONNECTION","DISCONNECTED"->L("غير متصل","Disconnected");else->s}
@Composable private fun Nav(sel:Int,set:(Int)->Unit)=NavigationBar{
 listOf(L("معلومات","About") to Icons.Default.Info,"OBD" to Icons.Default.Build,L("الرئيسية","Home") to Icons.Default.Home,L("السيارة","Car") to Icons.Default.DirectionsCar,L("الخريطة","Map") to Icons.Default.Map).forEachIndexed{i,x->NavigationBarItem(selected=sel==i,onClick={set(i)},icon={Icon(x.second,null)},label={Text(x.first,maxLines=1)},alwaysShowLabel=true)}
}
@Composable private fun Page(content:@Composable ColumnScope.()->Unit)=Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),verticalArrangement=Arrangement.spacedBy(14.dp),content=content)
@Composable private fun CardX(title:String,content:@Composable ColumnScope.()->Unit)=Card(shape=RoundedCornerShape(22.dp)){Column(Modifier.fillMaxWidth().padding(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)){Text(title,color=MaterialTheme.colorScheme.primary,fontWeight=FontWeight.Bold);content()}}
@Composable private fun Home(vm:JourneyViewModel,s:VehicleState)=Page{
 val angled by vm.angled.collectAsState()
 JourneyCarVisual(s,angled)
 Row(Modifier.fillMaxWidth(),Arrangement.SpaceEvenly){Text(if(s.online&&s.doorsValid){if(s.locked)L("مقفلة","Locked")else L("مفتوحة","Unlocked")}else L("القفل غير متاح","Lock unavailable"));Text(engineText(s))}
 Controls(vm,s);Telemetry(s)
}
@Composable private fun engineText(s:VehicleState)=if(!s.online||!s.rpmValid)L("المحرك غير متاح","Engine unavailable")else if(s.engineRunning)L("المحرك يعمل","Engine running")else L("المحرك متوقف","Engine stopped")
@Composable private fun Controls(vm:JourneyViewModel,s:VehicleState)=CardX(L("التحكم","Controls")){
 Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)){Action(L("قفل","Lock"),Icons.Default.Lock,s.online,s.feedbackLock,Modifier.weight(1f)){vm.send("lock")};Action(L("فتح","Unlock"),Icons.Default.LockOpen,s.online,s.feedbackUnlock,Modifier.weight(1f)){vm.send("unlock")}}
 Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)){Action(L("تشغيل","Remote start"),Icons.Default.PowerSettingsNew,s.online,s.feedbackStart,Modifier.weight(1f)){vm.send("remote_start")};Action(L("إنذار","Alarm"),Icons.Default.Notifications,s.online,s.feedbackAlarm,Modifier.weight(1f)){vm.send("horn")}}
 Action(L("طاقة الريموت","Remote power")+": "+if(s.online&&s.remotePowered)L("شغالة","On")else L("طافية","Off"),Icons.Default.VpnKey,s.online,s.online&&s.remotePowered,Modifier.fillMaxWidth()){vm.send(if(s.remotePowered)"remote_power_off" else "remote_power_on")}
 Text(L("الأخضر يؤكد خرج ESP؛ لا يؤكد حركة قفل السيارة.","Green confirms the ESP output; vehicle lock status comes from OBD."),style=MaterialTheme.typography.bodySmall)
}
@Composable private fun Action(t:String,i:ImageVector,enabled:Boolean,active:Boolean,m:Modifier=Modifier,on:()->Unit)=Button(on,m.heightIn(min=58.dp),enabled=enabled,colors=ButtonDefaults.buttonColors(containerColor=if(active)Color(0xFF158044)else MaterialTheme.colorScheme.primaryContainer,contentColor=if(active)Color.White else MaterialTheme.colorScheme.onPrimaryContainer)){Icon(i,null);Spacer(Modifier.width(6.dp));Text(t)}
@Composable private fun Telemetry(s:VehicleState)=CardX(L("بيانات السيارة","Vehicle data")){
 val na=L("غير متاح","Unavailable")
 Text("RPM: ${if(s.online&&s.rpmValid)s.rpm.toString()else na}   •   ${if(s.online&&s.speedValid)"${s.speed} km/h" else na}")
 Text(L("حرارة","Coolant")+": "+if(s.online&&s.coolantValid)"${s.coolant}°C"else na)
 Text(L("البطارية","Battery")+": "+if(s.online&&s.battery>0)"%.2f V".format(s.battery)else na)
 Text(L("بنزين","Fuel")+": "+if(s.online&&s.fuelValid)"${s.fuel}%"else na)
 Text("OBD: ${if(s.online)s.obdStatus else na}")
}
@Composable private fun Car(vm:JourneyViewModel,s:VehicleState)=Page{
 val angled by vm.angled.collectAsState();JourneyCarVisual(s,angled);Controls(vm,s);Telemetry(s)
 CardX(L("آخر حدث","Last event")){Text(s.lastEvent)}
}
@Composable private fun MapPage(s:VehicleState)=Page{
 val context=LocalContext.current
 CardX(L("الخريطة والتتبع","Map and tracking")){Text(if(s.online&&s.gpsValid)"${s.latitude}, ${s.longitude}"else L("بانتظار قراءة GPS حقيقية","Waiting for a real GPS fix"));Button({runCatching{context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("geo:${s.latitude},${s.longitude}?q=${s.latitude},${s.longitude}"))) }},enabled=s.online&&s.gpsValid){Text(L("فتح الخريطة","Open map"))}}
}
@Composable private fun Obd(vm:JourneyViewModel,s:VehicleState)=Page{
 var name by remember{mutableStateOf("KONNWEI")};var wifi by remember{mutableStateOf(false)};var password by remember{mutableStateOf("")};var clear by remember{mutableStateOf(false)}
 Telemetry(s)
 CardX(L("قطعة OBD","OBD adapter")){
  Row{FilterChip(!wifi,{wifi=false},{Text("BLE")});Spacer(Modifier.width(8.dp));FilterChip(wifi,{wifi=true},{Text("Wi-Fi")})}
  Field(L("اسم القطعة / الشبكة","Adapter / SSID"),name){name=it};if(wifi)SecretField(L("كلمة المرور","Password"),password){password=it}
  Button({vm.send("obd_search",JSONObject().put("obdAdapter",JSONObject().put("transport",if(wifi)"WIFI"else "BLE")))},enabled=s.online){Text(L("بحث من ESP","Scan from ESP"))}
  if(s.adapterList.isNotEmpty())Text(s.adapterList,style=MaterialTheme.typography.bodySmall)
  Button({vm.send("obd_select",JSONObject().put("obdAdapter",JSONObject().put("name",name).put("transport",if(wifi)"WIFI"else "BLE").put("password",password).put("host","192.168.0.10").put("port",35000)))},enabled=s.online&&name.isNotBlank()){Text(L("حفظ وربط","Save and connect"))}
 }
 CardX(L("الأعطال","Diagnostics")){Text(s.dtc.ifBlank{L("لم يُطلب فحص بعد","No scan requested yet")});Button({vm.send("obd_scan_dtc")},enabled=s.online){Text(L("قراءة الأعطال","Read DTCs"))};OutlinedButton({clear=true},enabled=s.online){Text(L("مسح الأعطال","Clear DTCs"))};if(s.diagnostics.isNotBlank())Text(s.diagnostics,style=MaterialTheme.typography.bodySmall)}
 if(clear)AlertDialog({clear=false},title={Text(L("تأكيد مسح الأعطال","Confirm clear DTCs"))},text={Text(L("يمسح رموز الأعطال وقد يصفر جاهزية فحص الانبعاثات.","Clears trouble codes and may reset emissions readiness."))},confirmButton={TextButton({clear=false;vm.send("obd_clear_dtc",JSONObject().put("obdClearConfirmed",true))}){Text(L("مسح","Clear"))}},dismissButton={TextButton({clear=false}){Text(L("إلغاء","Cancel"))}})
}
@Composable private fun Field(label:String,value:String,on:(String)->Unit)=OutlinedTextField(value,on,label={Text(label)},modifier=Modifier.fillMaxWidth(),singleLine=true)
@Composable private fun SecretField(label:String,value:String,on:(String)->Unit)=OutlinedTextField(value,on,label={Text(label)},modifier=Modifier.fillMaxWidth(),singleLine=true,visualTransformation=PasswordVisualTransformation())
@Composable private fun Settings(vm:JourneyViewModel,s:VehicleState)=Page{
 val en by vm.english.collectAsState();val angled by vm.angled.collectAsState();val dark by vm.dark.collectAsState()
 CardX(L("واجهة التطبيق","Appearance")){
  Row(Modifier.fillMaxWidth(),Arrangement.SpaceBetween,Alignment.CenterVertically){Text("English");Switch(en,{vm.setLanguage(it)})}
  Row(Modifier.fillMaxWidth(),Arrangement.SpaceBetween,Alignment.CenterVertically){Text(L("الوضع الداكن","Dark mode"));Switch(dark,{vm.setDark(it)})}
  Row(Modifier.fillMaxWidth(),Arrangement.SpaceBetween,Alignment.CenterVertically){Text(L("نموذج السيارة الجانبي","Angled car model"));Switch(angled,{vm.setAppearance(it)})}
 }
 CardX(L("الربط والمالك","Connection and owner")){
  Text(L("التحكم بهذا الإصدار عبر BLE محلياً.","This version controls the ESP locally over BLE."))
  Button({vm.connect()}){Text(L("بحث وإعادة ربط ESP","Search / reconnect ESP"))}
  Text(L("أجهزة مسجلة: ","Registered phones: ")+s.ownerCount)
  Text(L("معرّف هذا الهاتف: ","This phone ID: ")+vm.phoneId,style=MaterialTheme.typography.bodySmall)
  Button({vm.send("owner_register")},enabled=s.online){Text(L("تسجيل / طلب موافقة المالك","Enroll / request owner approval"))}
  if(s.pendingPhone.isNotBlank()&&s.adminPhone==vm.phoneId){Text(s.pendingPhone);Button({vm.send("owner_approve",JSONObject().put("ownerTarget",s.pendingPhone))}){Text(L("موافقة","Approve"))}}
 }
 Priority(vm,s)
 WifiSettings(vm,s)
 CellularSettings(vm,s)
 OtaSettings(vm,s)
 AboutContent()
}
@Composable private fun Priority(vm:JourneyViewModel,s:VehicleState)=CardX(L("أولوية الاتصال داخل ESP","ESP route priority")){
 var order by remember(s.connectionPriority){mutableStateOf(s.connectionPriority.split(',').filter{it in listOf("BLE","WIFI","CELLULAR")}.ifEmpty{listOf("CELLULAR","WIFI","BLE")})}
 for(i in order.indices)Row(Modifier.fillMaxWidth(),Arrangement.SpaceBetween,Alignment.CenterVertically){Text("${i+1}. ${order[i]}");Row{IconButton({order=order.toMutableList().also{java.util.Collections.swap(it,i,i-1)}},enabled=i>0){Icon(Icons.Default.KeyboardArrowUp,null)};IconButton({order=order.toMutableList().also{java.util.Collections.swap(it,i,i+1)}},enabled=i<order.lastIndex){Icon(Icons.Default.KeyboardArrowDown,null)}}}
 Button({vm.send("connection_priority",JSONObject().put("connectionPriority",JSONObject().put("order",JSONArray(order))))},enabled=s.online&&order.size==3){Text(L("حفظ الأولوية","Save priority"))}
 Text(L("خلي BLE أولاً للفحص المحلي إذا ESP متصل بالسيرفر.","Put BLE first for local testing when the ESP is connected to the server."),style=MaterialTheme.typography.bodySmall)
}
@Composable private fun WifiSettings(vm:JourneyViewModel,s:VehicleState)=CardX(L("Wi-Fi في ESP","ESP Wi-Fi")){
 var ssid by remember{mutableStateOf("")};var pass by remember{mutableStateOf("")}
 Text("${s.wifiSsid} • ${s.wifiStatus}");Field("SSID",ssid){ssid=it};SecretField(L("كلمة المرور","Password"),pass){pass=it}
 Button({vm.send("wifi_search")},enabled=s.online){Text(L("بحث الشبكات","Scan networks"))};if(s.wifiList.isNotBlank())Text(s.wifiList)
 Button({vm.send("wifi_config",JSONObject().put("wifiSettings",JSONObject().put("enabled",true).put("ssid",ssid).put("password",pass)))},enabled=s.online&&ssid.isNotBlank()){Text(L("حفظ وتشغيل","Save and enable"))}
 OutlinedButton({vm.send("wifi_config",JSONObject().put("wifiSettings",JSONObject().put("enabled",false)))},enabled=s.online){Text(L("إطفاء Wi-Fi","Disable Wi-Fi"))}
}
@Composable private fun CellularSettings(vm:JourneyViewModel,s:VehicleState)=CardX(L("الشريحة و4G","SIM and 4G")){
 var apn by remember{mutableStateOf("internet")}
 Text("${s.cellularNetwork} • ${s.cellularStatus}");Field("APN",apn){apn=it}
 Button({vm.send("cellular_config",JSONObject().put("cellularSettings",JSONObject().put("enabled",true).put("apn",apn).put("username","").put("password","").put("simPin","").put("hotspotEnabled",s.hotspotEnabled)))},enabled=s.online){Text(L("حفظ وتشغيل الشريحة","Save and enable SIM"))}
 OutlinedButton({vm.send("cellular_config",JSONObject().put("cellularSettings",JSONObject().put("enabled",false)))},enabled=s.online){Text(L("إطفاء الشريحة","Disable SIM"))}
}
@Composable private fun OtaSettings(vm:JourneyViewModel,s:VehicleState)=CardX(L("تحديث ESP عبر الإنترنت","ESP internet update")){
 var url by remember{mutableStateOf("https://raw.githubusercontent.com/mohanedbaqi-droid/JOURNEY/main/firmware/v12.76/firmware.bin")};var confirm by remember{mutableStateOf(false)}
 Field(L("رابط firmware.bin","firmware.bin URL"),url){url=it}
 Button({confirm=true},enabled=s.online&&url.startsWith("https://")&&url.endsWith(".bin")){Text(L("تحديث ESP","Update ESP"))}
 Text(L("الـESP يحتاج إنترنت عبر Wi-Fi أو شريحة حتى ينزل الملف.","ESP needs internet through Wi-Fi or SIM to download the file."),style=MaterialTheme.typography.bodySmall)
 if(confirm)AlertDialog({confirm=false},title={Text(L("تثبيت الفيرموير","Install firmware"))},text={Text(url)},confirmButton={TextButton({confirm=false;vm.send("ota_url",JSONObject().put("firmwareURL",url))}){Text(L("تحديث","Update"))}},dismissButton={TextButton({confirm=false}){Text(L("إلغاء","Cancel"))}})
}
@Composable private fun About()=Page{AboutContent()}
@Composable private fun AboutContent()=CardX(L("النظام والمعلومات","System and about")){
 Text("JOURNEY ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})");Text("ESP v12.76")
 Text(L("تصميم: مهند الربيعي","Design: Mohaned Al-Rubaie"))
 Text(L("قراءات الأبواب والأضواء من OBD. الخلفي جهة السائق غير مثبت بالفحص.","Doors and lights come from OBD. Driver rear door was not verified in the vehicle tests."),style=MaterialTheme.typography.bodySmall)
}
