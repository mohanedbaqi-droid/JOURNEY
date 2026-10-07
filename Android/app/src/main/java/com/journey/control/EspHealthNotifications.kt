package com.journey.control
import android.app.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
object EspHealthNotifications {
 fun show(c:Context,s:VehicleState,en:Boolean){
  if(Build.VERSION.SDK_INT>=33&&c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)return
  val manager=c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  if(Build.VERSION.SDK_INT>=26)manager.createNotificationChannel(NotificationChannel("esp_heat","ESP temperature",NotificationManager.IMPORTANCE_HIGH))
  val builder=if(Build.VERSION.SDK_INT>=26)Notification.Builder(c,"esp_heat")else Notification.Builder(c)
  val title=if(en)"ESP temperature warning"else "تنبيه حرارة ESP"
  val text=if(en)"Chip temperature ${s.espTemperature}°C. Check ventilation and power."else "حرارة الشريحة ${s.espTemperature}°C. افحص التهوية والتغذية."
  manager.notify(7701,builder.setSmallIcon(android.R.drawable.stat_notify_error).setContentTitle(title).setContentText(text).setAutoCancel(true).build())
 }
}
