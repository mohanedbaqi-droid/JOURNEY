# فتح JOURNEY في Xcode

1. ثبّت Xcode 15 أو أحدث وXcodeGen.
2. افتح Terminal داخل مجلد `ios`.
3. نفّذ `xcodegen generate`.
4. افتح `JourneyControl.xcodeproj` واختر فريق التوقيع وiPhone حقيقي.
5. شغّل التطبيق، أضف `DEVICE_ID` للبورد، ثم افتح الترس وأدخل إعدادات MQTT/TLS.

التطبيق لا يحتوي Demo Mode. الأزرار ترسل إلى `journey/<deviceId>/cmd` عند ظهور حالة **متصل** فقط. كلمة مرور MQTT تُحفظ في Keychain.

قبل تفعيل المخارج، اترك `ENABLE_OUTPUTS = false` في Firmware وحدد GPIO واختبر لوحة الأوتوكبلر بالأفوميتر.
