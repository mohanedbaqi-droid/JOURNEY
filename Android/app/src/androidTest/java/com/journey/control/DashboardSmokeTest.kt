package com.journey.control

import android.graphics.Bitmap
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
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
   assertTrue(device.hasObject(By.text("2.4.33 (65)")))
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
