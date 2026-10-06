import SwiftUI

struct AboutView: View {
    private let phone = "07811119127"
    private let instagram = "h0k38"
    private let telegram = "ma_o_92"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.02, blue: 0.025), Color(red: 0.01, green: 0.055, blue: 0.075)],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        PunisherBrandMark(size: 126)
                            .padding(.top, 8)

                        Text("PUNISHER DRIVE")
                            .font(.system(size: 27, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(
                                LinearGradient(colors: [.red, .white, .cyan], startPoint: .leading, endPoint: .trailing)
                            )

                        Text("بونيشير كار")
                            .font(.title3.bold())
                            .foregroundStyle(.red)

                        Text("تحكم كامل بسيارتك")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cyan.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 26))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(
                        LinearGradient(colors: [.red.opacity(0.7), .cyan.opacity(0.6)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1
                    ))

                    aboutRow(icon: "person.crop.circle.fill", title: "المطور", value: "مهند الربيعي", tint: .red)
                    aboutRow(icon: "building.2.crop.circle.fill", title: "الجهة", value: "مركز بونيشير للسيارات", tint: .cyan)

                    Link(destination: URL(string: "tel:\(phone)")!) {
                        aboutRow(icon: "phone.fill", title: "الهاتف / واتساب", value: phone, tint: .green)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://instagram.com/\(instagram)")!) {
                        aboutRow(icon: "camera.fill", title: "إنستغرام", value: instagram, tint: .pink)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://t.me/\(telegram)")!) {
                        aboutRow(icon: "paperplane.fill", title: "تيليغرام", value: telegram, tint: .cyan)
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 0) {
                        aboutRow(icon: "shippingbox.fill", title: "إصدار التطبيق", value: appVersion, tint: .cyan)
                        Divider().overlay(.white.opacity(0.08)).padding(.horizontal, 14)
                        aboutRow(icon: "cpu.fill", title: "تحديث ESP", value: "v1.0.4", tint: .red)
                    }
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08)))

                    Text("Punisher Drive • Smart Vehicle Control")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 26)
            }
        }
        .navigationTitle("حول التطبيق")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.92), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "7"
        return "\(version) (Build \(build))"
    }

    private func aboutRow(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(LinearGradient(colors: [tint.opacity(0.30), .white.opacity(0.04)], startPoint: .leading, endPoint: .trailing))
        )
    }
}
