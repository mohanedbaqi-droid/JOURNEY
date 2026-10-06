package com.journey.control

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.LayoutDirection
import kotlinx.coroutines.delay

@Composable fun JourneyCarVisual(s:VehicleState,angled:Boolean){
 var tick by remember{mutableLongStateOf(0)}
 LaunchedEffect(s.leftTurn,s.rightTurn){while(s.leftTurn||s.rightTurn){tick=android.os.SystemClock.elapsedRealtime();delay(50)}}
 CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr){
  if(angled)AngledCar(s,tick) else Box(Modifier.fillMaxWidth().aspectRatio(1920f/1200f)){
   @Composable fun layer(id:Int,show:Boolean=true){if(show)Image(painterResource(id),null,Modifier.fillMaxSize(),contentScale=ContentScale.Fit)}
   layer(R.drawable.journey_layer_liftgate,s.doorOpen(0x40))
   layer(R.drawable.journey_layer_passenger_rear_door,s.doorOpen(0x10))
   layer(R.drawable.journey_layer_body)
   layer(R.drawable.journey_layer_driver_mirror,!s.doorOpen(0x02))
   layer(R.drawable.journey_layer_passenger_mirror,!s.doorOpen(0x04))
   layer(R.drawable.journey_layer_driver_door,s.doorOpen(0x02))
   layer(R.drawable.journey_layer_passenger_door,s.doorOpen(0x04))
   layer(R.drawable.journey_layer_red_d_r_l,s.drl&&!s.lowBeam)
   layer(R.drawable.journey_layer_low_beam,s.lowBeam)
   layer(R.drawable.journey_layer_projectors,s.projectors)
   layer(R.drawable.journey_layer_driver_d_r_l,s.drl&&!s.leftTurn)
   layer(R.drawable.journey_layer_passenger_d_r_l,s.drl&&!s.rightTurn)
   if(s.leftTurn||s.rightTurn)Canvas(Modifier.fillMaxSize()){
    val phase=(tick%1150)/1000f
    val count=if(phase<0.72f)(phase/0.72f*18).toInt()+1 else if(phase<0.9f)18 else 0
    for((enabled,points) in listOf(s.rightTurn to passengerLEDs,s.leftTurn to driverLEDs)){
     if(enabled)points.take(count).forEach{p->
      val x=(p.x*1335f/800f*0.932f+347)*size.width/1920f
      val y=(p.y*1178f/706f*0.894f+114)*size.height/1200f
      drawCircle(Color(0xFFFFAD12),8.7f*size.width/1920f,Offset(x,y))
     }
    }
   }
  }
 }
}
private val passengerLEDs=listOf(178 to 470,166 to 467,154 to 465,142 to 462,130 to 459,118 to 457,105 to 449,94 to 446,82 to 443,70 to 440,59 to 437,48 to 430,46 to 422,46 to 413,46 to 404,47 to 395,48 to 386,49 to 376).map{Offset(it.first.toFloat(),it.second.toFloat())}
private val driverLEDs=listOf(613 to 470,625 to 468,638 to 465,650 to 462,662 to 460,674 to 457,686 to 450,698 to 447,710 to 444,722 to 441,733 to 437,742 to 430,743 to 422,743 to 413,743 to 404,742 to 395,741 to 386,740 to 376).map{Offset(it.first.toFloat(),it.second.toFloat())}

@Composable private fun AngledCar(s:VehicleState,tick:Long)=Box(Modifier.fillMaxWidth().aspectRatio(1.5f)){
 Image(painterResource(R.drawable.journey_angled_closed),null,Modifier.fillMaxSize(),contentScale=ContentScale.Fit)
 if(s.doorOpen(2))Image(painterResource(R.drawable.journey_angled_open),null,Modifier.fillMaxSize().graphicsLayer{translationX=size.width*20f/1536f;translationY=size.height*18f/1024f}.clip(GenericShape{size,_->
  val points=listOf(1155 to 127,1217 to 128,1266 to 160,1300 to 117,1418 to 104,1455 to 205,1475 to 340,1484 to 650,1200 to 729,1172 to 393)
  points.forEachIndexed{i,p->val x=p.first/1536f*size.width;val y=p.second/1024f*size.height;if(i==0)moveTo(x,y)else lineTo(x,y)};close()
 }),contentScale=ContentScale.Fit)
 Canvas(Modifier.fillMaxSize()){
  if(s.lowBeam||s.projectors)for(lens in listOf(Triple(213f,510f,50f),Triple(280f,518f,42f),Triple(848f,531f,68f),Triple(958f,533f,62f)))drawCircle(Color.White.copy(alpha=0.85f),lens.third/2f/1536f*size.width,Offset(lens.first/1536f*size.width,lens.second/1024f*size.height))
  if(tick%1000<700)for((on,center) in listOf(s.rightTurn to Offset(215f,576f),s.leftTurn to Offset(922f,594f))){if(on)for(i in 0..11)drawCircle(Color(0xFFFFAD12),size.width*3/1536f,Offset((center.x+(i-5.5f)*(if(center.x<500)10 else 18))/1536f*size.width,center.y/1024f*size.height))}
 }
}
