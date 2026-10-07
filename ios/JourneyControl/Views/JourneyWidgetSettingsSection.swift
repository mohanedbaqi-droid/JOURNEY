import SwiftUI
import WidgetKit

struct JourneyWidgetSettingsSection: View {
    @EnvironmentObject private var mqtt: MQTTService
    @State private var extensionPresent = false
    @State private var identityMatches = false
    @State private var signingMessage = ""
    @State private var refreshed = false

    var body: some View {
        Section {
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
            Label(JourneyWidgetStore.available ? JL("مشاركة بيانات الويدجيت متاحة", "Widget data sharing available") : JL("مشاركة بيانات الويدجيت غير متاحة بالتوقيع الحالي", "Widget data sharing unavailable with this signing profile"), systemImage: JourneyWidgetStore.available ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(JourneyWidgetStore.available ? Color.green : Color.orange)
            if !JourneyWidgetStore.available {
                Text(JL("وقّع التطبيق والويدجيت مع مجموعة App Group المشتركة حتى تظهر القراءات. احتفظ بالإضافات عند التثبيت.", "Sign the app and widget with their shared App Group to display readings. Keep app extensions when installing.")).font(.footnote)
            }
            Text(JL("الفتح والقفل من الويدجيت بالخلفية. التشغيل يفتح تأكيد Face ID؛ الإلغاء لا يرسل أمراً.", "Widget lock and unlock run in the background. Start opens Face ID authorization; cancelling sends no command.")).font(.footnote)
            Text(JL("الويدجيت الكبير يعرض كل القراءات المتاحة ووقت آخر تحديث. توقيت التحديث بالخلفية يحدده iOS.", "The large widget shows all available readings and the last update time. iOS schedules background widget refreshes.")).font(.footnote)
            Text(JL("ابحث عن JOURNEY بقائمة ويدجيت الشاشة الرئيسية أو شاشة القفل.", "Look for JOURNEY in the Home Screen or Lock Screen widget gallery."))
                .font(.footnote)
            Button(JL("تحديث الويدجيت", "Refresh widgets")) {
                checkExtension()
                mqtt.syncSelectedWidget(force: true)
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
