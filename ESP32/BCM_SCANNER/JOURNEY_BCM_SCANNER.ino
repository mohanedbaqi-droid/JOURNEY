/*
  JOURNEY_BCM_SCANNER - Dodge Journey 2017 / KONNWEI BLE
  READ-ONLY LAB TOOL. Does not send BCM actuator/configuration commands.
  Target: KONNWEI / 22:C0:20:12:8A:EE
  Serial: 115200
  Commands: INFO, MON, STOP, 0100, 0902, ATDP, ATDPN, ATH1
*/
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEScan.h>

static const char* OBD_NAME="KONNWEI";
static const char* OBD_MAC ="22:C0:20:12:8A:EE";
static const char* FFF0="0000fff0-0000-1000-8000-00805f9b34fb";
static const char* FFF1="0000fff1-0000-1000-8000-00805f9b34fb";
static const char* FFF2="0000fff2-0000-1000-8000-00805f9b34fb";
static const char* NUS ="6e400001-b5a3-f393-e0a9-e50e24dcca9e";
static const char* NUSRX="6e400002-b5a3-f393-e0a9-e50e24dcca9e";
static const char* NUSTX="6e400003-b5a3-f393-e0a9-e50e24dcca9e";

BLEClient* client=nullptr; BLERemoteCharacteristic* tx=nullptr; BLERemoteCharacteristic* rx=nullptr;
String buf; bool monitor=false, connected=false;
uint32_t monitorStarted=0, nextMonitorAt=0;
static const uint32_t MON_BURST_MS=350;
static const uint32_t MON_GAP_MS=120;

void notifyCB(BLERemoteCharacteristic*,uint8_t* d,size_t n,bool){
  if(monitor){ Serial.print("[CAN] "); for(size_t i=0;i<n;i++)Serial.write(d[i]); if(!n||d[n-1]!='\n')Serial.println(); return; }
  for(size_t i=0;i<n;i++){char c=(char)d[i];buf+=c;Serial.write(c);}
}
bool chars(){
 struct P{const char*s,*a,*b;}; P p[]={{FFF0,FFF1,FFF2},{NUS,NUSRX,NUSTX}};
 for(auto &q:p){auto*s=client->getService(BLEUUID(q.s));if(!s)continue;auto*a=s->getCharacteristic(BLEUUID(q.a));auto*b=s->getCharacteristic(BLEUUID(q.b));if(!a||!b)continue;
  BLERemoteCharacteristic* z[]={a,b};for(auto*c:z){if(c->canWrite()||c->canWriteNoResponse())tx=c;if(c->canNotify()||c->canIndicate())rx=c;}
  if(tx&&rx){rx->registerForNotify(notifyCB);return true;} tx=rx=nullptr;
 }return false;
}
bool link(const char* mac){
 if(!client)client=BLEDevice::createClient();
 BLEAddress a(mac); Serial.printf("\n[BLE] direct MAC %s PUBLIC\n",mac);
 if(!client->connect(a,BLE_ADDR_PUBLIC)){Serial.println("[BLE] retry RANDOM");if(!client->connect(a,BLE_ADDR_RANDOM))return false;}
 if(!chars()){client->disconnect();return false;} connected=true;return true;
}
bool fallback(){
 Serial.println("[BLE] MAC failed -> 8s fallback scan for name KONNWEI");
 BLEScan*s=BLEDevice::getScan();s->setActiveScan(true);BLEScanResults* r=s->start(8,false);
 if(!r){Serial.println("[BLE] scan failed");return false;}
 for(int i=0;i<r->getCount();i++){auto d=r->getDevice(i);String n=d.haveName()?d.getName().c_str():"";if(n.equalsIgnoreCase(OBD_NAME)){String a=d.getAddress().toString().c_str();a.toUpperCase();Serial.printf("[BLE] found %s [%s]\n",n.c_str(),a.c_str());s->clearResults();return link(a.c_str());}}
 s->clearResults();return false;
}
void sendElm(String c){
 if(!connected||!tx){Serial.println("[ERR] OBD not connected");return;} c.trim();c.toUpperCase();
 // Explicit deny-list for destructive/configuration commands in this discovery sketch.
 if(c=="04"||c.startsWith("ATZ")||c.startsWith("ATD")&&c!="ATDP"&&c!="ATDPN"){Serial.println("[SAFE] blocked");return;}
 buf="";String w=c+"\r";Serial.printf("\n[TX] %s\n",c.c_str());tx->writeValue((uint8_t*)w.c_str(),w.length(),tx->canWrite());
}
void waitPrompt(uint32_t ms=2200){uint32_t t=millis();while(millis()-t<ms){delay(10);if(buf.indexOf('>')>=0)return;}}
void initElm(){
 // Journey 2017 high-speed CAN-C on the standard OBD CAN pair: ISO 15765-4, 11-bit, 500 kbps.
 // Force protocol 6 so ELM does not stay in AUTO SEARCHING during the capture.
 const char* a[]={"ATE0","ATL0","ATS1","ATH1","ATCAF0","ATSP6","ATDP","ATDPN"};
 for(auto c:a){sendElm(c);waitPrompt();delay(120);}
 Serial.println("\n[READY] Headers ON. Type MON for passive traffic.");
}
void beginBurst(){
 if(!connected||!tx)return;
 buf=""; String x="ATMA\r"; monitor=true; monitorStarted=millis();
 tx->writeValue((uint8_t*)x.c_str(),x.length(),tx->canWrite());
}
void endBurst(bool finalStop=false){
 if(!monitor||!tx)return;
 String x="\r"; tx->writeValue((uint8_t*)x.c_str(),x.length(),tx->canWrite());
 monitor=false; nextMonitorAt=millis()+MON_GAP_MS;
 if(finalStop) Serial.println("\n[MON] stopped");
}
void startMonitor(){
 sendElm("ATH1");waitPrompt();sendElm("ATS1");waitPrompt();sendElm("ATCAF0");waitPrompt();sendElm("ATSP6");waitPrompt();
 Serial.println("\n[MON] BURST PASSIVE MONITOR. Auto pause/resume prevents BUFFER FULL.");
 beginBurst();
}
void stopMonitor(){endBurst(true); nextMonitorAt=0;}
void setup(){
 Serial.begin(115200);delay(800);Serial.println("\n=== JOURNEY 2017 BCM READ-ONLY SCANNER ===");
 BLEDevice::init("JOURNEY-BCM-SCANNER");
 if(!link(OBD_MAC)&&!fallback()){Serial.println("[FAIL] KONNWEI not found/unsupported GATT");return;}
 Serial.println("[OK] KONNWEI BLE connected");initElm();
}
void loop(){
 if(Serial.available()){
  String cmd=Serial.readStringUntil('\n');cmd.trim();if(!cmd.length())return;
  if(cmd.equalsIgnoreCase("MON"))startMonitor();
  else if(cmd.equalsIgnoreCase("STOP"))stopMonitor();
  else if(cmd.equalsIgnoreCase("INFO"))initElm();
  else if(!monitor && nextMonitorAt==0)sendElm(cmd);
  else Serial.println("[MON] type STOP first");
 }
 if(monitor && millis()-monitorStarted>=MON_BURST_MS) endBurst(false);
 if(!monitor && nextMonitorAt && (int32_t)(millis()-nextMonitorAt)>=0){nextMonitorAt=0;beginBurst();}
 delay(2);
}
