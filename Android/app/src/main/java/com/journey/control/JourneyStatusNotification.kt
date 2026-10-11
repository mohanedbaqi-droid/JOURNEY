package com.journey.control

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * Android alternative to iOS Live Activity. This is a notification, not a
 * lock-screen widget, and Android controls how much is shown on the lock screen.
 * It reflects last data the app actually received, never an invented BLE link.
 */
object JourneyStatusNotification {
 private const val CHANNEL="journey_vehicle_status"
 private const val ID=8300

 fun cancel(context:Context){
  (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(ID)
 }

 fun update(context:Context,s:VehicleState,demo:Boolean){
  val p=JourneyDemoStore.preferences(context)
  if(!p.getBoolean("lockStatus.enabled",false))return
  if(Build.VERSION.SDK_INT>=33 &&
   context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)return

  val manager=context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  if(Build.VERSION.SDK_INT>=26)
   manager.createNotificationChannel(
    NotificationChannel(CHANNEL,"JOURNEY vehicle status",NotificationManager.IMPORTANCE_LOW).apply {
     description="Vehicle status and demo readings from JOURNEY"
     lockscreenVisibility=Notification.VISIBILITY_PRIVATE
    }
   )

  val title=if(demo)"JOURNEY • DEMO"else if(s.online)"JOURNEY • متصل"else "JOURNEY • غير متصل"
  val doors=if(s.online&&s.doorsValid)listOf(2,4,8,16,32,64).count{s.doorOpen(it)}.toString()else "—"
  val motor=if(s.online&&s.rpmValid)if(s.engineRunning)"شغال"else "مطفأ"else "—"
  val lock=if(s.online)if(s.locked)"مقفلة"else "مفتوحة"else "—"
  val rpm=if(s.online&&s.rpmValid)s.rpm.toString()else "—"
  val summary="القفل: $lock • المحرك: $motor • أبواب: $doors • RPM: $rpm"
  val flags=PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
  fun action(name:String,code:Int)=PendingIntent.getActivity(context,code,
   Intent(context,MainActivity::class.java)
    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    .putExtra(JourneyHomeWidget.EXTRA_ACTION,name),flags)

  val builder=if(Build.VERSION.SDK_INT>=26)Notification.Builder(context,CHANNEL)else Notification.Builder(context)
  manager.notify(ID,builder
   .setSmallIcon(android.R.drawable.ic_lock_lock)
   .setContentTitle(title)
   .setContentText(summary)
   .setStyle(Notification.BigTextStyle().bigText(summary+
    if(demo)" • محاكاة فقط" else " • آخر قراءة وصلتها للتطبيق"))
   .setContentIntent(action("open",8400))
   .addAction(android.R.drawable.ic_lock_idle_unlock,"فتح",action("unlock",8401))
   .addAction(android.R.drawable.ic_lock_lock,"قفل",action("lock",8402))
   .setVisibility(Notification.VISIBILITY_PRIVATE)
   .setAutoCancel(false)
   .setOngoing(false)
   .setOnlyAlertOnce(true)
   .build())
 }
}
