/*
  JOURNEY_BCM_SCANNER - Dodge Journey 2017 / KONNWEI BLE
  READ-ONLY LAB TOOL. Does not send BCM actuator/configuration commands.
  Target: KONNWEI / 22:C0:20:12:8A:EE
  Serial: 115200
  Commands: INFO, MON, STOP, ATDP, ATDPN, ATH1
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

BLEClient* client=nullptr;
BLERemoteCharacteristic* tx=nullptr;
BLERemoteCharacteristic* rx=nullptr;

String buf;
bool monitor=false, connected=false;
bool burstStopping=false;
uint32_t monitorStarted=0, stopRequestedAt=0, nextMonitorAt=0;

// KONNWEI/ELM buffer is small on a busy Journey CAN-C bus.
// Capture a very short slice, stop, fully drain to '>', then wait before next slice.
static const uint32_t MON_BURST_MS=0;
static const uint32_t MON_GAP_MS=0;
static const uint32_t STOP_DRAIN_TIMEOUT_MS=350;

void notifyCB(BLERemoteCharacteristic*,uint8_t* d,size_t n,bool){
  if(monitor || burstStopping){
    Serial.print("[CAN] ");
    for(size_t i=0;i<n;i++) Serial.write(d[i]);
    if(!n || d[n-1]!='\n') Serial.println();

    // '>' means ELM finished the stopped ATMA stream and its output has drained.
    for(size_t i=0;i<n;i++){
      if(d[i]=='>'){
        monitor=false;
        burstStopping=false;
        nextMonitorAt=millis()+MON_GAP_MS;
        break;
      }
    }
    return;
  }
  for(size_t i=0;i<n;i++){char c=(char)d[i];buf+=c;Serial.write(c);}
}

bool chars(){
  struct P{const char*s,*a,*b;};
  P p[]={{FFF0,FFF1,FFF2},{NUS,NUSRX,NUSTX}};
  for(auto &q:p){
    auto*s=client->getService(BLEUUID(q.s)); if(!s)continue;
    auto*a=s->getCharacteristic(BLEUUID(q.a));
    auto*b=s->getCharacteristic(BLEUUID(q.b));
    if(!a||!b)continue;
    BLERemoteCharacteristic* z[]={a,b};
    for(auto*c:z){
      if(c->canWrite()||c->canWriteNoResponse())tx=c;
      if(c->canNotify()||c->canIndicate())rx=c;
    }
    if(tx&&rx){rx->registerForNotify(notifyCB);return true;}
    tx=rx=nullptr;
  }
  return false;
}

bool link(const char* mac){
  if(!client)client=BLEDevice::createClient();
  BLEAddress a(mac);
  Serial.printf("\n[BLE] direct MAC %s PUBLIC\n",mac);
  if(!client->connect(a,BLE_ADDR_PUBLIC)){
    Serial.println("[BLE] retry RANDOM");
    if(!client->connect(a,BLE_ADDR_RANDOM))return false;
  }
  if(!chars()){client->disconnect();return false;}
  connected=true;
  return true;
}

bool fallback(){
  Serial.println("[BLE] MAC failed -> 8s fallback scan for name KONNWEI");
  BLEScan*s=BLEDevice::getScan();
  s->setActiveScan(true);
  BLEScanResults* r=s->start(8,false);
  if(!r){Serial.println("[BLE] scan failed");return false;}
  for(int i=0;i<r->getCount();i++){
    auto d=r->getDevice(i);
    String n=d.haveName()?d.getName().c_str():"";
    if(n.equalsIgnoreCase(OBD_NAME)){
      String a=d.getAddress().toString().c_str();a.toUpperCase();
      Serial.printf("[BLE] found %s [%s]\n",n.c_str(),a.c_str());
      s->clearResults();
      return link(a.c_str());
    }
  }
  s->clearResults();
  return false;
}

void sendElm(String c){
  if(!connected||!tx){Serial.println("[ERR] OBD not connected");return;}
  c.trim();c.toUpperCase();
  if(c=="04"||c.startsWith("ATZ")||(c.startsWith("ATD")&&c!="ATDP"&&c!="ATDPN")){
    Serial.println("[SAFE] blocked");return;
  }
  buf="";
  String w=c+"\r";
  Serial.printf("\n[TX] %s\n",c.c_str());
  tx->writeValue((uint8_t*)w.c_str(),w.length(),tx->canWrite());
}

void waitPrompt(uint32_t ms=2200){
  uint32_t t=millis();
  while(millis()-t<ms){delay(10);if(buf.indexOf('>')>=0)return;}
}

void initElm(){
  const char* a[]={"ATE0","ATL0","ATS1","ATH1","ATCAF0","ATSP6","ATDP","ATDPN"};
  for(auto c:a){sendElm(c);waitPrompt();delay(100);}
  Serial.println("\n[READY] Protocol 6 / CAN 11-500. Type MON for IDs 100-13F. Then STOP, BANK5 for 140-17F.");
}

void beginBurst(){
  if(!connected||!tx||monitor||burstStopping)return;
  String x="ATMA\r";
  monitor=true;
  monitorStarted=millis();
  tx->writeValue((uint8_t*)x.c_str(),x.length(),tx->canWrite());
}

void requestBurstStop(){
  if(!monitor||!tx||burstStopping)return;
  String x="\r";
  tx->writeValue((uint8_t*)x.c_str(),x.length(),tx->canWrite());
  burstStopping=true;
  stopRequestedAt=millis();
}

void forceDrainRecovery(){
  // Some clone ELMs do not return '>' reliably after ATMA stop.
  // Never restart immediately: give the adapter a clean recovery gap.
  monitor=false;
  burstStopping=false;
  nextMonitorAt=millis()+MON_GAP_MS+200;
  Serial.println("[MON] drain timeout -> recovery gap");
}

void startFilteredMonitor(String cf="100", String cm="700"){
  if(monitor||burstStopping){Serial.println("[MON] already running");return;}
  sendElm("ATSP6");waitPrompt();
  sendElm("ATH1");waitPrompt();
  sendElm("ATS1");waitPrompt();
  sendElm("ATCAF0");waitPrompt();
  sendElm("ATCF"+cf);waitPrompt();
  sendElm("ATCM"+cm);waitPrompt();
  nextMonitorAt=0; burstStopping=false;
  Serial.printf("\n[FILTER] CF=%s CM=%s\n",cf.c_str(),cm.c_str());
  Serial.println("[MON] FILTERED passive monitor. Type STOP first before changing bank.");
  buf=""; monitor=true; monitorStarted=millis();
  String x="ATMA\r";
  tx->writeValue((uint8_t*)x.c_str(),x.length(),tx->canWrite());
}
void startMonitor(){ startBank(16); }
void startBank(int n){
  // 16-ID windows: mask 0x7F0. BANK16=100-10F, BANK17=110-11F, etc.
  if(n<0||n>127){Serial.println("[ERR] BANK must be 0..127");return;}
  unsigned int base=(unsigned int)n*0x10;
  char cf[4]; snprintf(cf,sizeof(cf),"%03X",base);
  char label[48]; snprintf(label,sizeof(label),"IDs %03X-%03X",base,base+0x0F);
  Serial.printf("[BANK %d] %s\n",n,label);
  startFilteredMonitor(String(cf),"7F0");
}
void startExact(String s){
  s.trim(); s.toUpperCase();
  if(s.startsWith("ID")) s=s.substring(2);
  long id=strtol(s.c_str(),nullptr,16);
  if(id<0||id>0x7FF){Serial.println("[ERR] use ID000..ID7FF");return;}
  char cf[4]; snprintf(cf,sizeof(cf),"%03lX",id);
  startFilteredMonitor(String(cf),"7FF");
}
void stopMonitor(){
  nextMonitorAt=0;
  if(monitor&&!burstStopping) requestBurstStop();
  uint32_t t=millis();
  while((monitor||burstStopping) && millis()-t<600){
    delay(5);
    if(burstStopping && millis()-stopRequestedAt>STOP_DRAIN_TIMEOUT_MS) forceDrainRecovery();
  }
  monitor=false;
  burstStopping=false;
  nextMonitorAt=0;
  Serial.println("\n[MON] stopped");
}

void setup(){
  Serial.begin(115200);
  delay(800);
  Serial.println("\n=== JOURNEY 2017 BCM READ-ONLY SCANNER v5 FILTERED-64 ===");
  BLEDevice::init("JOURNEY-BCM-SCANNER");
  if(!link(OBD_MAC)&&!fallback()){
    Serial.println("[FAIL] KONNWEI not found/unsupported GATT");
    return;
  }
  Serial.println("[OK] KONNWEI BLE connected");
  initElm();
}

void loop(){
  if(Serial.available()){
    String s=Serial.readStringUntil('\n');s.trim();if(!s.length())return;
    String u=s;u.toUpperCase();
    if(u=="STOP") stopMonitor();
    else if(monitor||burstStopping) Serial.println("[MON] type STOP first");
    else if(u=="MON") startBank(4); // 100-13F
    else if(u.startsWith("BANK")){
      int n=u.substring(4).toInt();
      startBank(n);
    }
    else if(u.startsWith("ID")) startExact(u);
    else if(u=="INFO") initElm();
    else Serial.println("[CMD] MON, BANK0..BANK31, IDxxx, STOP, INFO");
  }
  delay(2);
}
