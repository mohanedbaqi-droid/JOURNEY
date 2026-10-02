import SwiftUI
import WidgetKit

private struct JourneyWidgetEntry: TimelineEntry {
    let date: Date
}

private struct JourneyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> JourneyWidgetEntry {
        JourneyWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (JourneyWidgetEntry) -> Void) {
        completion(JourneyWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JourneyWidgetEntry>) -> Void) {
        let entry = JourneyWidgetEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

private struct JourneyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JourneyWidgetEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                smallWidget
            } else {
                mediumWidget
            }
        }
        .journeyWidgetBackground { widgetBackground }
        .widgetURL(URL(string: "journeycontrol://widget/open"))
    }

    private var smallWidget: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("JOURNEY")
                        .font(.caption.bold())
                        .tracking(1.2)
                    Text("افتح للتحديث")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Circle()
                    .fill(.gray)
                    .frame(width: 7, height: 7)
                    .shadow(color: .gray, radius: 3)
            }

            JourneyWidgetCar()
                .frame(height: 76)

            HStack {
                Label("ESP", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                Text("—")
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.cyan)
        }
        .padding(13)
    }

    private var mediumWidget: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("JOURNEY")
                    .font(.headline.bold())
                    .tracking(1.5)
                Text("السيارة المختارة")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.52))

                Spacer(minLength: 2)

                Label("افتح للتحديث", systemImage: "arrow.clockwise")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                HStack(spacing: 10) {
                    metric("—", "km/h")
                    metric("—", "حرارة")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            JourneyWidgetCar()
                .frame(width: 76, height: 126)

            VStack(spacing: 9) {
                actionLink("lock.fill", path: "lock", tint: .blue)
                actionLink("lock.open.fill", path: "unlock", tint: .green)
                actionLink("power", path: "start", tint: .orange)
            }
        }
        .padding(15)
    }

    private func metric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.bold()).monospacedDigit()
            Text(title).font(.system(size: 8)).foregroundStyle(.white.opacity(0.42))
        }
    }

    private func actionLink(_ icon: String, path: String, tint: Color) -> some View {
        Link(destination: URL(string: "journeycontrol://widget/\(path)")!) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(tint)
                .frame(width: 34, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var widgetBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.02, green: 0.06, blue: 0.11), Color(red: 0.03, green: 0.15, blue: 0.20), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Circle()
                .fill(.cyan.opacity(0.13))
                .frame(width: 160)
                .blur(radius: 35)
                .offset(x: 50, y: -30)
        )
    }
}

private struct JourneyWidgetCar: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(.cyan.opacity(0.14))
                .frame(width: 80, height: 118)
                .blur(radius: 12)

            VStack(spacing: 42) {
                wheelPair
                wheelPair
            }

            JourneyWidgetBody()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(white: 0.72), .white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 58, height: 111)
                .overlay(JourneyWidgetBody().stroke(.white.opacity(0.7), lineWidth: 0.7))
                .shadow(color: .cyan.opacity(0.22), radius: 8)

            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(windowGradient)
                    .frame(width: 41, height: 21)
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.74))
                    .frame(width: 39, height: 35)
                RoundedRectangle(cornerRadius: 6)
                    .fill(windowGradient)
                    .frame(width: 39, height: 16)
            }

            VStack(spacing: 88) {
                HStack(spacing: 28) { lamp(.white); lamp(.white) }
                HStack(spacing: 29) { lamp(.red); lamp(.red) }
            }
        }
    }

    private var wheelPair: some View {
        HStack(spacing: 52) {
            Capsule().fill(.black).frame(width: 7, height: 20)
            Capsule().fill(.black).frame(width: 7, height: 20)
        }
    }

    private var windowGradient: LinearGradient {
        LinearGradient(colors: [.cyan.opacity(0.35), .black.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func lamp(_ color: Color) -> some View {
        Capsule().fill(color).frame(width: 11, height: 3).shadow(color: color, radius: 3)
    }
}

private struct JourneyWidgetBody: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX - 14, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 2, y: rect.minY + 22), control: CGPoint(x: rect.minX + 7, y: rect.minY + 5))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 17))
            path.addQuadCurve(to: CGPoint(x: rect.midX - 13, y: rect.maxY), control: CGPoint(x: rect.minX + 6, y: rect.maxY - 2))
            path.addQuadCurve(to: CGPoint(x: rect.midX + 13, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY + 2))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - 17), control: CGPoint(x: rect.maxX - 6, y: rect.maxY - 2))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 22))
            path.addQuadCurve(to: CGPoint(x: rect.midX + 14, y: rect.minY), control: CGPoint(x: rect.maxX - 7, y: rect.minY + 5))
            path.closeSubpath()
        }
    }
}

struct JourneyHomeWidget: Widget {
    let kind = "JourneyHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JourneyWidgetProvider()) { entry in
            JourneyWidgetView(entry: entry)
        }
        .configurationDisplayName("JOURNEY")
        .description("حالة سيارة العرض واختصارات الفحص الآمن.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct JourneyWidgetBundle: WidgetBundle {
    var body: some Widget {
        JourneyHomeWidget()
    }
}

private extension View {
    @ViewBuilder
    func journeyWidgetBackground<Background: View>(
        @ViewBuilder _ background: () -> Background
    ) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget, content: background)
        } else {
            self.background(background())
        }
    }
}
