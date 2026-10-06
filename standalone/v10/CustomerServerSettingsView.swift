import SwiftUI

struct CustomerServerSettingsView: View {
    @AppStorage("punisher.customerServer.baseURL") private var baseURL = ""
    @AppStorage("punisher.customerServer.project") private var project = ""

    private var isConfigured: Bool {
        guard let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased()
        else { return false }
        return scheme == "https"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.04, green: 0.01, blue: 0.02), Color(red: 0.0, green: 0.05, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.title)
                            .foregroundStyle(.cyan)
                            .frame(width: 56, height: 56)
                            .background(.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Customer Server")
                                .font(.title2.bold())
                            Text(pd(
                                "سيرفر خاص ببيانات الزبائن والمستمسكات",
                                "Private server for customer data and documents",
                                "سێرڤەری تایبەت بۆ زانیاری و بەڵگەی کڕیار",
                                "Müşteri verileri ve belgeleri için özel sunucu",
                                "سرور خصوصی برای اطلاعات و مدارک مشتری"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("HTTPS Base URL")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("https://customers.example.com", text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(.horizontal, 13)
                            .frame(height: 50)
                            .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))

                        Text(pd("اسم المشروع / الفرع", "Project / branch name", "ناوی پڕۆژە / لق", "Proje / şube adı", "نام پروژه / شعبه"))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Punisher Customers", text: $project)
                            .padding(.horizontal, 13)
                            .frame(height: 50)
                            .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
                    }
                    .padding(14)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))

                    HStack(spacing: 10) {
                        Image(systemName: isConfigured ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(isConfigured ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isConfigured
                                ? pd("عنوان HTTPS جاهز", "HTTPS endpoint ready", "ناونیشانی HTTPS ئامادەیە", "HTTPS adresi hazır", "آدرس HTTPS آماده است")
                                : pd("السيرفر غير مهيأ بعد", "Server not configured yet", "سێرڤەر هێشتا ڕێک نەخراوە", "Sunucu henüz yapılandırılmadı", "سرور هنوز تنظیم نشده"))
                                .font(.subheadline.bold())
                            Text(pd(
                                "الرفع يبقى متوقف لحد ما نحدد API وطريقة تسجيل الدخول. مفاتيح الدخول راح تنخزن بالـKeychain مو بالإعدادات.",
                                "Uploads stay disabled until the API and authentication method are defined. Credentials will be stored in Keychain, not settings.",
                                "بارکردن ناچالاک دەمێنێتەوە تا API و شێوازی چوونەژوورەوە دیاری بکرێت. کلیلەکان لە Keychain پارێزراو دەبن.",
                                "API ve kimlik doğrulama belirlenene kadar yükleme kapalı kalır. Kimlik bilgileri ayarlarda değil Keychain'de tutulur.",
                                "بارگذاری تا تعیین API و روش احراز هویت غیرفعال می‌ماند. اطلاعات ورود در Keychain نگهداری خواهد شد."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background((isConfigured ? Color.green : Color.orange).opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke((isConfigured ? Color.green : Color.orange).opacity(0.20)))
                }
                .padding(16)
            }
        }
        .navigationTitle("Customer Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}
