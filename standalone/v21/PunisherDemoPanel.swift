import SwiftUI

/// OFFLINE, OPT-IN simulator. It deliberately has no BLE, HTTP, GPS or GPIO dependencies.
/// All state is synthetic and disappears when the demo view is recreated.
struct PunisherDemoPanel: View {
    let vehicleID: UUID

    @State private var locked = true
    @State private var engineRunning = false
    @State private var alarmActive = false
    @State private var showStartConfirmation = false
    @State private var notice = ""

    private var simulationTitle: String {
        pd("محاكاة ESP • تجربة فقط", "ESP simulator • Demo only",
           "هاوشێوەسازی ESP", "ESP simülatörü", "شبیه‌ساز ESP")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(simulationTitle, systemImage: "testtube.2")
                .font(.headline.bold())
                .foregroundStyle(.orange)

            Text(pd("بيانات تجريبية فقط — ماكو أي اتصال حقيقي بالسيارة أو GPS أو OBD.",
                    "Synthetic data only — not connected to a vehicle, GPS or OBD.",
                    "تەنها داتای تاقیکردنەوە، پەیوەندی ڕاستەقینە نییە.",
                    "Sahte veriler; araca gerçek bağlantı yok.",
                    "فقط اطلاعات آزمایشی، بدون اتصال واقعی."))
                .font(.caption)
                .foregroundStyle(.orange)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                stat("RPM", engineRunning ? "780" : "0")
                stat("OBD", engineRunning ? "14.20 V" : "12.58 V")
                stat("ESP", "32 °C")
                stat("GPS", "DEMO")
                stat(pd("المحرك", "Engine", "ماتۆڕ", "Motor", "موتور"),
                     engineRunning ? "ON" : "OFF")
                stat(pd("القفل", "Lock", "قفڵ", "Kilit", "قفل"),
                     locked ? "LOCK" : "UNLOCK")
            }

            HStack(spacing: 8) {
                simButton(pd("قفل", "Lock", "قفڵ", "Kilitle", "قفل"), icon: "lock.fill") {
                    locked = true
                    notice = "SIM: LOCK"
                }
                simButton(pd("فتح", "Unlock", "کردنەوە", "Aç", "باز"), icon: "lock.open.fill") {
                    locked = false
                    notice = "SIM: UNLOCK"
                }
                simButton(pd("تشغيل", "Start", "پێکردن", "Başlat", "روشن"), icon: "power") {
                    showStartConfirmation = true
                }
                simButton(pd("إنذار", "Alarm", "ئاگادارکردنەوە", "Alarm", "هشدار"), icon: "bell.fill") {
                    alarmActive.toggle()
                    notice = alarmActive ? "SIM: ALARM ON" : "SIM: ALARM OFF"
                }
            }

            HStack {
                Text(notice.isEmpty ? "SIM • vehicle: \(vehicleID.uuidString.prefix(8))" : notice)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(pd("إعادة", "Reset", "ڕێکخستنەوە", "Sıfırla", "بازنشانی")) {
                    locked = true
                    engineRunning = false
                    alarmActive = false
                    notice = ""
                }
                .font(.caption.bold())
            }
        }
        .padding(14)
        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.orange.opacity(0.36)))
        .confirmationDialog(
            pd("تشغيل المحرك الافتراضي فقط؟", "Start the synthetic engine only?",
               "تەنها ماتۆڕی ساختە؟", "Sanal motoru başlat?", "موتور آزمایشی روشن شود؟"),
            isPresented: $showStartConfirmation,
            titleVisibility: .visible
        ) {
            Button(pd("تأكيد التجربة", "Confirm demo", "پشتڕاستکردنەوە",
                      "Demoyu onayla", "تأیید آزمایش")) {
                engineRunning = true
                notice = "SIM: ENGINE STARTED"
            }
            Button(pd("إلغاء", "Cancel", "هەڵوەشاندنەوە", "İptal", "لغو"), role: .cancel) {}
        } message: {
            Text(pd("هذا الأمر لا يتصل بالسيارة ولا يشغّل محركها الحقيقي.",
                    "No real vehicle command will be sent.",
                    "هیچ فەرمانێکی ڕاستەقینە نانێردرێت.",
                    "Gerçek araca komut gönderilmez.",
                    "هیچ فرمان واقعی ارسال نخواهد شد."))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold().monospacedDigit()).foregroundStyle(.cyan).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
    }

    private func simButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                Text(label).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.caption.bold())
            .frame(maxWidth: .infinity, minHeight: 57)
            .foregroundStyle(.cyan)
            .background(.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
