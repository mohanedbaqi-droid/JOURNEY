/* Punisher Drive local vehicle simulator (v1).
 * ALL data is synthetic. No network, Bluetooth, OBD, GPIO or physical vehicle access.
 * Keep it separate from any future authenticated hardware transport.
 */
(function(root,factory){
  var api=factory();
  if(typeof module==='object' && module.exports)module.exports=api;
  root.PunisherSimulator=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  var sessions=Object.create(null);
  var allowed={lock:1,unlock:1,start:1,alarm:1,stop:1};
  function clone(x){return JSON.parse(JSON.stringify(x))}
  function state(id){
    if(typeof id!=='string'||!id||id.length>128)throw new Error('invalid vehicle id');
    if(!sessions[id])sessions[id]={
      protocol:'punisher.vehicle.v1',mode:'simulation',vehicleId:id,
      connected:true,locked:true,engineRunning:false,alarmActive:false,
      parked:true,doorsClosed:true,speedKmh:0,rpm:0,
      batteryV:12.58,coolantC:28,espC:32,latitude:30.508,longitude:47.814,
      gpsValid:true,dtcs:[],seq:0,updatedAt:new Date().toISOString()
    };
    return sessions[id]
  }
  function get(id){return clone(state(id))}
  function reset(id){delete sessions[id];return get(id)}
  function setSensors(id,values){
    var s=state(id),input=values||{};
    var permitted=['parked','doorsClosed','connected','speedKmh','batteryV','coolantC','espC','gpsValid'];
    Object.keys(input).forEach(function(k){
      if(permitted.indexOf(k)<0)throw new Error('unsupported simulated sensor: '+k);
      var v=input[k];
      if(['speedKmh','batteryV','coolantC','espC'].indexOf(k)>=0){
        if(typeof v!=='number'||!Number.isFinite(v)||v<0||v>500)throw new Error('bad sensor value');
      }else if(typeof v!=='boolean')throw new Error('bad sensor value');
      s[k]=v
    });
    s.parked=s.parked&&s.speedKmh===0;
    s.updatedAt=new Date().toISOString();return get(id)
  }
  function execute(id,cmd){
    if(!allowed[cmd])return {ok:false,reason:'unsupported-command',state:get(id)};
    var s=state(id),reason='';
    if(!s.connected)reason='demo-disconnected';
    else if(cmd==='start'&&(!s.parked||s.speedKmh>0||!s.doorsClosed))reason='safety-guard';
    else if(cmd==='lock'&&!s.doorsClosed)reason='door-open';
    else if(cmd==='stop'&&s.speedKmh>0)reason='vehicle-moving';
    if(reason)return {ok:false,reason:reason,state:get(id)};
    if(cmd==='lock')s.locked=true;
    if(cmd==='unlock')s.locked=false;
    if(cmd==='start'){s.engineRunning=true;s.rpm=780;s.batteryV=14.2;s.coolantC=45;}
    if(cmd==='stop'){s.engineRunning=false;s.rpm=0;s.batteryV=12.55;}
    if(cmd==='alarm')s.alarmActive=!s.alarmActive;
    s.seq++;s.updatedAt=new Date().toISOString();
    return {ok:true,mode:'simulation',command:cmd,state:get(id)}
  }
  return Object.freeze({version:1,get:get,reset:reset,execute:execute,setSensors:setSensors});
});
