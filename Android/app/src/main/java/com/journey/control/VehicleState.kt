package com.journey.control

data class VehicleState(
    val online:Boolean=false,val locked:Boolean=true,val engineRunning:Boolean=false,val doorsOpen:Boolean=false,
    val remotePowered:Boolean=false,val rpm:Int=0,val speed:Int=0,val coolant:Int=0,val fuel:Int=0,
    val battery:Double=0.0,val obdConnected:Boolean=false,val obdStatus:String="waiting",
    val wifiEnabled:Boolean=false,val wifiConnected:Boolean=false,val wifiSsid:String="",val wifiStatus:String="off",
    val cellularEnabled:Boolean=false,val cellularStatus:String="off",val cellularNetwork:String="",
    val hotspotEnabled:Boolean=false,val hotspotRunning:Boolean=false,val internetRoute:String="NONE",
    val latitude:Double=0.0,val longitude:Double=0.0,val gpsValid:Boolean=false,
    val ownerKnown:Boolean=false,val ownerCount:Int=0,val lastEvent:String="waiting",
    val connectionPriority:String="CELLULAR,WIFI,BLE"
)
