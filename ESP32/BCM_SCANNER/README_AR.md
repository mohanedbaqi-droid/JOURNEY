# JOURNEY BCM Scanner (read-only)
هدفه اكتشاف رسائل BCM الفعلية في Dodge Journey 2017 عبر KONNWEI BLE بدون كتابة إعدادات أو تشغيل actuators.

## الاتصال
- Name: KONNWEI
- MAC: 22:C0:20:12:8A:EE
- يحاول MAC مباشرة PUBLIC ثم RANDOM؛ إذا فشل يسوي scan لمدة 8 ثوانٍ ويبحث عن الاسم.

## الاستخدام
1. ارفع السكيتش على ESP32 وافتح Serial Monitor = 115200.
2. انتظر [OK] ثم نتائج ATDP / ATDPN / 0100 / VIN.
3. اكتب MON. السكيتش يشغل ATH1 ثم ATMA (استماع سلبي).
4. غيّر حالة واحدة فقط لمدة 5-10 ثوانٍ: باب السائق، LOCK، UNLOCK، يمين، يسار، Low Beam، ACC.
5. اكتب STOP بين كل تجربة واحفظ الـSerial log.
6. قارن الـCAN IDs والبايتات التي تتغير باستمرار مع نفس الحدث.

ملاحظة: Journey/Freemont يستخدم أكثر من CAN bus على منفذ OBD. إذا KONNWEI لا يبدّل إلى شبكة الـBody المتاحة على pins 3/11 فلن تظهر رسائل BCM المطلوبة حتى لو الكود صحيح؛ نتائج ATDP/ATDPN وATMA ستوضح ذلك.

هذا السكيتش مرحلة اكتشاف فقط؛ لا يرسل أوامر كتابة BCM.
