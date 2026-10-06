package com.journey.control

import org.json.JSONObject
import java.util.UUID

object JourneyProtocol {
    const val SERVICE_UUID="AF10A000-17B7-4A86-A7D7-9A3B40C8D001"
    const val COMMAND_UUID="AF10A001-17B7-4A86-A7D7-9A3B40C8D001"
    const val STATE_UUID="AF10A002-17B7-4A86-A7D7-9A3B40C8D001"
    fun command(phoneId:String, action:String, extras:JSONObject=JSONObject())=JSONObject().apply{
        put("schema",1); put("id",UUID.randomUUID().toString()); put("phoneID",phoneId); put("action",action)
        extras.keys().forEach { put(it,extras.get(it)) }
    }.toString()
}
