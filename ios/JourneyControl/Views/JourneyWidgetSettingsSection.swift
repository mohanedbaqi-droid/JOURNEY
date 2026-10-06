import SwiftUI
import WidgetKit

struct JourneyWidgetSettingsSection: View {
    @State private var extensionPresent = false
    @State private var identityMatches = false
    @State private var extensionSafe = false
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
                    ? JL("هوية الويدجيت مرتبطة بالديمو", "Widget identity matches Demo")
                    : JL("هوية الويدجيت تغيّرت أثناء التوقيع؛ أعد توقيع التطبيق والإضافة معاً", "Widget identity changed during signing; re-sign the app and extension together"),
                    systemImage: identityMatches ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(identityMatches ? Color.green : Color.orange)
                Label(extensionSafe
                    ? JL("بناء الويدجيت متوافق مع إضافات الآيفون", "Widget binary is built for app extensions")
                    : JL("بناء الويدجيت يحتاج تحديث", "Widget binary needs an update"),
                    systemImage: extensionSafe ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(extensionSafe ? Color.green : Color.orange)
            }
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
        identityMatches = false
        extensionSafe = false
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
            if let file = try? FileHandle(forReadingFrom: executable) {
                defer { try? file.close() }
                if let header = try? file.read(upToCount: 32), header.count == 32 {
                    // Device builds are a thin, little-endian arm64 Mach-O.
                    let magic = header.prefix(4).elementsEqual([0xcf, 0xfa, 0xed, 0xfe])
                    let flags = UInt32(header[24]) | UInt32(header[25]) << 8
                        | UInt32(header[26]) << 16 | UInt32(header[27]) << 24
                    extensionSafe = magic && flags & 0x02000000 != 0
                }
            }
            break
        }
    }
}
