import SwiftUI

enum PDLanguage: String, CaseIterable, Identifiable {
    case ar
    case en
    case ku
    case tr
    case fa

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ar: return "العربية"
        case .en: return "English"
        case .ku: return "کوردی (سۆرانی)"
        case .tr: return "Türkçe"
        case .fa: return "فارسی"
        }
    }

    var shortLabel: String {
        switch self {
        case .ar: return "AR"
        case .en: return "EN"
        case .ku: return "KU"
        case .tr: return "TR"
        case .fa: return "FA"
        }
    }

    var isRTL: Bool {
        self == .ar || self == .ku || self == .fa
    }
}

enum PDLocalization {
    static let key = "punisher.language"

    static var current: PDLanguage {
        PDLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "ar") ?? .ar
    }

    static var layoutDirection: LayoutDirection {
        current.isRTL ? .rightToLeft : .leftToRight
    }
}

func pd(_ ar: String, _ en: String) -> String {
    switch PDLocalization.current {
    case .ar: return ar
    case .en: return en
    case .ku: return en
    case .tr: return en
    case .fa: return en
    }
}

func pd(_ ar: String, _ en: String, _ ku: String, _ tr: String, _ fa: String) -> String {
    switch PDLocalization.current {
    case .ar: return ar
    case .en: return en
    case .ku: return ku
    case .tr: return tr
    case .fa: return fa
    }
}


func pdt(_ key: String) -> String {
    let table: [String: [PDLanguage: String]] = [
        "home": [.ar:"الرئيسية", .en:"Home", .ku:"سەرەکی", .tr:"Ana Sayfa", .fa:"خانه"],
        "garage": [.ar:"الكراج", .en:"Garage", .ku:"گاراژ", .tr:"Garaj", .fa:"گاراژ"],
        "map": [.ar:"الخارطة", .en:"Map", .ku:"نەخشە", .tr:"Harita", .fa:"نقشه"],
        "settings": [.ar:"الإعدادات", .en:"Settings", .ku:"ڕێکخستنەکان", .tr:"Ayarlar", .fa:"تنظیمات"],
        "about": [.ar:"حول", .en:"About", .ku:"دەربارە", .tr:"Hakkında", .fa:"درباره"],
        "add_car": [.ar:"إضافة سيارة", .en:"Add vehicle", .ku:"زیادکردنی ئۆتۆمبێل", .tr:"Araç ekle", .fa:"افزودن خودرو"],
        "add_first_car": [.ar:"إضافة أول سيارة", .en:"Add first vehicle", .ku:"یەکەم ئۆتۆمبێل زیاد بکە", .tr:"İlk aracı ekle", .fa:"افزودن اولین خودرو"],
        "garage_empty": [.ar:"الكراج فارغ", .en:"Garage is empty", .ku:"گاراژ بەتاڵە", .tr:"Garaj boş", .fa:"گاراژ خالی است"],
        "active": [.ar:"نشطة", .en:"Active", .ku:"چالاک", .tr:"Aktif", .fa:"فعال"],
        "vehicle_color_plate": [.ar:"لون ورقم السيارة", .en:"Vehicle color & plate", .ku:"ڕەنگ و ژمارەی ئۆتۆمبێل", .tr:"Araç rengi ve plaka", .fa:"رنگ و پلاک خودرو"],
        "choose_color_plate": [.ar:"اختار اللون واكتب رقم السيارة", .en:"Choose color and enter the plate", .ku:"ڕەنگ هەڵبژێرە و ژمارە بنووسە", .tr:"Rengi seç ve plakayı gir", .fa:"رنگ را انتخاب و پلاک را وارد کنید"],
        "quick_control": [.ar:"التحكم السريع", .en:"Quick controls", .ku:"کۆنترۆڵی خێرا", .tr:"Hızlı kontroller", .fa:"کنترل سریع"],
        "lock": [.ar:"قفل", .en:"Lock", .ku:"قفڵ", .tr:"Kilitle", .fa:"قفل"],
        "unlock": [.ar:"فتح", .en:"Unlock", .ku:"کردنەوە", .tr:"Kilidi aç", .fa:"باز کردن"],
        "start": [.ar:"تشغيل", .en:"Start", .ku:"پێکردن", .tr:"Çalıştır", .fa:"روشن کردن"],
        "alarm": [.ar:"إنذار", .en:"Alarm", .ku:"ئاگادارکردنەوە", .tr:"Alarm", .fa:"هشدار"],
        "profile_ready": [.ar:"جاهز بالبروفايل", .en:"Ready in profile", .ku:"لە پرۆفایلدا ئامادەیە", .tr:"Profilde hazır", .fa:"در پروفایل آماده"],
        "not_enabled": [.ar:"غير مفعّل", .en:"Not enabled", .ku:"چالاک نییە", .tr:"Etkin değil", .fa:"فعال نیست"],
        "vehicles": [.ar:"سيارات", .en:"Vehicles", .ku:"ئۆتۆمبێلەکان", .tr:"Araçlar", .fa:"خودروها"],
        "not_linked": [.ar:"غير مربوط", .en:"Not linked", .ku:"پەیوەست نییە", .tr:"Bağlı değil", .fa:"متصل نیست"],
        "linked": [.ar:"مربوط", .en:"Linked", .ku:"پەیوەستە", .tr:"Bağlı", .fa:"متصل"],
        "profile": [.ar:"البروفايل", .en:"Profile", .ku:"پرۆفایل", .tr:"Profil", .fa:"پروفایل"],
        "language": [.ar:"اللغة", .en:"Language", .ku:"زمان", .tr:"Dil", .fa:"زبان"],
        "language_note": [.ar:"تتغير لغة الواجهة مباشرة بدون إعادة تثبيت.", .en:"The interface language changes instantly without reinstalling.", .ku:"زمانی ڕووکار دەستبەجێ دەگۆڕێت بەبێ دامەزراندنەوە.", .tr:"Arayüz dili yeniden kurulum olmadan anında değişir.", .fa:"زبان رابط بدون نصب مجدد فوراً تغییر می‌کند."],
        "active_vehicle": [.ar:"السيارة النشطة", .en:"Active vehicle", .ku:"ئۆتۆمبێلی چالاک", .tr:"Aktif araç", .fa:"خودروی فعال"],
        "vehicle": [.ar:"السيارة", .en:"Vehicle", .ku:"ئۆتۆمبێل", .tr:"Araç", .fa:"خودرو"],
        "model": [.ar:"النوع", .en:"Model", .ku:"مۆدێل", .tr:"Model", .fa:"مدل"],
        "manage_garage": [.ar:"إدارة الكراج", .en:"Manage garage", .ku:"بەڕێوەبردنی گاراژ", .tr:"Garajı yönet", .fa:"مدیریت گاراژ"],
        "connection": [.ar:"الاتصال", .en:"Connectivity", .ku:"پەیوەندی", .tr:"Bağlantı", .fa:"اتصال"],
        "connect_esp": [.ar:"ربط ESP", .en:"Link ESP", .ku:"پەیوەستکردنی ESP", .tr:"ESP bağla", .fa:"اتصال ESP"],
        "gps_tracking": [.ar:"إعداد التتبع والموقع", .en:"Tracking and location setup", .ku:"ڕێکخستنی شوێن و بەدواداچوون", .tr:"Takip ve konum ayarı", .fa:"تنظیم ردیابی و موقعیت"],
        "obd_diag": [.ar:"التشخيص وبيانات السيارة", .en:"Diagnostics and vehicle data", .ku:"پشکنین و داتای ئۆتۆمبێل", .tr:"Arıza teşhisi ve araç verileri", .fa:"عیب‌یابی و داده‌های خودرو"],
        "app": [.ar:"التطبيق", .en:"App", .ku:"ئەپ", .tr:"Uygulama", .fa:"برنامه"],
        "notifications": [.ar:"الإشعارات", .en:"Notifications", .ku:"ئاگادارکردنەوەکان", .tr:"Bildirimler", .fa:"اعلان‌ها"],
        "about_app": [.ar:"حول التطبيق", .en:"About the app", .ku:"دەربارەی ئەپ", .tr:"Uygulama hakkında", .fa:"درباره برنامه"],
        "smart_ai": [.ar:"الذكاء", .en:"Smart AI", .ku:"زیرەکی", .tr:"Akıllı AI", .fa:"هوش مصنوعی"],
        "smart_ai_sub": [.ar:"ذكاء للصور والتشخيص والتنبيهات والرحلات", .en:"AI for visuals, diagnostics, alerts and trips", .ku:"زیرەکی بۆ وێنە و پشکنین و ئاگادارکردنەوە و گەشت", .tr:"Görsel, teşhis, uyarı ve yolculuk AI", .fa:"هوش برای تصویر، عیب‌یابی، هشدار و سفر"],
        "version": [.ar:"الإصدار", .en:"Version", .ku:"وەشان", .tr:"Sürüm", .fa:"نسخه"],
        "fleet_map": [.ar:"خارطة السيارات", .en:"Fleet map", .ku:"نەخشەی ئۆتۆمبێلەکان", .tr:"Araç haritası", .fa:"نقشه خودروها"],
        "waiting_gps": [.ar:"بانتظار بيانات GPS", .en:"Waiting for GPS data", .ku:"چاوەڕێی داتای GPS", .tr:"GPS verisi bekleniyor", .fa:"در انتظار داده GPS"],
        "speed": [.ar:"السرعة", .en:"Speed", .ku:"خێرایی", .tr:"Hız", .fa:"سرعت"],
        "status": [.ar:"الحالة", .en:"Status", .ku:"دۆخ", .tr:"Durum", .fa:"وضعیت"],
        "online": [.ar:"متصل", .en:"Online", .ku:"ئۆنلاین", .tr:"Çevrimiçi", .fa:"آنلاین"],
        "offline": [.ar:"غير متصل", .en:"Offline", .ku:"ئۆفلاین", .tr:"Çevrimdışı", .fa:"آفلاین"],
        "moving": [.ar:"متحركة", .en:"Moving", .ku:"لە جووڵەدایە", .tr:"Hareket ediyor", .fa:"در حرکت"],
        "stopped": [.ar:"متوقفة", .en:"Stopped", .ku:"وەستاوە", .tr:"Duruyor", .fa:"متوقف"],
        "make_active": [.ar:"اعتماد للتحكم", .en:"Set active", .ku:"بیکە چالاک", .tr:"Aktif yap", .fa:"فعال کردن"],
        "choose_vehicle": [.ar:"اختيار أول سيارة", .en:"Choose first vehicle", .ku:"یەکەم ئۆتۆمبێل هەڵبژێرە", .tr:"İlk aracı seç", .fa:"انتخاب اولین خودرو"],
        "make": [.ar:"ماركة الصنع", .en:"Make", .ku:"براند", .tr:"Marka", .fa:"برند"],
        "year": [.ar:"سنة الصنع", .en:"Year", .ku:"ساڵی دروستکردن", .tr:"Yıl", .fa:"سال"],
        "choose": [.ar:"اختار", .en:"Choose", .ku:"هەڵبژێرە", .tr:"Seç", .fa:"انتخاب"],
        "optional_name": [.ar:"اسم اختياري", .en:"Optional name", .ku:"ناوی ئارەزوومەندانە", .tr:"İsteğe bağlı ad", .fa:"نام اختیاری"],
        "add_to_garage": [.ar:"إضافة إلى الكراج واعتمادها", .en:"Add to garage and set active", .ku:"زیادکردن بۆ گاراژ و چالاککردن", .tr:"Garaja ekle ve aktif yap", .fa:"افزودن به گاراژ و فعال کردن"],
        "close": [.ar:"إغلاق", .en:"Close", .ku:"داخستن", .tr:"Kapat", .fa:"بستن"],
        "appearance": [.ar:"شكل السيارة", .en:"Vehicle appearance", .ku:"دەرکەوتنی ئۆتۆمبێل", .tr:"Araç görünümü", .fa:"ظاهر خودرو"],
        "vehicle_color": [.ar:"لون السيارة", .en:"Vehicle color", .ku:"ڕەنگی ئۆتۆمبێل", .tr:"Araç rengi", .fa:"رنگ خودرو"],
        "iraqi_plate": [.ar:"رقم السيارة العراقي", .en:"Iraqi plate", .ku:"ژمارەی عێراقی", .tr:"Irak plakası", .fa:"پلاک عراقی"],
        "governorate": [.ar:"المحافظة", .en:"Governorate", .ku:"پارێزگا", .tr:"İl", .fa:"استان"],
        "letter": [.ar:"الحرف", .en:"Letter", .ku:"پیت", .tr:"Harf", .fa:"حرف"],
        "number_6": [.ar:"الرقم • حتى 6 أرقام", .en:"Number • up to 6 digits", .ku:"ژمارە • تا ٦ ژمارە", .tr:"Numara • en fazla 6 hane", .fa:"شماره • تا ۶ رقم"],
        "final_format": [.ar:"الشكل النهائي", .en:"Final format", .ku:"شێوەی کۆتایی", .tr:"Son biçim", .fa:"فرمت نهایی"],
        "save_appearance": [.ar:"حفظ شكل السيارة", .en:"Save appearance", .ku:"پاشەکەوتکردنی دەرکەوتن", .tr:"Görünümü kaydet", .fa:"ذخیره ظاهر"],
        "developer": [.ar:"المطور", .en:"Developer", .ku:"گەشەپێدەر", .tr:"Geliştirici", .fa:"توسعه‌دهنده"],
        "company": [.ar:"الجهة", .en:"Business", .ku:"ناوەند", .tr:"İşletme", .fa:"مجموعه"],
        "full_control": [.ar:"تحكم كامل بسيارتك", .en:"Full control of your vehicle", .ku:"کۆنترۆڵی تەواوی ئۆتۆمبێلەکەت", .tr:"Aracınızın tam kontrolü", .fa:"کنترل کامل خودروی شما"]
    ]
    return table[key]?[PDLocalization.current] ?? table[key]?[.en] ?? key
}
