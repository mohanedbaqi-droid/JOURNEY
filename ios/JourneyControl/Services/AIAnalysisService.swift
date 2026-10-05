import Foundation

/// Read-only assistant. It converts telemetry into explanations and never sends commands.
enum AIAnalysisService {
    static func analyze(_ state: VehicleState) -> [AIInsight] {
        var insights: [AIInsight] = []

        if !state.obdConnected {
            insights.append(.init(
                id: "can-offline",
                severity: .info,
                title: JL("OBD غير متصل", "OBD disconnected"),
                explanation: JL("لا توجد بيانات محرك كافية حتى يكتمل التحليل.", "Not enough engine data to complete the analysis."),
                nextStep: JL("شغّل السويج وتأكد أن قطعة OBD BLE ظاهرة وغير متصلة بتطبيق آخر.", "Turn the ignition on and make sure the BLE OBD adapter is visible and not connected to another app.")
            ))
        } else {
            if state.coolantC >= 110 {
                insights.append(.init(
                    id: "coolant-critical",
                    severity: .critical,
                    title: JL("حرارة سائل التبريد مرتفعة جداً", "Coolant temperature is very high"),
                    explanation: JL("القراءة الحالية \(state.coolantC)°C وتحتاج تحققاً فورياً من القراءة والحالة.", "The current reading is \(state.coolantC)°C. Check the reading and vehicle condition immediately."),
                    nextStep: JL("أوقف الاختبار بأمان وافحص منظومة التبريد وحساس الحرارة يدوياً.", "Stop the test safely and manually inspect the cooling system and temperature sensor.")
                ))
            } else if state.coolantC >= 100 {
                insights.append(.init(
                    id: "coolant-high",
                    severity: .attention,
                    title: JL("حرارة المحرك أعلى من المعتاد", "Engine temperature is above normal"),
                    explanation: JL("القراءة الحالية \(state.coolantC)°C.", "The current reading is \(state.coolantC)°C."),
                    nextStep: JL("راقب تغيّر الحرارة وافحص المراوح ومستوى السائل ضمن إجراءات الورشة.", "Monitor temperature changes and inspect fans and coolant level using workshop procedures.")
                ))
            }

            if state.batteryVoltage > 0 {
                if state.batteryVoltage < 11.2 {
                    insights.append(.init(
                        id: "battery-critical",
                        severity: .critical,
                        title: JL("فولتية البطارية منخفضة جداً", "Battery voltage is very low"),
                        explanation: String(format: JL("القراءة %.1fV وقد تكون البطارية مفرغة أو القياس غير صحيح.", "The reading is %.1fV. The battery may be discharged or the measurement may be incorrect."), state.batteryVoltage),
                        nextStep: JL("أكد القراءة بملتيميتر وافحص البطارية والتوصيلات.", "Verify with a multimeter and inspect the battery and connections.")
                    ))
                } else if !state.simulatedEngineRunning && state.batteryVoltage < 11.8 {
                    insights.append(.init(
                        id: "battery-low",
                        severity: .attention,
                        title: JL("فولتية البطارية منخفضة", "Battery voltage is low"),
                        explanation: String(format: JL("القراءة %.1fV والمحرك متوقف.", "The reading is %.1fV with the engine stopped."), state.batteryVoltage),
                        nextStep: JL("نفّذ اختبار بطارية وشحن قبل الاعتماد على الاستنتاج.", "Test the battery and charging system before drawing conclusions.")
                    ))
                } else if state.simulatedEngineRunning && state.batteryVoltage < 13.2 {
                    insights.append(.init(
                        id: "charging-low",
                        severity: .attention,
                        title: JL("فولتية الشحن تحتاج تحقق", "Charging voltage needs verification"),
                        explanation: String(format: JL("القراءة %.1fV مع حالة تشغيل ظاهرة.", "The reading is %.1fV while the engine appears to be running."), state.batteryVoltage),
                        nextStep: JL("أكد حالة المحرك وقس خرج الشحن بأداة مستقلة.", "Verify engine status and measure charging output independently.")
                    ))
                }
            }

            if !state.diagnosticCodes.isEmpty {
                insights.append(.init(
                    id: "dtc-present",
                    severity: .attention,
                    title: JL("أكواد أعطال مسجلة", "Stored diagnostic trouble codes"),
                    explanation: JL("تمت قراءة \(state.diagnosticCodes.count) كود: \(state.diagnosticCodes.joined(separator: ", ")).", "Read \(state.diagnosticCodes.count) codes: \(state.diagnosticCodes.joined(separator: ", "))."),
                    nextStep: JL("افتح تقرير الأكواد وافحص السبب؛ المساعد لا يمسح الأكواد ولا يرسل أوامر للسيارة.", "Open the code report and inspect the cause. The assistant does not clear codes or send vehicle commands.")
                ))
            }
        }

        if !state.gpsValid {
            insights.append(.init(
                id: "gps-no-fix",
                severity: .info,
                title: JL("لا يوجد تثبيت GPS", "No GPS fix"),
                explanation: JL("التعقب لا يملك موقعاً صالحاً حالياً.", "Tracking does not currently have a valid position."),
                nextStep: JL("اختبر الهوائي بمكان مفتوح وراجع زمن آخر تحديث.", "Test the antenna outdoors and check the last update time.")
            ))
        }

        if insights.isEmpty {
            insights.append(.init(
                id: "normal",
                severity: .info,
                title: JL("لا توجد ملاحظة واضحة", "No clear issue detected"),
                explanation: JL("القراءات المتاحة لا تُظهر حالة تتجاوز حدود التنبيه المحافظة.", "Available readings do not exceed the conservative alert thresholds."),
                nextStep: JL("استمر بجمع البيانات وقارنها بالفحص اليدوي؛ هذا ليس تشخيصاً نهائياً.", "Continue collecting data and compare it with manual inspection. This is not a final diagnosis.")
            ))
        }

        return insights.sorted { $0.severity > $1.severity }
    }
}
