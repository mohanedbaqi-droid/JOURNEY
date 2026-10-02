import Foundation

/// Read-only assistant. It converts telemetry into explanations and never sends commands.
enum AIAnalysisService {
    static func analyze(_ state: VehicleState) -> [AIInsight] {
        var insights: [AIInsight] = []

        if !state.obdConnected {
            insights.append(.init(
                id: "can-offline",
                severity: .info,
                title: "OBD غير متصل",
                explanation: "لا توجد بيانات محرك كافية حتى يكتمل التحليل.",
                nextStep: "شغّل السويج وتأكد أن قطعة OBD BLE ظاهرة وغير متصلة بتطبيق آخر."
            ))
        } else {
            if state.coolantC >= 110 {
                insights.append(.init(
                    id: "coolant-critical",
                    severity: .critical,
                    title: "حرارة سائل التبريد مرتفعة جداً",
                    explanation: "القراءة الحالية \(state.coolantC)°C وتحتاج تحققاً فورياً من القراءة والحالة.",
                    nextStep: "أوقف الاختبار بأمان وافحص منظومة التبريد وحساس الحرارة يدوياً."
                ))
            } else if state.coolantC >= 100 {
                insights.append(.init(
                    id: "coolant-high",
                    severity: .attention,
                    title: "حرارة المحرك أعلى من المعتاد",
                    explanation: "القراءة الحالية \(state.coolantC)°C.",
                    nextStep: "راقب تغيّر الحرارة وافحص المراوح ومستوى السائل ضمن إجراءات الورشة."
                ))
            }

            if state.batteryVoltage > 0 {
                if state.batteryVoltage < 11.2 {
                    insights.append(.init(
                        id: "battery-critical",
                        severity: .critical,
                        title: "فولتية البطارية منخفضة جداً",
                        explanation: String(format: "القراءة %.1fV وقد تكون البطارية مفرغة أو القياس غير صحيح.", state.batteryVoltage),
                        nextStep: "أكد القراءة بملتيميتر وافحص البطارية والتوصيلات."
                    ))
                } else if !state.simulatedEngineRunning && state.batteryVoltage < 11.8 {
                    insights.append(.init(
                        id: "battery-low",
                        severity: .attention,
                        title: "فولتية البطارية منخفضة",
                        explanation: String(format: "القراءة %.1fV والمحرك متوقف.", state.batteryVoltage),
                        nextStep: "نفّذ اختبار بطارية وشحن قبل الاعتماد على الاستنتاج."
                    ))
                } else if state.simulatedEngineRunning && state.batteryVoltage < 13.2 {
                    insights.append(.init(
                        id: "charging-low",
                        severity: .attention,
                        title: "فولتية الشحن تحتاج تحقق",
                        explanation: String(format: "القراءة %.1fV مع حالة تشغيل ظاهرة.", state.batteryVoltage),
                        nextStep: "أكد حالة المحرك وقس خرج الشحن بأداة مستقلة."
                    ))
                }
            }

            if !state.diagnosticCodes.isEmpty {
                insights.append(.init(
                    id: "dtc-present",
                    severity: .attention,
                    title: "أكواد أعطال مسجلة",
                    explanation: "تمت قراءة \(state.diagnosticCodes.count) كود: \(state.diagnosticCodes.joined(separator: ", ")).",
                    nextStep: "افتح تقرير الأكواد وافحص السبب؛ المساعد لا يمسح الأكواد ولا يرسل أوامر للسيارة."
                ))
            }
        }

        if !state.gpsValid {
            insights.append(.init(
                id: "gps-no-fix",
                severity: .info,
                title: "لا يوجد تثبيت GPS",
                explanation: "التعقب لا يملك موقعاً صالحاً حالياً.",
                nextStep: "اختبر الهوائي بمكان مفتوح وراجع زمن آخر تحديث."
            ))
        }

        if insights.isEmpty {
            insights.append(.init(
                id: "normal",
                severity: .info,
                title: "لا توجد ملاحظة واضحة",
                explanation: "القراءات المتاحة لا تُظهر حالة تتجاوز حدود التنبيه المحافظة.",
                nextStep: "استمر بجمع البيانات وقارنها بالفحص اليدوي؛ هذا ليس تشخيصاً نهائياً."
            ))
        }

        return insights.sorted { $0.severity > $1.severity }
    }
}
