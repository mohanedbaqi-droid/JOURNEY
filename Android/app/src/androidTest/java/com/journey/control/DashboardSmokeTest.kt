package com.journey.control

import android.graphics.Bitmap
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DashboardSmokeTest {
 @Test fun dashboardAndPagesRenderWithoutCrash(){
  val instrumentation=InstrumentationRegistry.getInstrumentation()
  val device=UiDevice.getInstance(instrumentation)
  ActivityScenario.launch(MainActivity::class.java).use {
   assertTrue(device.wait(Until.hasObject(By.text("قفل")),10000))
   device.waitForIdle()
   capture("01-home")
   val about=device.findObjects(By.text("معلومات")).last()
   about.click()
   assertTrue(device.wait(Until.hasObject(By.text("إصدار التطبيق")),5000))
   assertTrue(device.hasObject(By.text("2.4.34 (66)")))
   assertTrue(device.hasObject(By.text("غير متصل")))
   capture("02-about")
   device.findObjects(By.text("OBD")).last().click()
   assertTrue(device.wait(Until.hasObject(By.text("بيانات السيارة")),5000))
   capture("03-obd")
   device.findObjects(By.text("الخريطة")).last().click()
   assertTrue(device.wait(Until.hasObject(By.text("بانتظار موقع السيارة")),5000))
   capture("04-map")
   device.findObjects(By.desc("الإعدادات")).first().click()
   assertTrue(device.wait(Until.hasObject(By.text("واجهة التطبيق")),5000))
   capture("05-settings")
   device.findObjects(By.text("ESP")).first().click()
   assertTrue(device.wait(Until.hasObject(By.text("صحة ESP")),5000))
   assertTrue(device.hasObject(By.text("بانتظار قراءة حرارة فعلية")))
   assertTrue(device.hasObject(By.text("بداية تنبيه الحرارة")))
   assertTrue(device.hasObject(By.text("50 °C")))
   UiScrollable(UiSelector().scrollable(true)).scrollIntoView(UiSelector().text("حفظ حد التنبيه على ESP"))
   val save=device.findObject(By.text("حفظ حد التنبيه على ESP"))
   assertNotNull(save)
   save.click() // A disabled button must not send or show a save result offline.
   device.waitForIdle()
   assertFalse(device.hasObject(By.text("تم الإرسال؛ بانتظار تأكيد ESP")))
   assertFalse(device.hasObject(By.text("لم يصل تأكيد؛ تحقق من الاتصال وأعد المحاولة")))
   assertFalse(device.hasObject(By.text("أكد ESP حفظ حد التنبيه")))
   capture("06-esp-health")
  }
 }
 private fun capture(name:String){
  val i=InstrumentationRegistry.getInstrumentation()
  i.waitForIdleSync()
  UiDevice.getInstance(i).waitForIdle()
  Thread.sleep(400)
  val image=i.uiAutomation.takeScreenshot()
  assertNotNull(image)
  val dir=File(i.targetContext.getExternalFilesDir(null),"ui-review").also{it.mkdirs()}
  File(dir,"$name.png").outputStream().use{image.compress(Bitmap.CompressFormat.PNG,100,it)}
  image.recycle()
 }
}
