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
                            Text(pd("ذكاء مساعد للسيارة والتطبيق", "Smart assistance for your car and app"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    aiCard(
                        title: pd("AI Visual Fit", "AI Visual Fit"),
                        subtitle: pd("يحلل صورة السيارة ويضبط تلوين البودي ومكان وحجم وزاوية اللوحة.", "Analyzes the vehicle image and auto-fits body color plus plate position, size and angle."),
                        icon: "wand.and.stars",
                        tint: .cyan,
                        status: pd("يعمل الآن", "Active now")
                    ) {
                        Toggle(pd("تشغيل Visual AI", "Enable Visual AI"), isOn: $visualAI)
                        Toggle(pd("تلوين البودي الذكي", "Smart body recoloring"), isOn: $smartColor)
                        Toggle(pd("تثبيت اللوحة تلقائياً", "Automatic plate fit"), isOn: $autoPlate)
                    }

                    aiCard(
                        title: pd("AI OBD Diagnostics", "AI OBD Diagnostics"),
                        subtitle: pd("يلخص الأعطال ويفسر DTC وبيانات الحساسات عند وصول بيانات OBD الحقيقية.", "Summarizes faults, DTCs and sensor data when real OBD data is available."),
                        icon: "waveform.path.ecg.rectangle",
                        tint: .red,
                        status: garage.activeVehicle?.hasESP == true ? pd("جاهز للبيانات", "Ready for data") : pd("يحتاج ربط السيارة", "Needs vehicle connection")
                    ) {
                        Toggle(pd("مساعد التشخيص", "Diagnostic assistant"), isOn: $obdAI)
                    }

                    aiCard(
                        title: pd("Smart Alerts", "Smart Alerts"),
                        subtitle: pd("يراقب تغيّر الفولت والحرارة والاتصال والحركة وينبه على القيم غير الطبيعية عند توفر التليمتري.", "Watches voltage, temperature, connectivity and motion and flags abnormal values when telemetry is available."),
                        icon: "bell.badge.fill",
                        tint: .orange,
                        status: pd("جاهز مع التليمتري", "Ready with telemetry")
                    ) {
                        Toggle(pd("تنبيهات ذكية", "Smart alerts"), isOn: $smartAlerts)
                    }

                    aiCard(
                        title: pd("Trip AI", "Trip AI"),
                        subtitle: pd("ملخص رحلة: وقت، مسافة، توقفات وسلوك قيادة بعد ربط GPS وبيانات السيارة.", "Trip summary for time, distance, stops and driving behavior after GPS and vehicle data are connected."),
                        icon: "road.lanes",
                        tint: .green,
                        status: garage.activeVehicle?.hasGPSFix == true ? pd("بيانات GPS متوفرة", "GPS data available") : pd("بانتظار GPS", "Waiting for GPS")
                    ) {
                        Toggle(pd("تحليل الرحلات", "Trip insights"), isOn: $tripInsights)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label(pd("مهم", "Important"), systemImage: "shield.checkered")
                            .font(.headline)
                            .foregroundStyle(.cyan)
                        Text(pd(
                            "Visual AI يعمل محلياً على صور السيارة. ميزات التشخيص والتنبيهات والرحلات ما تخمّن بيانات؛ تشتغل فقط من توصل قراءات حقيقية من ESP/OBD/GPS.",
                            "Visual AI runs locally on vehicle images. Diagnostics, alerts and trip insights never invent data; they activate only when real ESP/OBD/GPS readings are available."
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
        .navigationTitle(pd("الذكاء", "Smart AI"))
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
