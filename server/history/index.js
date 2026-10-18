'use strict';
const express = require('express');
const mqtt = require('mqtt');
const { Pool } = require('pg');
const app = express();
app.disable('x-powered-by');
const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.PGSSL === 'disable' ? false : { rejectUnauthorized: true } });
const DEVICE = process.env.JOURNEY_DEVICE_ID;
const API_TOKEN = process.env.JOURNEY_API_TOKEN;
if (!DEVICE || !API_TOKEN || !process.env.MQTT_URL || !process.env.DATABASE_URL) throw Error('Missing required environment configuration');
app.use(express.json({limit:'16kb'}));
const now = () => new Date();
function num(v,min,max) { const n=Number(v); return Number.isFinite(n)&&n>=min&&n<=max?n:null; }
function pick(o,...names){ for(const k of names)if(o[k]!==undefined&&o[k]!==null)return o[k];return null; }
function geoDistance(a,b) { const r=Math.PI/180, dlat=(b.lat-a.lat)*r, dlon=(b.lon-a.lon)*r; const h=Math.sin(dlat/2)**2+Math.cos(a.lat*r)*Math.cos(b.lat*r)*Math.sin(dlon/2)**2; return 12742000*Math.asin(Math.min(1,Math.sqrt(h))); }
const sessions=new Map();
async function ingest(payload,topic) {
 const o=JSON.parse(payload.toString('utf8'));if(!o||typeof o!=='object'||Array.isArray(o))return;
 const lat=num(pick(o,'lat','latitude','gps_lat'),-90,90),lon=num(pick(o,'lon','lng','longitude','gps_lon'),-180,180);
 if(lat===null||lon===null||lat===0&&lon===0)return;
 const gpsValid=pick(o,'gps_valid','gpsValid');if(gpsValid===false||gpsValid===0)return;
 const accuracy=num(pick(o,'accuracy','gps_accuracy','hdop_m'),0,10000);
 if(accuracy!==null&&accuracy>100)return;
 const speed=num(pick(o,'speed_kph','speedKph','gps_speed_kph'),0,350);
 const heading=num(pick(o,'heading','course'),0,360);
 const rpm=num(pick(o,'rpm','engine_rpm'),0,10000);
 const engine=typeof o.engine_running==='boolean'?o.engine_running:(rpm!==null?rpm>350:null);
 const time=now(); const key=DEVICE;const last=sessions.get(key);
 const point={lat,lon,time,speed,heading,rpm,engine};
 if(last){const elapsed=(time-last.time)/1000;if(elapsed<2)return;const dist=geoDistance(last,point);if(elapsed>0&&dist/elapsed>85)return;}
 const moving=(speed!==null&&speed>=5)||(last&&geoDistance(last,point)>=30&&(time-last.time)<120000);
 const client=await pool.connect();
 try {
  await client.query('BEGIN');
  const inserted=await client.query('INSERT INTO journey_points(device_id,recorded_at,lat,lon,speed_kph,heading,engine_running,accuracy_m) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id',[key,time,lat,lon,speed,heading,engine,accuracy]);
  let trip=await client.query('SELECT id FROM journey_trips WHERE device_id=$1 AND ended_at IS NULL ORDER BY started_at DESC LIMIT 1 FOR UPDATE',[key]);
  if(moving&&trip.rowCount===0){
   trip=await client.query('INSERT INTO journey_trips(device_id,started_at,start_lat,start_lon) VALUES($1,$2,$3,$4) RETURNING id',[key,time,lat,lon]);
  }
  if(trip.rowCount){
   const id=trip.rows[0].id;
   await client.query('UPDATE journey_points SET trip_id=$1 WHERE id=$2',[id,inserted.rows[0].id]);
   if(last&&last.tripId===id&&moving){
    const dist=geoDistance(last,point);
    if(dist<1000)await client.query('UPDATE journey_trips SET distance_m=distance_m+$1,max_speed_kph=GREATEST(max_speed_kph,$2) WHERE id=$3',[dist,speed||0,id]);
   }
   if(!moving&&last&&!last.moving&&(time-last.time)>=120000){
    await client.query('UPDATE journey_trips SET ended_at=$1,end_lat=$2,end_lon=$3 WHERE id=$4 AND ended_at IS NULL',[time,lat,lon,id]);
    await client.query('INSERT INTO journey_stops(device_id,trip_id,arrived_at,lat,lon) VALUES($1,$2,$3,$4,$5)',[key,id,last.time,lat,lon]);
    trip={rows:[]};
   }
  }
  if(moving)await client.query('UPDATE journey_stops SET departed_at=$1 WHERE device_id=$2 AND departed_at IS NULL',[time,key]);
  await client.query('COMMIT');
  sessions.set(key,{...point,moving,tripId:trip.rows[0]?.id||null});
 }catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}
}
app.use('/api', (req,res,next)=>{const header=req.get('authorization')||'';if(header!==`Bearer ${API_TOKEN}`)return res.status(401).json({error:'unauthorized'});next();});
app.get('/health',(_req,res)=>res.json({ok:true}));
app.get('/api/trips',async(req,res,next)=>{try{const limit=Math.min(100,Math.max(1,parseInt(req.query.limit)||30));const q=await pool.query('SELECT * FROM journey_trips WHERE device_id=$1 ORDER BY started_at DESC LIMIT $2',[DEVICE,limit]);res.json(q.rows);}catch(e){next(e);}});
app.get('/api/stops',async(req,res,next)=>{try{const q=await pool.query('SELECT * FROM journey_stops WHERE device_id=$1 ORDER BY arrived_at DESC LIMIT 100',[DEVICE]);res.json(q.rows);}catch(e){next(e);}});
app.get('/api/trips/:id/points',async(req,res,next)=>{try{if(!/^[0-9]+$/.test(req.params.id))return res.sendStatus(400);const q=await pool.query('SELECT recorded_at,lat,lon,speed_kph,heading FROM journey_points WHERE device_id=$1 AND trip_id=$2 ORDER BY recorded_at LIMIT 10000',[DEVICE,req.params.id]);res.json(q.rows);}catch(e){next(e);}});
app.get('/api/stats',async(req,res,next)=>{try{const q=await pool.query('SELECT COUNT(*)::int AS trip_count,COALESCE(SUM(distance_m),0)::float8 AS distance_m,COALESCE(MAX(max_speed_kph),0)::float8 AS max_speed_kph FROM journey_trips WHERE device_id=$1',[DEVICE]);res.json(q.rows[0]);}catch(e){next(e);}});
app.use((err,req,res,next)=>{console.error('API error',err.message);res.status(500).json({error:'server_error'});});
const client=mqtt.connect(process.env.MQTT_URL,{username:process.env.MQTT_USERNAME,password:process.env.MQTT_PASSWORD,protocolVersion:4,reconnectPeriod:5000,clientId:'journey-history-'+require('crypto').randomBytes(6).toString('hex')});
client.on('connect',()=>client.subscribe(`journey/${DEVICE}/telemetry/state`,{qos:1},e=>e&&console.error('subscribe',e.message)));
client.on('message',(topic,data)=>{if(data.length>32768)return;ingest(data,topic).catch(e=>console.error('ingest',e.message));});
client.on('error',e=>console.error('mqtt',e.message));
app.listen(Number(process.env.PORT)||8080,()=>console.log('JOURNEY history API listening'));
