import SwiftUI

struct SmartAIView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @AppStorage("punisher.ai.visual") private var visualAI = true
    @AppStorage("punisher.ai.plate") private var autoPlate = true
    @AppStorage("punisher.ai.color") private var smartColor = true
    @AppStorage("punisher.ai.alerts") private var smartAlerts = true
    @AppStorage("punisher.ai.trip") private var tripInsights = true
    @AppStorage("punisher.ai.obd") private var obdAI = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.05, green: 0.01, blue: 0.02), Color(red: 0.0, green: 0.06, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        PunisherBrandMark(size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PUNISHER AI")
                                .font(.system(size: 25, weight: .black, design: .rounded))
                            Text(pd(
                                "ذكاء مساعد للسيارة والتطبيق",
                                "Smart assistance for your car and app",
                                "یاریدەدەری زیرەک بۆ ئۆتۆمبێل و ئەپ",
                                "Araç ve uygulama için akıllı yardımcı",
                                "دستیار هوشمند برای خودرو و برنامه"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    aiCard(
                        title: "AI Visual Fit",
                        subtitle: pd(
                            "يحلل صورة السيارة ويضبط تلوين البودي ومكان وحجم وزاوية اللوحة.",
                            "Analyzes the vehicle image and auto-fits body color plus plate position, size and angle.",
                            "وێنەی ئۆتۆمبێل شیکردنەوە دەکات و ڕەنگی بۆدی و شوێن و قەبارە و گۆشەی تەختە ژمارە خۆکار ڕێکدەخات.",
                            "Araç görselini analiz eder; gövde rengini ve plakanın konum, boyut ve açısını otomatik ayarlar.",
                            "تصویر خودرو را تحلیل می‌کند و رنگ بدنه و محل، اندازه و زاویه پلاک را خودکار تنظیم می‌کند."
                        ),
                        icon: "wand.and.stars",
                        tint: .cyan,
                        status: pd("يعمل الآن", "Active now", "ئێستا چالاکە", "Şimdi aktif", "اکنون فعال")
                    ) {
                        Toggle(pd("تشغيل Visual AI", "Enable Visual AI", "Visual AI چالاک بکە", "Visual AI'ı aç", "فعال‌سازی Visual AI"), isOn: $visualAI)
                        Toggle(pd("تلوين البودي الذكي", "Smart body recoloring", "ڕەنگکردنی زیرەکی بۆدی", "Akıllı gövde renklendirme", "رنگ‌آمیزی هوشمند بدنه"), isOn: $smartColor)
                        Toggle(pd("تثبيت اللوحة تلقائياً", "Automatic plate fit", "ڕێکخستنی خۆکاری تەختە", "Otomatik plaka yerleşimi", "تنظیم خودکار پلاک"), isOn: $autoPlate)
                    }

                    aiCard(
                        title: "AI OBD Diagnostics",
                        subtitle: pd(
                            "يلخص الأعطال ويفسر DTC وبيانات الحساسات عند وصول بيانات OBD الحقيقية.",
                            "Summarizes faults, DTCs and sensor data when real OBD data is available.",
                            "کاتێک داتای ڕاستەقینەی OBD هات، هەڵەکان و DTC و داتای سنسۆرەکان کورت و ڕوون دەکات.",
                            "Gerçek OBD verisi geldiğinde arızaları, DTC kodlarını ve sensör verilerini açıklar.",
                            "هنگام دریافت داده واقعی OBD، خطاها، DTC و داده حسگرها را خلاصه و تفسیر می‌کند."
                        ),
                        icon: "waveform.path.ecg.rectangle",
                        tint: .red,
                        status: garage.activeVehicle?.hasESP == true
                            ? pd("جاهز للبيانات", "Ready for data", "بۆ داتا ئامادەیە", "Veri için hazır", "آماده دریافت داده")
                            : pd("يحتاج ربط السيارة", "Needs vehicle connection", "پێویستی بە پەیوەستکردنی ئۆتۆمبێلە", "Araç bağlantısı gerekli", "نیاز به اتصال خودرو")
                    ) {
                        Toggle(pd("مساعد التشخيص", "Diagnostic assistant", "یاریدەدەری پشکنین", "Teşhis yardımcısı", "دستیار عیب‌یابی"), isOn: $obdAI)
                    }

                    aiCard(
                        title: "Smart Alerts",
                        subtitle: pd(
                            "يراقب تغيّر الفولت والحرارة والاتصال والحركة وينبه على القيم غير الطبيعية عند توفر التليمتري.",
                            "Watches voltage, temperature, connectivity and motion and flags abnormal values when telemetry is available.",
                            "ڤۆڵت، پلەی گەرمی، پەیوەندی و جووڵە چاودێری دەکات و لە دۆخی نائاسایی ئاگادار دەکات.",
                            "Telemetri varsa voltaj, sıcaklık, bağlantı ve hareketi izleyip anormallikleri bildirir.",
                            "در صورت وجود تله‌متری، ولتاژ، دما، اتصال و حرکت را پایش و موارد غیرعادی را هشدار می‌دهد."
                        ),
                        icon: "bell.badge.fill",
                        tint: .orange,
                        status: pd("جاهز مع التليمتري", "Ready with telemetry", "لەگەڵ تلیمەتری ئامادەیە", "Telemetri ile hazır", "با تله‌متری آماده")
                    ) {
                        Toggle(pd("تنبيهات ذكية", "Smart alerts", "ئاگادارکردنەوەی زیرەک", "Akıllı uyarılar", "هشدارهای هوشمند"), isOn: $smartAlerts)
                    }

                    aiCard(
                        title: "Trip AI",
                        subtitle: pd(
                            "ملخص رحلة: وقت، مسافة، توقفات وسلوك قيادة بعد ربط GPS وبيانات السيارة.",
                            "Trip summary for time, distance, stops and driving behavior after GPS and vehicle data are connected.",
                            "پوختەی گەشت: کات، دووری، وەستان و شێوازی لێخوڕین دوای پەیوەستکردنی GPS و داتای ئۆتۆمبێل.",
                            "GPS ve araç verileri bağlandığında süre, mesafe, duraklar ve sürüş davranışı özeti.",
                            "خلاصه سفر شامل زمان، مسافت، توقف‌ها و رفتار رانندگی پس از اتصال GPS و داده خودرو."
                        ),
                        icon: "road.lanes",
                        tint: .green,
                        status: garage.activeVehicle?.hasGPSFix == true
                            ? pd("بيانات GPS متوفرة", "GPS data available", "داتای GPS بەردەستە", "GPS verisi mevcut", "داده GPS موجود")
                            : pdt("waiting_gps")
                    ) {
                        Toggle(pd("تحليل الرحلات", "Trip insights", "شیکردنەوەی گەشت", "Yolculuk analizi", "تحلیل سفر"), isOn: $tripInsights)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label(pd("مهم", "Important", "گرنگ", "Önemli", "مهم"), systemImage: "shield.checkered")
                            .font(.headline)
                            .foregroundStyle(.cyan)
                        Text(pd(
                            "Visual AI يعمل محلياً على صور السيارة. ميزات التشخيص والتنبيهات والرحلات ما تخمّن بيانات؛ تشتغل فقط من توصل قراءات حقيقية من ESP/OBD/GPS.",
                            "Visual AI runs locally on vehicle images. Diagnostics, alerts and trip insights never invent data; they activate only when real ESP/OBD/GPS readings are available.",
                            "Visual AI لەسەر وێنەکانی ئۆتۆمبێل بە ناوخۆ کاردەکات. پشکنین و ئاگادارکردنەوە و گەشت هیچ داتایەک خەیاڵ ناکەن؛ تەنها بە داتای ڕاستەقینەی ESP/OBD/GPS چالاک دەبن.",
                            "Visual AI araç görsellerinde yerel çalışır. Teşhis, uyarı ve yolculuk özellikleri veri uydurmaz; yalnızca gerçek ESP/OBD/GPS okumaları geldiğinde çalışır.",
                            "Visual AI به‌صورت محلی روی تصاویر خودرو کار می‌کند. عیب‌یابی، هشدار و سفر داده جعلی تولید نمی‌کنند و فقط با داده واقعی ESP/OBD/GPS فعال می‌شوند."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(16)
            }
        }
        .navigationTitle(pdt("smart_ai"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aiCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        status: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(status)
                        .font(.caption2.bold())
                        .foregroundStyle(tint)
                }
                Spacer()
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .tint(tint)
        }
        .padding(15)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(tint.opacity(0.18)))
    }
}
