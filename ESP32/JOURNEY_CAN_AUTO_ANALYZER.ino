/*
  JOURNEY CAN AUTO ANALYZER
  ESP32-S3 + KONNWEI BLE ELM327
  ------------------------------------------------------------
  Standalone CAN/BCM discovery tool.
  No iPhone app, no keyless, no remote outputs, no cloud/server.

  "AI" here = local smart scoring/heuristics:
    - compares CLOSED -> OPEN -> CLOSED2
    - scores CAN IDs by repeatable state change
    - identifies changed byte(s) and bit(s)
    - penalizes unstable/counter-like bytes
    - ranks strongest candidates automatically

  Serial Monitor: 115200 baud

  QUICK TEST:
    1) Ignition RUN or engine running
    2) door closed -> send CLOSED
    3) open driver door, wait ~1 sec -> send OPEN
    4) close driver door, wait ~1 sec -> send CLOSED2
    5) send ANALYZE
*/

#include <Arduino.h>
#include <BLEDevice.h>

static const char* KONNWEI_MAC = "22:c0:20:12:8a:ee";
static const char* FFF0 = "0000fff0-0000-1000-8000-00805f9b34fb";
static const char* FFF1 = "0000fff1-0000-1000-8000-00805f9b34fb";
static const char* FFF2 = "0000fff2-0000-1000-8000-00805f9b34fb";

BLEClient* client = nullptr;
BLERemoteCharacteristic* writeChar = nullptr;
BLERemoteCharacteristic* notifyChar = nullptr;
String rx, monitorLine, serialLine;
bool connected=false, monitorActive=false;
uint32_t captureMs=1200;
uint8_t topResults=10;
static const uint8_t MAX_DATA=8, MAX_SAMPLES_PER_ID=24;
static const int MAX_IDS=180;

struct Sample { uint8_t len=0; uint8_t data[MAX_DATA]{}; };
struct IdState { uint16_t id=0; uint32_t frameCount=0; uint8_t sampleCount=0; Sample samples[MAX_SAMPLES_PER_ID]; };
IdState closedSet[MAX_IDS], openSet[MAX_IDS], closed2Set[MAX_IDS];
int closedIds=0, openIds=0, closed2Ids=0;
enum CaptureTarget:uint8_t {TARGET_NONE,TARGET_CLOSED,TARGET_OPEN,TARGET_CLOSED2};
CaptureTarget activeTarget=TARGET_NONE;

class ClientCB: public BLEClientCallbacks {
 void onDisconnect(BLEClient*) override { connected=false; writeChar=nullptr; notifyChar=nullptr; monitorActive=false; Serial.println("\n[BLE] KONNWEI disconnected"); }
};

bool hexNibble(char c,uint8_t&v){if(c>='0'&&c<='9'){v=c-'0';return true;}if(c>='A'&&c<='F'){v=c-'A'+10;return true;}if(c>='a'&&c<='f'){v=c-'a'+10;return true;}return false;}
bool parseByteToken(const String&s,uint8_t&out){if(s.length()!=2)return false;uint8_t h,l;if(!hexNibble(s[0],h)||!hexNibble(s[1],l))return false;out=(h<<4)|l;return true;}
bool parseCanLine(String line,uint16_t&id,Sample&sample){
 line.trim(); if(line.length()<5||line.indexOf("DATA ERROR")>=0||line.indexOf("BUFFER FULL")>=0||line.indexOf("SEARCHING")>=0||line=="STOPPED"||line==">")return false;
 int sp=line.indexOf(' '); if(sp<0)return false; String t=line.substring(0,sp);t.trim();if(t.length()!=3)return false;
 for(size_t i=0;i<t.length();i++){uint8_t d;if(!hexNibble(t[i],d))return false;} id=(uint16_t)strtoul(t.c_str(),nullptr,16);
 String p=line.substring(sp+1);p.trim();sample.len=0;int pos=0;
 while(pos<(int)p.length()&&sample.len<MAX_DATA){while(pos<(int)p.length()&&p[pos]==' ')pos++;if(pos>=(int)p.length())break;int n=p.indexOf(' ',pos);String tok=(n<0)?p.substring(pos):p.substring(pos,n);tok.trim();uint8_t b;if(!parseByteToken(tok,b))return false;sample.data[sample.len++]=b;if(n<0)break;pos=n+1;} return sample.len>0;
}
IdState* findId(IdState*s,int count,uint16_t id){for(int i=0;i<count;i++)if(s[i].id==id)return&s[i];return nullptr;}
void addSample(IdState*s,int&count,uint16_t id,const Sample&x){IdState*r=findId(s,count,id);if(!r){if(count>=MAX_IDS)return;r=&s[count++];r->id=id;r->frameCount=0;r->sampleCount=0;}r->frameCount++;if(r->sampleCount<MAX_SAMPLES_PER_ID)r->samples[r->sampleCount++]=x;else{for(uint8_t i=1;i<MAX_SAMPLES_PER_ID;i++)r->samples[i-1]=r->samples[i];r->samples[MAX_SAMPLES_PER_ID-1]=x;}}
void processMonitorLine(String l){uint16_t id;Sample s;if(!parseCanLine(l,id,s))return;if(activeTarget==TARGET_CLOSED)addSample(closedSet,closedIds,id,s);else if(activeTarget==TARGET_OPEN)addSample(openSet,openIds,id,s);else if(activeTarget==TARGET_CLOSED2)addSample(closed2Set,closed2Ids,id,s);}
void ingestNotify(uint8_t*b,size_t len){for(size_t i=0;i<len;i++){char c=(char)b[i];if(monitorActive){if(c=='\r'||c=='\n'||c=='>'){if(monitorLine.length()){processMonitorLine(monitorLine);monitorLine="";}}else if(monitorLine.length()<160)monitorLine+=c;else monitorLine="";}else if(rx.length()<12000)rx+=c;}}
static void onNotify(BLERemoteCharacteristic*,uint8_t*b,size_t l,bool){ingestNotify(b,l);}
bool findElmCharacteristics(){auto*s=client->getService(BLEUUID(FFF0));if(!s)return false;auto*c1=s->getCharacteristic(BLEUUID(FFF1));auto*c2=s->getCharacteristic(BLEUUID(FFF2));if(!c1||!c2)return false;BLERemoteCharacteristic*cs[2]={c1,c2};for(auto*c:cs){if(c->canWrite()||c->canWriteNoResponse())writeChar=c;if(c->canNotify()||c->canIndicate())notifyChar=c;}if(!writeChar||!notifyChar)return false;notifyChar->registerForNotify(onNotify);return true;}
bool connectKonnwei(){if(connected&&client&&client->isConnected())return true;Serial.printf("[BLE] Connecting to %s ...\n",KONNWEI_MAC);if(!client){client=BLEDevice::createClient();client->setClientCallbacks(new ClientCB());}BLEAddress a(KONNWEI_MAC);if(!client->connect(a)){Serial.println("[BLE] direct connect failed");return false;}if(!findElmCharacteristics()){Serial.println("[BLE] FFF0/FFF1/FFF2 not found");client->disconnect();return false;}connected=true;Serial.println("[BLE] KONNWEI connected");return true;}
void rawWrite(const String&s){if(!connected||!writeChar)return;if(writeChar->canWriteNoResponse())writeChar->writeValue((uint8_t*)s.c_str(),s.length(),false);else writeChar->writeValue((uint8_t*)s.c_str(),s.length(),true);}
String waitPrompt(uint32_t ms=1500){uint32_t t=millis();while(millis()-t<ms){delay(5);if(rx.indexOf('>')>=0)break;}String r=rx;rx="";return r;}
String elm(const String&cmd,uint32_t ms=1500,bool pr=true){if(!connectKonnwei())return"NO_BLE";rx="";String tx=cmd;tx.trim();tx+="\r";if(pr)Serial.printf("\n[ELM TX] %s\n",cmd.c_str());rawWrite(tx);String r=waitPrompt(ms);if(pr){Serial.println("[ELM RX]");Serial.println(r);}return r;}
bool initElm(){if(!connectKonnwei())return false;Serial.println("\n========== ELM INIT ==========");elm("ATZ",2500);elm("ATE0");elm("ATL1");elm("ATS1");elm("ATH1");elm("ATSP0",2500);elm("0100",2500);elm("ATAR",1200);elm("ATH1");elm("ATS1");elm("ATL1");Serial.println("========== ELM READY ==========\n");return true;}
void clearSet(IdState*s,int&count){for(int i=0;i<MAX_IDS;i++){s[i].id=0;s[i].frameCount=0;s[i].sampleCount=0;}count=0;}
void clearCapture(CaptureTarget t){if(t==TARGET_CLOSED)clearSet(closedSet,closedIds);else if(t==TARGET_OPEN)clearSet(openSet,openIds);else if(t==TARGET_CLOSED2)clearSet(closed2Set,closed2Ids);}
void stopMonitor(){if(!connected)return;rawWrite("\r");delay(160);if(monitorLine.length()){processMonitorLine(monitorLine);monitorLine="";}monitorActive=false;rx="";}
const char* targetName(CaptureTarget t){return t==TARGET_CLOSED?"CLOSED":t==TARGET_OPEN?"OPEN":t==TARGET_CLOSED2?"CLOSED2":"NONE";}
void capture(CaptureTarget t){if(!connectKonnwei())return;clearCapture(t);elm("ATAR",700,false);elm("ATE0",700,false);elm("ATH1",700,false);elm("ATS1",700,false);elm("ATL1",700,false);activeTarget=t;monitorLine="";rx="";Serial.printf("\n[CAPTURE] %s duration=%lu ms\n",targetName(t),(unsigned long)captureMs);monitorActive=true;rawWrite("ATMA\r");uint32_t t0=millis();while(millis()-t0<captureMs)delay(2);stopMonitor();activeTarget=TARGET_NONE;int c=t==TARGET_CLOSED?closedIds:t==TARGET_OPEN?openIds:closed2Ids;Serial.printf("[CAPTURE] %s complete, IDs=%d\n",targetName(t),c);}
uint8_t modalLength(const IdState*s){if(!s||!s->sampleCount)return 0;uint8_t c[9]{};for(uint8_t i=0;i<s->sampleCount;i++)if(s->samples[i].len<=8)c[s->samples[i].len]++;uint8_t bl=0,bc=0;for(uint8_t l=1;l<=8;l++)if(c[l]>bc){bc=c[l];bl=l;}return bl;}
uint8_t modalByte(const IdState*s,uint8_t bi,uint8_t len){uint16_t h[256]{};if(!s)return 0;for(uint8_t i=0;i<s->sampleCount;i++)if(s->samples[i].len==len&&bi<len)h[s->samples[i].data[bi]]++;uint8_t bv=0;uint16_t bc=0;for(int v=0;v<256;v++)if(h[v]>bc){bc=h[v];bv=v;}return bv;}
float byteStability(const IdState*s,uint8_t bi,uint8_t len){if(!s||!s->sampleCount)return 0;uint8_t m=modalByte(s,bi,len);uint16_t same=0,u=0;for(uint8_t i=0;i<s->sampleCount;i++)if(s->samples[i].len==len&&bi<len){u++;if(s->samples[i].data[bi]==m)same++;}return u?(float)same/u:0;}
struct Candidate {
  uint16_t id = 0;
  float score = 0.0f;
  uint8_t len = 0;
  uint8_t changedBytes = 0;
  uint8_t changedMask[MAX_DATA] = {0};
  uint8_t closed[MAX_DATA] = {0};
  uint8_t open[MAX_DATA] = {0};
  uint8_t closed2[MAX_DATA] = {0};
  float stability = 0.0f;
};
float computeCandidate(uint16_t id,Candidate&o){IdState*a=findId(closedSet,closedIds,id),*b=findId(openSet,openIds,id),*c=findId(closed2Set,closed2Ids,id);if(!a||!b||!c)return-1;uint8_t l=modalLength(a);if(!l||l!=modalLength(b)||l!=modalLength(c))return-1;o.id=id;o.len=l;float score=0,ss=0;for(uint8_t i=0;i<l;i++){uint8_t x=modalByte(a,i,l),y=modalByte(b,i,l),z=modalByte(c,i,l);o.closed[i]=x;o.open[i]=y;o.closed2[i]=z;o.changedMask[i]=0;float st=(byteStability(a,i,l)+byteStability(b,i,l)+byteStability(c,i,l))/3;ss+=st;if(x==z&&x!=y){o.changedBytes++;o.changedMask[i]=x^y;score+=34+16*st;uint8_t d=x^y,bits=0;for(uint8_t k=0;k<8;k++)if(d&(1<<k))bits++;score+=bits==1?14:bits==2?8:bits<=4?3:0;}else if(x!=y&&y!=z)score-=12;else if(x!=z)score-=10;}o.stability=ss/l;if(!o.changedBytes)return-1;score+=o.changedBytes==1?18:o.changedBytes==2?7:-(o.changedBytes-2)*5;if(a->frameCount>=3&&b->frameCount>=3&&c->frameCount>=3)score+=8;score+=10*o.stability;if(score<0)score=0;if(score>100)score=100;o.score=score;return score;}
void printBytes(const uint8_t*d,uint8_t l){for(uint8_t i=0;i<l;i++){if(i)Serial.print(' ');if(d[i]<16)Serial.print('0');Serial.print(d[i],HEX);}}
void printChangedBits(const Candidate&c){for(uint8_t i=0;i<c.len;i++){uint8_t m=c.changedMask[i];if(!m)continue;Serial.printf("  Byte %u: %02X -> %02X -> %02X | changed bits:",i,c.closed[i],c.open[i],c.closed2[i]);for(uint8_t b=0;b<8;b++)if(m&(1<<b))Serial.printf(" b%u(%u->%u)",b,(c.closed[i]>>b)&1,(c.open[i]>>b)&1);Serial.println();}}
void analyze(){if(!closedIds||!openIds||!closed2Ids){Serial.println("[AI] Need CLOSED, OPEN and CLOSED2 captures first.");return;}Candidate r[MAX_IDS];int n=0;for(int i=0;i<openIds;i++){Candidate c;float s=computeCandidate(openSet[i].id,c);if(s>=0&&n<MAX_IDS)r[n++]=c;}for(int i=0;i<n-1;i++)for(int j=i+1;j<n;j++)if(r[j].score>r[i].score){Candidate t=r[i];r[i]=r[j];r[j]=t;}Serial.println("\n=== LOCAL SMART CAN ANALYSIS ===");if(!n){Serial.println("[AI] No repeatable candidate found. Try TIME:1800 and repeat.");return;}int show=n>topResults?topResults:n;for(int i=0;i<show;i++){auto&c=r[i];Serial.printf("\n#%d ID %03X SCORE %.1f/100 stability %.0f%%\n",i+1,c.id,c.score,c.stability*100);Serial.print(" CLOSED : ");printBytes(c.closed,c.len);Serial.print("\n OPEN   : ");printBytes(c.open,c.len);Serial.print("\n CLOSED2: ");printBytes(c.closed2,c.len);Serial.println();printChangedBits(c);}Serial.println("\nRepeat same test 2-3 times to verify.");}
void printHelp(){Serial.println("\nCommands: CLOSED, OPEN, CLOSED2, ANALYZE, RESET, INIT, TIME:1800, TOP:10, ELM:ATI, ELM:ATDP\nTest order: CLOSED -> open door -> OPEN -> close door -> CLOSED2 -> ANALYZE");}
void handleCommand(String c){c.trim();if(!c.length())return;String u=c;u.toUpperCase();if(u=="HELP")printHelp();else if(u=="INIT")initElm();else if(u=="CLOSED")capture(TARGET_CLOSED);else if(u=="OPEN")capture(TARGET_OPEN);else if(u=="CLOSED2")capture(TARGET_CLOSED2);else if(u=="ANALYZE"||u=="AI"||u=="COMPARE")analyze();else if(u=="RESET"){clearSet(closedSet,closedIds);clearSet(openSet,openIds);clearSet(closed2Set,closed2Ids);Serial.println("[RESET] all captures cleared");}else if(u.startsWith("TIME:")){long v=u.substring(5).toInt();if(v<400)v=400;if(v>2500)v=2500;captureMs=v;Serial.printf("[SET] capture=%lu ms\n",(unsigned long)captureMs);}else if(u.startsWith("TOP:")){long v=u.substring(4).toInt();if(v<1)v=1;if(v>30)v=30;topResults=v;}else if(u.startsWith("ELM:")){String at=c.substring(4);at.trim();elm(at,2500);}else Serial.println("[ERR] Type HELP");}
void setup(){Serial.begin(115200);delay(1200);Serial.println("\n=== JOURNEY CAN AUTO ANALYZER ===");BLEDevice::init("JOURNEY-CAN-AUTO-AI");if(connectKonnwei())initElm();else Serial.println("[BLE] Type INIT to retry");printHelp();}
void loop(){while(Serial.available()){char c=(char)Serial.read();if(c=='\r'||c=='\n'){if(serialLine.length()){String cmd=serialLine;serialLine="";handleCommand(cmd);}}else if(serialLine.length()<96)serialLine+=c;}delay(2);}
