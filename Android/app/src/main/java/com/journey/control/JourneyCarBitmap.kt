package com.journey.control

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF

/**
 * Widget-sized rendering of the EXACT same transparent artwork and layer order
 * as ios/JourneyControl/Views/CarVisualView.swift.
 *
 * RemoteViews cannot host a Compose Canvas; render to one bounded bitmap to
 * retain doors, low beam, projector lamps and individual turn signals.
 * 480x300 consumes <= 576 kB raw, keeping binder transactions small.
 */
object JourneyCarBitmap {
 private const val SOURCE_W=1920f
 private const val SOURCE_H=1200f
 private val paint=Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

 fun render(context:Context,state:VehicleState,width:Int=480):Bitmap {
  val w=width.coerceIn(240,480)
  val h=(w*SOURCE_H/SOURCE_W).toInt()
  val bitmap=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888)
  val canvas=Canvas(bitmap)
  canvas.save()
  canvas.scale(w/SOURCE_W,h/SOURCE_H)

  fun layer(res:Int,visible:Boolean=true) {
   if(!visible)return
   val image=BitmapFactory.decodeResource(context.resources,res)?:return
   try {
    canvas.drawBitmap(image,null,Rect(0,0,1920,1200),paint)
   }finally {image.recycle()}
  }

  // The reference iPhone ZStack order is important: the doors never slide
  // the grille, license plate, white roof or surrounding body.
  layer(R.drawable.journey_layer_liftgate,state.doorOpen(0x40))
  layer(R.drawable.journey_layer_driver_rear_door,state.doorOpen(0x08))
  layer(R.drawable.journey_layer_passenger_rear_door,state.doorOpen(0x10))
  layer(R.drawable.journey_layer_body)
  layer(R.drawable.journey_layer_driver_mirror,!state.doorOpen(0x02))
  layer(R.drawable.journey_layer_passenger_mirror,!state.doorOpen(0x04))
  layer(R.drawable.journey_layer_driver_door,state.doorOpen(0x02))
  layer(R.drawable.journey_layer_passenger_door,state.doorOpen(0x04))
  layer(R.drawable.journey_layer_red_d_r_l,state.drl&&!state.lowBeam)
  layer(R.drawable.journey_layer_low_beam,state.lowBeam)
  layer(R.drawable.journey_layer_projectors,state.projectors)
  layer(R.drawable.journey_layer_passenger_d_r_l,state.drl&&!state.rightTurn)
  layer(R.drawable.journey_layer_driver_d_r_l,state.drl&&!state.leftTurn)

  // A home-screen widget is a static frame: show active amber LEDs without
  // inventing an independent animation.
  if(state.rightTurn || state.leftTurn) {
   val amber=Paint(Paint.ANTI_ALIAS_FLAG).apply {color=Color.rgb(255,173,18)}
   val passenger=listOf(178 to 470,166 to 467,154 to 465,142 to 462,130 to 459,
    118 to 457,105 to 449,94 to 446,82 to 443,70 to 440,59 to 437,48 to 430,
    46 to 422,46 to 413,46 to 404,47 to 395,48 to 386,49 to 376)
   val driver=listOf(613 to 470,625 to 468,638 to 465,650 to 462,662 to 460,
    674 to 457,686 to 450,698 to 447,710 to 444,722 to 441,733 to 437,
    742 to 430,743 to 422,743 to 413,743 to 404,742 to 395,741 to 386,740 to 376)
   for((on,points) in listOf(state.rightTurn to passenger,state.leftTurn to driver)){
    if(!on)continue
    for((x,y) in points){
     canvas.drawCircle(x*1335f/800f*0.932f+347f,
      y*1178f/706f*0.894f+114f,8.7f,amber)
    }
   }
  }

  // A real hood opening is indicated textually in the widget, since the
  // original car artwork does not include an approved hood-open photo.
  canvas.restore()
  return bitmap
 }
}
