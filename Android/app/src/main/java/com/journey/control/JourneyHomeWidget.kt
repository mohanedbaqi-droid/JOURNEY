package com.journey.control

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONObject

/** Plain Android RemoteViews: no Apple-style App Group, no Keychain and no
 * background BLE control from a widget process. The demo buttons change
 * local preferences directly; real controls ask the foreground app to act.
 */
open class JourneyHomeWidget : AppWidgetProvider() {
    override fun onUpdate(context:Context,manager:AppWidgetManager,ids:IntArray) {
        ids.forEach { id -> update(context,manager,id,this::class.java) }
    }
    override fun onReceive(context:Context,intent:Intent) {
        super.onReceive(context,intent)
        when(intent.action) {
            ACTION_DEMO_LOCK,ACTION_DEMO_UNLOCK -> {
                if(JourneyDemoStore.enabled(context)) {
                    val p=JourneyDemoStore.preferences(context)
                    JourneyDemoStore.save(
                        p,JourneyDemoStore.read(p).copy(locked=intent.action==ACTION_DEMO_LOCK)
                    )
                    refreshAll(context)
                }
            }
            ACTION_REFRESH -> refreshAll(context)
        }
    }

    companion object {
        const val ACTION_DEMO_LOCK="com.journey.control.DEMO_LOCK"
        const val ACTION_DEMO_UNLOCK="com.journey.control.DEMO_UNLOCK"
        const val ACTION_REFRESH="com.journey.control.WIDGET_REFRESH"
        const val EXTRA_ACTION="journey.widget.action"
        private const val LAST_STATE="widget.lastState"
        private const val LAST_STATE_AT="widget.lastStateAt"
        private val classes=arrayOf(JourneyHomeWidget::class.java,JourneyLargeWidget::class.java)

        fun storeRealState(context:Context,s:VehicleState) {
            if(JourneyDemoStore.enabled(context)) return
            val v=JSONObject()
            v.put("online",s.online)
            v.put("locked",s.locked)
            v.put("engine",s.engineRunning)
            v.put("rpm",if(s.rpmValid)s.rpm else JSONObject.NULL)
            v.put("coolant",if(s.coolantValid)s.coolant else JSONObject.NULL)
            v.put("battery",if(s.battery>0)s.battery else JSONObject.NULL)
            v.put("doors",if(s.doorsValid)s.doorOpenMask else JSONObject.NULL)
            v.put("doorKnown",if(s.doorsValid)s.doorKnownMask else JSONObject.NULL)
            v.put("parking",if(s.parkingLightsValid)s.parkingLightsOn else JSONObject.NULL)
            v.put("remotePower",s.remotePowered)
            v.put("fuel",if(s.fuelValid)s.fuel else JSONObject.NULL)
            v.put("espTemperature",s.espTemperature?:JSONObject.NULL)
            v.put("espBattery",s.espBatteryPercent?:JSONObject.NULL)
            v.put("lowBeam",if(s.lightsValid)s.headlightsOn else JSONObject.NULL)
            v.put("leftTurn",if(s.turnsValid)s.leftSignal else JSONObject.NULL)
            v.put("rightTurn",if(s.turnsValid)s.rightSignal else JSONObject.NULL)
            // Last observation is for freshness, not a claim that the car is
            // presently connected while Android has stopped the app.
            val prefs=JourneyDemoStore.preferences(context)
            prefs.edit().putString(LAST_STATE,v.toString())
                .putLong(LAST_STATE_AT,System.currentTimeMillis()).apply()
            refreshAll(context)
        }

        fun refreshAll(context:Context) {
            val manager=AppWidgetManager.getInstance(context)
            classes.forEach { kind ->
                val ids=manager.getAppWidgetIds(ComponentName(context,kind))
                ids.forEach { id -> update(context,manager,id,kind) }
            }
        }

        private fun update(ctx:Context,manager:AppWidgetManager,id:Int,kind:Class<*>) {
            val large=kind==JourneyLargeWidget::class.java
            val p=JourneyDemoStore.preferences(ctx)
            val demo=p.getBoolean(JourneyDemoStore.ENABLED,false)
            val status:VehicleState
            val fresh:Boolean
            if(demo) {
                status=JourneyDemoStore.read(p).toVehicleState()
                fresh=true
            } else {
                val elapsed=System.currentTimeMillis()-p.getLong(LAST_STATE_AT,0L)
                fresh=elapsed in 0..12000
                val j=runCatching{JSONObject(p.getString(LAST_STATE,"{}")?:"{}")}.getOrDefault(JSONObject())
                status=VehicleState(
                    online=fresh && j.optBoolean("online"),
                    locked=j.optBoolean("locked",true),
                    engineRunning=fresh && j.optBoolean("engine"),
                    rpm=j.optInt("rpm",0),
                    rpmValid=fresh && !j.isNull("rpm") && j.has("rpm"),
                    coolant=j.optInt("coolant",0),
                    coolantValid=fresh && !j.isNull("coolant") && j.has("coolant"),
                    battery=if(fresh)j.optDouble("battery",0.0)else 0.0,
                    doorOpenMask=j.optInt("doors",0),
                    doorKnownMask=j.optInt("doorKnown",0),
                    doorsValid=fresh && !j.isNull("doors") && j.has("doors"),
                    headlightsOn=j.optBoolean("lowBeam"),
                    lightsValid=fresh && !j.isNull("lowBeam") && j.has("lowBeam"),
                    parkingLightsOn=j.optBoolean("parking"),
                    parkingLightsValid=fresh && !j.isNull("parking") && j.has("parking"),
                    remotePowered=j.optBoolean("remotePower"),
                    turnsValid=fresh && !j.isNull("leftTurn") && j.has("leftTurn"),
                    leftSignal=j.optBoolean("leftTurn"),
                    rightSignal=j.optBoolean("rightTurn"),
                    fuel=j.optInt("fuel",0),
                    fuelValid=fresh && !j.isNull("fuel") && j.has("fuel"),
                    espTemperature=if(fresh)j.optDouble("espTemperature").takeIf{it.isFinite()}else null,
                    espBatteryPercent=if(fresh)j.optDouble("espBattery").takeIf{it.isFinite()}else null
                )
            }
            val remote=RemoteViews(ctx.packageName,
                if(large)R.layout.journey_widget_large else R.layout.journey_widget_small)
            remote.setTextViewText(R.id.widget_title,"JOURNEY")
            remote.setImageViewBitmap(R.id.widget_car,JourneyCarBitmap.render(ctx,status,if(large)480 else 360))
            remote.setTextViewText(R.id.widget_status,if(demo)"DEMO" else if(status.online)"● LIVE" else "OFFLINE")
            val rpm=if(status.online&&status.rpmValid) status.rpm.toString() else "—"
            val coolant=if(status.online&&status.coolantValid)"${status.coolant}°C" else "—"
            remote.setTextViewText(R.id.widget_reading,
                "RPM $rpm   •   حرارة $coolant")
            if(large) {
                val openCount=listOf(2,4,8,16,32,64).count{status.doorOpen(it)}
                val lock=if(status.online)if(status.locked)"مقفلة" else "مفتوحة" else "—"
                val motor=if(status.online&&status.rpmValid)if(status.engineRunning)"شغال" else "مطفأ" else "—"
                val beam=if(status.online&&status.lightsValid && status.headlightsOn)"💡" else ""
                val turn=if(status.online&&status.turnsValid && (status.leftSignal||status.rightSignal))"↔" else ""
                val doorCount=if(status.doorsValid && status.doorKnownMask!=0)openCount.toString()else "—"
                val signals=if(status.online&&status.turnsValid) {
                    "${if(status.leftSignal)"◀"else "—"} / ${if(status.rightSignal)"▶"else "—"}"
                }else "—"
                val battery=if(status.online&&status.battery>0)"%.1fV".format(java.util.Locale.US,status.battery) else "—"
                remote.setTextViewText(R.id.widget_details,
                    "قفل: $lock • محرك: $motor • أبواب: $doorCount\nفولت: $battery • إشارة: $signals • أيت: ${if(beam.isNotBlank())"ON" else "—"}")
            }
            remote.setOnClickPendingIntent(R.id.widget_car,open(ctx,id,"open"))
            remote.setOnClickPendingIntent(R.id.widget_title,open(ctx,id,"open"))
            remote.setOnClickPendingIntent(R.id.widget_start,open(ctx,id,"start"))
            if(demo){
                remote.setOnClickPendingIntent(R.id.widget_lock,broadcast(ctx,id,ACTION_DEMO_LOCK))
                remote.setOnClickPendingIntent(R.id.widget_unlock,broadcast(ctx,id,ACTION_DEMO_UNLOCK))
            }else{
                remote.setOnClickPendingIntent(R.id.widget_lock,open(ctx,id,"lock"))
                remote.setOnClickPendingIntent(R.id.widget_unlock,open(ctx,id,"unlock"))
            }
            manager.updateAppWidget(id,remote)
        }

        private fun open(ctx:Context,id:Int,action:String):PendingIntent {
            val intent=Intent(ctx,MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_ACTION,action)
            return PendingIntent.getActivity(ctx,id*17+action.hashCode(),intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        private fun broadcast(ctx:Context,id:Int,action:String):PendingIntent {
            val intent=Intent(ctx,JourneyHomeWidget::class.java).setAction(action)
            return PendingIntent.getBroadcast(ctx,id*17+action.hashCode(),intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
class JourneyLargeWidget:JourneyHomeWidget()
