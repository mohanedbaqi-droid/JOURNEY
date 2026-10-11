import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyWidgetSettingsSection: View {
    @EnvironmentObject private var mqtt: MQTTService
    @State private var extensionPresent = false
    @State private var identityMatches = false
    @State private var signingMessage = ""
    @State private var refreshed = false
    @AppStorage("journey.liveActivity.enabled") private var liveActivityEnabled = false

    var body: some View {
        Section {
            Toggle(isOn: $liveActivityEnabled) {
                Label(JL("حالة السيارة المباشرة على شاشة القفل", "Live vehicle status on Lock Screen"), systemImage: "car.side.fill")
            }
            .onChange(of: liveActivityEnabled) { _, _ in
                mqtt.syncSelectedWidget(force: true)
            }
            if !ActivityAuthorizationInfo().areActivitiesEnabled {
                Label(JL("فعّل Live Activities من إعدادات iPhone حتى تظهر حالة السيارة على شاشة القفل.", "Enable Live Activities in iPhone Settings to show vehicle status on the Lock Screen."), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Text(JL("هذا بديل لشاشة القفل يعمل بدون مشاركة App Group، وليس بديلاً عن ويدجت الشاشة الرئيسية. يتحدث من التطبيق عندما تصله قراءة جديدة، ولا يراقب السيارة مستقلاً إذا توقف التطبيق.", "This Lock Screen status works without App Group sharing. It does not replace the Home Screen widget and updates only as the app receives vehicle data."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            Label(extensionPresent
                ? JL("ملف الويدجيت موجود", "Widget extension file is present")
                : JL("ملف الويدجيت غير موجود بالتثبيت", "Widget extension is missing from this installation"),
                systemImage: extensionPresent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(extensionPresent ? Color.green : Color.orange)
            if extensionPresent {
                Label(identityMatches
                    ? JL("هوية الويدجيت مرتبطة بالتطبيق", "Widget identity matches JOURNEY")
                    : JL("هوية الويدجيت تغيّرت أثناء التوقيع؛ أعد توقيع التطبيق والإضافة معاً", "Widget identity changed during signing; re-sign the app and extension together"),
                    systemImage: identityMatches ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(identityMatches ? Color.green : Color.orange)
                Text(signingMessage).font(.footnote).foregroundStyle(.secondary)
            }
            if JourneyWidgetStore.groupURL != nil {
                Label(JL("مشاركة App Group متاحة", "App Group sharing available"),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(JL("صلاحية App Group غير متاحة بالتوقيع الحالي", "App Group entitlement unavailable"),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if JourneyWidgetStore.keychainSnapshotPresent {
                Label(JL("نسخة Keychain البديلة محفوظة — جرّب الويدجت", "Keychain backup stored — test the widget"),
                      systemImage: "key.fill")
                    .foregroundStyle(.cyan)
                Text(JL("الحفظ داخل التطبيق ما يثبت وصول الويدجت. إذا ظهرت القراءات على ويدجت الشاشة الرئيسية فالمشاركة نجحت.",
                        "App-side storage alone does not prove extension access. If readings appear on the Home Screen widget, sharing is confirmed."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label(JL("نسخة Keychain البديلة غير جاهزة", "Keychain fallback not ready"),
                      systemImage: "key")
                    .foregroundStyle(.orange)
            }
            if JourneyWidgetStore.groupURL == nil {
                Text(JL("تگدر تجرب توقيع الويدجت بهوية مستقلة من SideStore: Keep App Extensions (Register App ID for Each Extension). هذا قد يستهلك App ID إضافي وما يضمن مشاركة البيانات.",
                        "Try separate extension provisioning with SideStore: Keep App Extensions (Register App ID for Each Extension). This may use an additional App ID and does not guarantee sharing."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(JL("الفتح والقفل بالويدجت يفتحون JOURNEY ليرسل الأمر عبر اتصال المالك. التشغيل يتطلب تأكيد وFace ID.", "Widget lock/unlock open JOURNEY to send through the owner's connection. Engine start requires confirmation and Face ID.")).font(.footnote)
            Text(JL("الويدجيت الكبير يعرض كل القراءات المتاحة ووقت آخر تحديث. توقيت التحديث بالخلفية يحدده iOS.", "The large widget shows all available readings and the last update time. iOS schedules background widget refreshes.")).font(.footnote)
            Text(JL("ابحث عن JOURNEY بقائمة ويدجيت الشاشة الرئيسية أو شاشة القفل.", "Look for JOURNEY in the Home Screen or Lock Screen widget gallery."))
                .font(.footnote)
            Button(JL("تحديث الويدجيت", "Refresh widgets")) {
                mqtt.syncSelectedWidget(force: true)
                checkExtension()
                WidgetCenter.shared.reloadAllTimelines()
                refreshed = true
            }
            if refreshed {
                Text(JL("تم طلب التحديث. إضافة الويدجيت تتم من قائمة الآيفون.", "Refresh requested. Add the widget from the iPhone widget gallery."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text(JL("عند التثبيت بـSideloadly عطّل Remove App Extensions / PlugIns حتى يبقى الويدجيت داخل البرنامج.", "When installing with Sideloadly, disable Remove App Extensions / PlugIns to retain the widget."))
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Label(JL("الويدجيت", "Widgets"), systemImage: "rectangle.3.group")
        }
        .onAppear {
            checkExtension()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func checkExtension() {
        identityMatches = false
        signingMessage = ""
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else {
            extensionPresent = false
            return
        }
        extensionPresent = false
        for url in urls {
            guard url.pathExtension == "appex", let bundle = Bundle(url: url),
                  let point = bundle.infoDictionary?["NSExtension"] as? [String: Any],
                  point["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension",
                  let executable = bundle.executableURL,
                  FileManager.default.fileExists(atPath: executable.path) else { continue }
            extensionPresent = true
            if let parent = Bundle.main.bundleIdentifier, let child = bundle.bundleIdentifier {
                identityMatches = child.hasPrefix(parent + ".")
            }
            let profileURL = url.appendingPathComponent("embedded.mobileprovision")
            if let profile = try? Data(contentsOf: profileURL),
               let start = profile.range(of: Data("<?xml".utf8)),
               let end = profile.range(of: Data("</plist>".utf8)),
               start.lowerBound < end.upperBound,
               let plist = try? PropertyListSerialization.propertyList(from: profile.subdata(in: start.lowerBound..<end.upperBound), format: nil),
               let dictionary = plist as? [String: Any],
               let entitlements = dictionary["Entitlements"] as? [String: Any],
               let allowedID = entitlements["application-identifier"] as? String,
               let child = bundle.bundleIdentifier {
                let provisionedID = allowedID.split(separator: ".").dropFirst().joined(separator: ".")
                let matches = provisionedID == child || (provisionedID.hasSuffix(".*") && child.hasPrefix(String(provisionedID.dropLast()))) || provisionedID == "*"
                signingMessage = matches
                    ? JL("ملف توقيع الويدجيت موجود وهوية التطبيق متوافقة معه. إذا ما ظهر بالقائمة، أعد تشغيل الآيفون وافتح التطبيق ثم ابحث عنه.", "Widget provisioning profile is present and matches its identity. If it is missing from the gallery, restart the iPhone, open JOURNEY, then search again.")
                    : JL("ملف توقيع الويدجيت لا يطابق هويته. أعد التوقيع بـSideloadly مع الاحتفاظ بالإضافات.", "Widget provisioning profile does not match its identity. Re-sign with Sideloadly while retaining extensions.")
            } else {
                signingMessage = JL("لم أتمكن من قراءة ملف توقيع الويدجيت. وجود ملف الإضافة وحده لا يؤكد أن iOS سجّله.", "Unable to read the widget provisioning profile. The extension file alone does not confirm iOS registered it.")
            }
            break
        }
    }
}
