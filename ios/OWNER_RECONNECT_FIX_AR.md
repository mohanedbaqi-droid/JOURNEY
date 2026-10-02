# إصلاح المدير بعد إعادة الاتصال

التطبيق يحتفظ بآخر حالة مدير مؤكدة لكل deviceID في UserDefaults، ويطلب owner_status من ESP بعد كل reconnect.
لا يعتبر فقدان BLE دليلاً على حذف المدير، ولا يعرض زر تسجيل مدير جديد إلا بعد استلام حالة مؤكدة من ESP بأن authorizedPhoneCount = 0.
