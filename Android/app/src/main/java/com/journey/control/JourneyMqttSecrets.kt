package com.journey.control

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Broker password is never stored in ordinary plaintext preferences.
 * API 21/22 can connect for the current session, but cannot persist it
 * because hardware backed AES/GCM Keystore is only required from API 23.
 */
object JourneyMqttSecrets {
 private const val ALIAS="com.journey.control.mqtt.credentials.v1"
 private const val KEY="mqtt.password.encrypted"

 fun save(context:Context,password:String):Boolean {
  if(Build.VERSION.SDK_INT<23)return false
  if(password.isEmpty()){
   context.getSharedPreferences("journey",Context.MODE_PRIVATE).edit().remove(KEY).apply()
   return true
  }
  return runCatching{
   val cipher=Cipher.getInstance("AES/GCM/NoPadding")
   cipher.init(Cipher.ENCRYPT_MODE,getOrCreateKey())
   val data=cipher.iv+cipher.doFinal(password.toByteArray(Charsets.UTF_8))
   context.getSharedPreferences("journey",Context.MODE_PRIVATE).edit()
    .putString(KEY,Base64.encodeToString(data,Base64.NO_WRAP)).apply()
   true
  }.getOrDefault(false)
 }

 fun read(context:Context):String {
  if(Build.VERSION.SDK_INT<23)return ""
  val encoded=context.getSharedPreferences("journey",Context.MODE_PRIVATE)
   .getString(KEY,null)?:return ""
  return runCatching{
   val data=Base64.decode(encoded,Base64.NO_WRAP)
   if(data.size<29)return@runCatching ""
   val cipher=Cipher.getInstance("AES/GCM/NoPadding")
   cipher.init(Cipher.DECRYPT_MODE,getOrCreateKey(),GCMParameterSpec(128,data.copyOfRange(0,12)))
   String(cipher.doFinal(data.copyOfRange(12,data.size)),Charsets.UTF_8)
  }.getOrDefault("")
 }

 private fun getOrCreateKey():SecretKey {
  val store=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}
  (store.getKey(ALIAS,null) as? SecretKey)?.let{return it}
  val generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore")
  val spec=KeyGenParameterSpec.Builder(ALIAS,
   KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
   .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
   .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
   .setKeySize(256)
   .build()
  generator.init(spec)
  return generator.generateKey()
 }
}
