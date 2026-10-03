package com.journey.control

import org.json.JSONObject
import java.util.UUID

object JourneyProtocol {
    const val SERVICE_UUID="7e57a001-6e7a-4f55-a9d8-5f6d6f4a1001"
    const val COMMAND_UUID="7e57a002-6e7a-4f55-a9d8-5f6d6f4a1001"
    const val STATE_UUID="7e57a003-6e7a-4f55-a9d8-5f6d6f4a1001"
    fun command(phoneId:String, action:String, extras:JSONObject=JSONObject())=JSONObject().apply{
        put("schema",1); put("id",UUID.randomUUID().toString()); put("phoneID",phoneId); put("action",action)
        extras.keys().forEach { put(it,extras.get(it)) }
    }.toString()
}
