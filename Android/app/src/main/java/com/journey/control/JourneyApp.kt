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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.runtime.saveable.rememberSaveable
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
 val s by vm.state.collectAsState();val en by vm.english.collectAsState();val dark by vm.dark.collectAsState();var tab by rememberSaveable{mutableIntStateOf(2)}
 CompositionLocalProvider(English provides en,LocalLayoutDirection provides if(en)LayoutDirection.Ltr else LayoutDirection.Rtl){
  MaterialTheme(colorScheme=if(dark)darkColorScheme(
   primary=Cyan,onPrimary=Color.Black,primaryContainer=Color(0xFF082D3B),onPrimaryContainer=Cyan,
   background=Color(0xFF02070C),onBackground=Color(0xFFF2F6FA),surface=Color(0xFF09141F),onSurface=Color(0xFFF2F6FA),
   surfaceVariant=Color(0xFF122330),onSurfaceVariant=Color(0xFF98ADB9),outline=Color(0xFF254353),secondary=Cyan,tertiary=Cyan,secondaryContainer=Color(0xFF133C4A),onSecondaryContainer=Cyan,surfaceTint=Color.Transparent,surfaceContainer=Color(0xFF09141F),surfaceContainerLow=Color(0xFF09141F),surfaceContainerHighest=Color(0xFF122330)
  )else lightColorScheme(primary=Color(0xFF006E88),onPrimary=Color.White,primaryContainer=Color(0xFFE0F4FB),onPrimaryContainer=Color(0xFF006078),background=Color(0xFFF2F7FA),surface=Color.White,onSurface=Color(0xFF12232D),surfaceVariant=Color(0xFFE4EEF3),onSurfaceVariant=Color(0xFF536876),outline=Color(0xFFCEDFE7))){
   Scaffold(containerColor=MaterialTheme.colorScheme.background,topBar={Header(vm,s,{tab=5},{tab=6})},bottomBar={Nav(tab){tab=it}}){pad->Box(Modifier.padding(pad).fillMaxSize()){when(tab){0->About(s);1->Obd(vm,s);2->Home(vm,s);3->Car(vm,s);4->MapPage(s);6->Page{EspHealth(s);OtaSettings(vm,s)};else->Settings(vm,s)}}}
  }
 }
}
@Composable private fun Header(vm:JourneyViewModel,s:VehicleState,settings:()->Unit,esp:()->Unit){
 val status by vm.status.collectAsState()
 Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.background).padding(horizontal=16.dp,vertical=6.dp)){
  CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr){
   Row(Modifier.fillMaxWidth(),Arrangement.SpaceBetween,Alignment.CenterVertically){
    IconButton(settings,Modifier.testTag("settings")){Icon(Icons.Default.Menu,L("الإعدادات","Settings"),tint=MaterialTheme.colorScheme.primary)}
    Column(horizontalAlignment=Alignment.CenterHorizontally){Text("J O U R N E Y",fontWeight=FontWeight.Black,style=MaterialTheme.typography.titleLarge);Text(L("سيارة جورني","Journey vehicle"),color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.labelMedium)}
    Column(horizontalAlignment=Alignment.CenterHorizontally){Box(Modifier.size(32.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant),contentAlignment=Alignment.Center){Icon(Icons.Default.Bluetooth,L("البلوتوث","Bluetooth"),tint=if(s.online)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)};TextButton(esp,contentPadding=PaddingValues(0.dp),modifier=Modifier.height(26.dp)){Text("ESP",style=MaterialTheme.typography.labelMedium)}}
   }
  }
  Row(Modifier.fillMaxWidth(),Arrangement.SpaceBetween,Alignment.CenterVertically){
   Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)){Box(Modifier.size(6.dp).background(if(s.online)Color(0xFF40D89C)else Color(0xFF71828D),CircleShape));Text(statusText(status),color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.labelSmall,modifier=Modifier.widthIn(max=240.dp),maxLines=2)}
   if(!s.online)TextButton({vm.connect()},contentPadding=PaddingValues(horizontal=10.dp,vertical=0.dp)){Text(L("ربط ESP","Connect ESP"),style=MaterialTheme.typography.labelMedium)}
  }
 }
}
@Composable private fun statusText(s:String):String=when(s){"CONNECTED"->L("BLE متصل","BLE connected");"SEARCHING"->L("جاري البحث عن ESP","Searching for ESP");"CONNECTING"->L("جاري الربط","Connecting");"SENT_WAITING_ESP"->L("تم الإرسال؛ بانتظار رد ESP","Sent; waiting for ESP");"BLE_PERMISSION"->L("اسمح بالبلوتوث من إعدادات التطبيق","Allow Bluetooth in app settings");"BLE_DISABLED"->L("فعّل البلوتوث","Enable Bluetooth");"NOT_FOUND"->L("لم نجد ESP؛ أعد البحث","ESP not found; search again");"NO_CONNECTION","DISCONNECTED"->L("غير متصل","Disconnected");else->s}
@Composable private fun Nav(sel:Int,set:(Int)->Unit){
 val labels=listOf(L("معلومات","About"),"OBD",L("الرئيسية","Home"),L("السيارة","Car"),L("الخريطة","Map"))
 val icons=listOf(Icons.Default.Info,Icons.Default.Build,Icons.Default.Home,Icons.Default.DirectionsCar,Icons.Default.Map)
 val scheme=MaterialTheme.colorScheme
 Box(Modifier.fillMaxWidth().background(scheme.background).navigationBarsPadding().padding(horizontal=12.dp,vertical=8.dp)){
  CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr){
   Row(Modifier.fillMaxWidth().border(1.dp,scheme.outline.copy(alpha=.6f),RoundedCornerShape(34.dp)).background(scheme.surface,RoundedCornerShape(34.dp)).padding(5.dp),verticalAlignment=Alignment.CenterVertically){
    for(i in labels.indices){
     Column(Modifier.weight(1f).clip(RoundedCornerShape(28.dp)).clickable{set(i)}.testTag("nav_$i").padding(vertical=5.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(3.dp)){
      if(i==2)Box(Modifier.size(46.dp).background(if(sel==i)scheme.primary else scheme.primaryContainer,CircleShape),contentAlignment=Alignment.Center){Icon(icons[i],labels[i],Modifier.size(27.dp),tint=if(sel==i)scheme.onPrimary else scheme.primary)}
      else Icon(icons[i],labels[i],Modifier.size(24.dp),tint=if(sel==i)scheme.primary else scheme.onSurfaceVariant)
      Text(labels[i],color=if(sel==i)scheme.primary else scheme.onSurfaceVariant,style=MaterialTheme.typography.labelSmall,maxLines=1)
     }
    }
   }
  }
 }
}
@Composable private fun Page(content:@Composable ColumnScope.()->Unit)=Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=16.dp,vertical=10.dp),verticalArrangement=Arrangement.spacedBy(16.dp),content=content)
@Composable private fun CardX(title:String,content:@Composable ColumnScope.()->Unit)=Card(
 modifier=Modifier.fillMaxWidth(),shape=RoundedCornerShape(22.dp),border=BorderStroke(1.dp,MaterialTheme.colorScheme.outline.copy(alpha=.6f)),colors=CardDefaults.cardColors(containerColor=MaterialTheme.colorScheme.surface)
){Column(Modifier.fillMaxWidth().padding(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){Text(title,color=MaterialTheme.colorScheme.primary,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleMedium);content()}}
@Composable private fun VehicleHero(vm:JourneyViewModel,s:VehicleState){
 val angled by vm.angled.collectAsState()
 val scheme=MaterialTheme.colorScheme
 Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Brush.verticalGradient(listOf(scheme.surfaceVariant,scheme.background))),verticalArrangement=Arrangement.spacedBy(8.dp)){
  JourneyCarVisual(s,angled)
  Row(Modifier.fillMaxWidth().padding(horizontal=10.dp,vertical=10.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)){
   StatusPill(if(s.online&&s.doorsValid){if(s.locked)L("مقفلة","Locked")else L("مفتوحة","Unlocked")}else L("القفل —","Lock —"),Icons.Default.Lock,Modifier.weight(1f))
   StatusPill(engineText(s),Icons.Default.DirectionsCar,Modifier.weight(1f))
  }
 }
}
@Composable private fun StatusPill(text:String,icon:ImageVector,m:Modifier)=Row(m.background(MaterialTheme.colorScheme.surfaceVariant,RoundedCornerShape(20.dp)).padding(horizontal=10.dp,vertical=9.dp),horizontalArrangement=Arrangement.spacedBy(5.dp),verticalAlignment=Alignment.CenterVertically){Icon(icon,null,Modifier.size(17.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant);Text(text,style=MaterialTheme.typography.labelMedium,maxLines=2,color=MaterialTheme.colorScheme.onSurfaceVariant)}
@Composable private fun Home(vm:JourneyViewModel,s:VehicleState)=Page{VehicleHero(vm,s);Controls(vm,s);Telemetry(s)}
@Composable private fun engineText(s:VehicleState)=if(!s.online||!s.rpmValid)L("المحرك غير متاح","Engine unavailable")else if(s.engineRunning)L("المحرك يعمل","Engine running")else L("المحرك متوقف","Engine stopped")
@Composable private fun Controls(vm:JourneyViewModel,s:VehicleState){
 Column(verticalArrangement=Arrangement.spacedBy(10.dp)){
  Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(10.dp)){Action(L("قفل","Lock"),Icons.Default.Lock,s.online,s.feedbackLock,Modifier.weight(1f)){vm.send("lock")};Action(L("فتح","Unlock"),Icons.Default.LockOpen,s.online,s.feedbackUnlock,Modifier.weight(1f)){vm.send("unlock")}}
  Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(10.dp)){Action(L("تشغيل","Remote start"),Icons.Default.PowerSettingsNew,s.online,s.feedbackStart,Modifier.weight(1f)){vm.send("remote_start")};Action(L("إنذار","Alarm"),Icons.Default.Notifications,s.online,s.feedbackAlarm,Modifier.weight(1f)){vm.send("horn")}}
  val remoteText=if(!s.online)L("غير متصل","Disconnected")else if(s.remotePowered)L("شغالة","On")else L("طافية","Off")
  Action(L("طاقة الريموت","Remote power")+" · "+remoteText,Icons.Default.VpnKey,s.online,s.online&&s.remotePowered,Modifier.fillMaxWidth(),compact=true){vm.send(if(s.remotePowered)"remote_power_off" else "remote_power_on")}
  if(!s.online)Text(L("اربط ESP لتفعيل التحكم والقراءات.","Connect ESP to enable controls and live readings."),color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.bodySmall)
 }
}
@Composable private fun Action(t:String,i:ImageVector,enabled:Boolean,active:Boolean,m:Modifier=Modifier,compact:Boolean=false,on:()->Unit){
 val scheme=MaterialTheme.colorScheme
 OutlinedButton(onClick=on,modifier=m.heightIn(min=if(compact)64.dp else 88.dp),enabled=enabled,shape=RoundedCornerShape(20.dp),border=BorderStroke(1.dp,if(active)Color(0xFF43D79D)else scheme.primary.copy(alpha=if(enabled).6f else .22f)),contentPadding=PaddingValues(horizontal=12.dp,vertical=12.dp),colors=ButtonDefaults.outlinedButtonColors(containerColor=if(active)Color(0xFF0B4737)else scheme.primaryContainer.copy(alpha=.45f),contentColor=scheme.primary,disabledContainerColor=scheme.surface,disabledContentColor=scheme.onSurfaceVariant.copy(alpha=.65f))){
  if(compact){Icon(i,null,Modifier.size(25.dp));Spacer(Modifier.width(12.dp));Text(t,fontWeight=FontWeight.SemiBold,style=MaterialTheme.typography.titleSmall)}
  else Column(horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(6.dp)){Icon(i,null,Modifier.size(27.dp));Text(t,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleMedium)}
 }
}
@Composable private fun Metric(label:String,value:String,unit:String,m:Modifier=Modifier){
 Column(m.background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha=.55f),RoundedCornerShape(16.dp)).padding(12.dp),verticalArrangement=Arrangement.spacedBy(6.dp)){
  CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr){Row(verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(4.dp)){Text(value,fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleLarge);if(unit.isNotEmpty())Text(unit,style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
  Text(label,color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.labelMedium)
 }
}
@Composable private fun Telemetry(s:VehicleState)=CardX(L("بيانات السيارة","Vehicle data")){
 Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)){
  Metric("RPM",if(s.online&&s.rpmValid)s.rpm.toString()else "—","",Modifier.weight(1f))
  Metric(L("السرعة","Speed"),if(s.online&&s.speedValid)s.speed.toString()else "—","km/h",Modifier.weight(1f))
  Metric(L("الحرارة","Coolant"),if(s.online&&s.coolantValid)s.coolant.toString()else "—","°C",Modifier.weight(1f))
 }
 Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)){
  Metric(L("البطارية","Battery"),if(s.online&&s.battery>0)"%.2f".format(java.util.Locale.US,s.battery)else "—","V",Modifier.weight(1f))
  Metric(L("البنزين","Fuel"),if(s.online&&s.fuelValid)s.fuel.toString()else "—","%",Modifier.weight(1f))
 }
 Text(if(s.online)"OBD · ${s.obdStatus}"else L("بانتظار اتصال ESP · — قراءة غير متاحة","Waiting for ESP · — reading unavailable"),color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.labelMedium)
}
@Composable private fun Car(vm:JourneyViewModel,s:VehicleState)=Page{VehicleHero(vm,s);Controls(vm,s);Telemetry(s);CardX(L("آخر حدث","Last event")){Text(if(s.online)s.lastEvent else L("غير متصل","Disconnected"))}}
@Composable private fun MapPage(s:VehicleState)=Page{
 val context=LocalContext.current
 CardX(L("الخريطة والتتبع","Map and tracking")){
  Column(Modifier.fillMaxWidth().padding(vertical=28.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(14.dp)){
   Icon(Icons.Default.LocationOn,null,Modifier.size(52.dp),tint=MaterialTheme.colorScheme.primary)
   Text(if(s.online&&s.gpsValid)"${s.latitude}, ${s.longitude}"else L("بانتظار موقع السيارة","Waiting for vehicle location"),fontWeight=FontWeight.Bold,style=MaterialTheme.typography.titleMedium)
   if(!s.online||!s.gpsValid)Text(L("يظهر الموقع بعد وصول قراءة GPS من الجهاز.","Location appears when the device sends a GPS fix."),color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.bodySmall)
   Button({runCatching{context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("geo:${s.latitude},${s.longitude}?q=${s.latitude},${s.longitude}"))) }},enabled=s.online&&s.gpsValid){Text(L("فتح الخريطة","Open map"))}
  }
 }
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
 EspHealth(s)
 Priority(vm,s)
 WifiSettings(vm,s)
 CellularSettings(vm,s)
 OtaSettings(vm,s)
 AboutContent(s)
}
@Composable private fun EspHealth(s:VehicleState)=CardX(L("صحة ESP","ESP health")){
 InfoRow(L("فيرموير ESP","ESP firmware"),if(s.online)s.firmwareVersion.ifBlank{"—"}else "—")
 val fresh=s.online && s.espTemperature!=null
 InfoRow(L("حرارة شريحة ESP","ESP chip temperature"),if(fresh)"%.1f °C".format(java.util.Locale.US,s.espTemperature)else "—")
 InfoRow(L("بطارية ESP","ESP battery"),if(s.online&&s.espBatteryPercent!=null)"%.0f%% · %.2f V".format(java.util.Locale.US,s.espBatteryPercent,s.espBatteryVoltage)else L("غير متاحة — تحتاج حساس بطارية","Unavailable — battery gauge required"))
 val diagnosis=when{!fresh->L("بانتظار قراءة حرارة فعلية","Waiting for a live temperature reading");s.espThermalLevel>=2->L("حرارة مرتفعة جداً؛ افحص التهوية والتغذية","Very high temperature; check ventilation and power");s.espThermalLevel==1->L("حرارة مرتفعة؛ افحص التهوية","High temperature; check ventilation");else->L("الحرارة دون حد التنبيه","Temperature below warning threshold")}
 Text(diagnosis,color=if(fresh&&s.espThermalLevel>0)Color(0xFFFF9C51)else MaterialTheme.colorScheme.onSurfaceVariant)
 Text(L("تنبيه عند 65°C، وتصعيد عند 80°C. حرارة الشريحة لا تقيس حرارة البطارية أو المقصورة.","Warning at 65°C; escalation at 80°C. Chip temperature does not measure battery or cabin temperature."),style=MaterialTheme.typography.bodySmall)
 if(s.online&&s.espResetReason==9)Text(L("آخر إعادة تشغيل: هبوط تغذية (Brownout)، وليس إثباتاً لعطل حراري.","Last reset: brownout; this does not prove a thermal fault."),color=Color(0xFFFF9C51))
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
 var url by remember{mutableStateOf("https://raw.githubusercontent.com/mohanedbaqi-droid/JOURNEY/main/firmware/v12.77/firmware.bin")};var confirm by remember{mutableStateOf(false)}
 Field(L("رابط firmware.bin","firmware.bin URL"),url){url=it}
 Button({confirm=true},enabled=s.online&&url.startsWith("https://")&&url.endsWith(".bin")){Text(L("تحديث ESP","Update ESP"))}
 Text(L("الـESP يحتاج إنترنت عبر Wi-Fi أو شريحة حتى ينزل الملف.","ESP needs internet through Wi-Fi or SIM to download the file."),style=MaterialTheme.typography.bodySmall)
 if(confirm)AlertDialog({confirm=false},title={Text(L("تثبيت الفيرموير","Install firmware"))},text={Text(url)},confirmButton={TextButton({confirm=false;vm.send("ota_url",JSONObject().put("firmwareURL",url))}){Text(L("تحديث","Update"))}},dismissButton={TextButton({confirm=false}){Text(L("إلغاء","Cancel"))}})
}
@Composable private fun About(s:VehicleState)=Page{
 Column(Modifier.fillMaxWidth().padding(vertical=20.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(8.dp)){
  Icon(Icons.Default.DirectionsCar,null,Modifier.size(50.dp),tint=MaterialTheme.colorScheme.primary)
  Text("JOURNEY",fontWeight=FontWeight.Black,style=MaterialTheme.typography.headlineMedium)
  Text(L("تحكم وبيانات سيارتك","Your vehicle, connected"),color=MaterialTheme.colorScheme.onSurfaceVariant)
 }
 AboutContent(s)
 CardX(L("حول التطبيق","About JOURNEY")){
  Text(L("تصميم وتطوير: مهند الربيعي","Design and development: Mohaned Al-Rubaie"))
  Text(L("التحكم في هذه النسخة عبر BLE محلياً. حالة الأبواب والأضواء تعتمد على القراءات الفعلية المتاحة.","This version connects locally over BLE. Doors and lights use available live readings."),color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.bodyMedium)
 }
}
@Composable private fun InfoRow(label:String,value:String){
 Row(Modifier.fillMaxWidth().padding(vertical=8.dp),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically){Text(label,style=MaterialTheme.typography.bodyMedium);Text(value,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.primary,style=MaterialTheme.typography.bodyMedium)}
}
@Composable private fun AboutContent(s:VehicleState)=CardX(L("النظام والإصدار","System and version")){
 InfoRow(L("إصدار التطبيق","App version"),"${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
 HorizontalDivider(color=MaterialTheme.colorScheme.outline.copy(alpha=.5f))
 InfoRow(L("فيرموير ESP","ESP firmware"),if(!s.online)L("غير متصل","Disconnected")else s.firmwareVersion.ifBlank{L("لم يرسل الجهاز الإصدار","Not reported by device")})
 if(s.online&&s.firmwareVersion.isBlank())Text(L("الرقم يظهر إذا الفيرموير يرسله، بدون افتراض إصدار ثابت.","The version appears when firmware reports it."),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
}
