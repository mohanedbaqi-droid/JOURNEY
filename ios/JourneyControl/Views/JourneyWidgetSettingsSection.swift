import SwiftUI
import WidgetKit

struct JourneyWidgetSettingsSection: View {
    @State private var extensionPresent = false
    @State private var refreshed = false

    var body: some View {
        Section {
            Label(extensionPresent
                ? JL("ملف الويدجيت مثبت", "Widget extension is installed")
                : JL("ملف الويدجيت غير موجود بالتثبيت", "Widget extension is missing from this installation"),
                systemImage: extensionPresent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(extensionPresent ? Color.green : Color.orange)
            Text(JL("ابحث عن JOURNEY DEMO بقائمة ويدجيت الشاشة الرئيسية أو شاشة القفل.", "Look for JOURNEY DEMO in the Home Screen or Lock Screen widget gallery."))
                .font(.footnote)
            Button(JL("تحديث الويدجيت", "Refresh widgets")) {
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
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else {
            extensionPresent = false
            return
        }
        extensionPresent = urls.contains { url in
            guard url.pathExtension == "appex", let bundle = Bundle(url: url),
                  let point = bundle.infoDictionary?["NSExtension"] as? [String: Any] else { return false }
            return point["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
                && bundle.executableURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
    }
}
