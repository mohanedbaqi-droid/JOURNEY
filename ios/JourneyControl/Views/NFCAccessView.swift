import SwiftUI

struct NFCAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NFCCredentialStore
    @State private var showingAddCredential = false
    @State private var editingCredential: NFCCredential?

    let onTestIPhoneTap: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                iphoneSection
                credentialsSection
                safetySection
                recentEventsSection
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.05, blue: 0.10),
                        Color(red: 0.03, green: 0.10, blue: 0.15),
                        .black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("مفاتيح NFC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("تم") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddCredential = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCredential) {
                AddNFCCredentialView()
                    .environmentObject(store)
                    .preferredColorScheme(.dark)
            }
            .sheet(item: $editingCredential) { credential in
                EditNFCCredentialView(credential: credential)
                    .environmentObject(store)
                    .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.cyan)
    }

    private var iphoneSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 13) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.title2.bold())
                        .foregroundStyle(.cyan)
                        .frame(width: 48, height: 48)
                        .background(.cyan.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("مفتاح iPhone").font(.headline)
                        Text("NFC Tag يفتح التطبيق، ثم Face ID وBLE")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("أساسي")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.12), in: Capsule())
                }

                Divider()

                Label(store.settings.iphoneActionTitle, systemImage: "lock.open.fill")
                    .font(.subheadline.weight(.semibold))

                Label("Face ID إلزامي قبل تنفيذ أي طلب", systemImage: "faceid")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onTestIPhoneTap) {
                    Label("اختبار تمرير الآيفون", systemImage: "wave.3.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 6)
        } header: {
            Text("الآيفون")
        } footer: {
            Text("التاغ لا يحمل أمراً أو مفتاحاً سرياً. للاختبار أنشئ Automation في Shortcuts يفتح journeycontrol://nfc عند تمرير الآيفون.")
        }
    }

    private var credentialsSection: some View {
        Section {
            if store.credentials.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "key.radiowaves.forward.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.cyan)
                    Text("ماكو بطاقات مضافة").font(.headline)
                    Text("حالياً الإضافة تجريبية. التسجيل الحقيقي يتفعل بعد ربط PN532 بالـESP.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("إضافة بطاقة فحص") { showingAddCredential = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ForEach(store.credentials) { credential in
                    HStack(spacing: 12) {
                        Image(systemName: credential.kind.symbol)
                            .foregroundStyle(credential.isEnabled ? .cyan : .secondary)
                            .frame(width: 28)

                        Button {
                            editingCredential = credential
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(credential.name)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(credential.maskedIdentifier)
                                        .font(.caption.monospaced())
                                    if credential.isBenchCredential {
                                        Text("فحص")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Toggle("", isOn: Binding(
                            get: { credential.isEnabled },
                            set: { store.setEnabled($0, for: credential.id) }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(credential)
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("البطاقات والمفاتيح")
                Spacer()
                Text("\(store.enabledCredentialCount) مفعّل")
            }
        }
    }

    private var safetySection: some View {
        Section("الحماية") {
            LabeledContent {
                Text("إجباري").foregroundStyle(.green)
            } label: {
                Label("Face ID للآيفون", systemImage: "faceid")
            }

            Stepper(
                value: Binding(
                    get: { store.settings.repeatGuardSeconds },
                    set: { newValue in
                        var updated = store.settings
                        updated.repeatGuardSeconds = newValue
                        store.settings = updated
                    }
                ),
                in: 3...15
            ) {
                LabeledContent("منع القراءة المكررة") {
                    Text("\(store.settings.repeatGuardSeconds) ثوانٍ")
                        .monospacedDigit()
                }
            }

            Label("لا يوجد أمر إطفاء ضمن مسار NFC", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)
        }
    }

    private var recentEventsSection: some View {
        Section("آخر النشاطات") {
            if store.events.isEmpty {
                Text("ماكو نشاط مسجل بعد")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.events.prefix(6)) { event in
                    HStack(spacing: 10) {
                        Image(systemName: eventSymbol(event.result))
                            .foregroundStyle(eventColor(event.result))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline)
                            Text(event.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(event.timestamp, style: .time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func eventSymbol(_ result: NFCAccessEvent.Result) -> String {
        switch result {
        case .allowed: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .bench: return "hammer.circle.fill"
        }
    }

    private func eventColor(_ result: NFCAccessEvent.Result) -> Color {
        switch result {
        case .allowed: return .green
        case .denied: return .red
        case .bench: return .orange
        }
    }
}

private struct AddNFCCredentialView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NFCCredentialStore
    @State private var name = ""
    @State private var kind: NFCCredentialKind = .physicalCard
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("المفتاح") {
                    TextField("مثال: بطاقة أبو سيف", text: $name)
                    Picker("النوع", selection: $kind) {
                        ForEach(NFCCredentialKind.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                }

                Section {
                    Label("هذه إضافة فحص محلية فقط، وما ترسل أمراً إلى السيارة.", systemImage: "hammer.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Text("عند وصول PN532 نستبدل المعرّف التجريبي بالمعرّف الذي يرجعه ESP بعد التحقق من البطاقة.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("إضافة مفتاح NFC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") {
                        if let error = store.addBenchCredential(name: name, kind: kind) {
                            errorText = error
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

private struct EditNFCCredentialView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NFCCredentialStore
    @State private var draft: NFCCredential

    init(credential: NFCCredential) {
        _draft = State(initialValue: credential)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("معلومات المفتاح") {
                    TextField("الاسم", text: $draft.name)
                    LabeledContent("النوع", value: draft.kind.title)
                    LabeledContent("المعرّف", value: draft.maskedIdentifier)
                }

                Section("الصلاحيات") {
                    Toggle("المفتاح مفعّل", isOn: $draft.isEnabled)
                    Toggle("يسمح بالتشغيل عن بُعد", isOn: $draft.allowsRemoteStart)
                }

                Section {
                    Label("إلغاء الإطفاء والقفل بالتمرير الثاني حسب الاتفاق الحالي.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("تعديل المفتاح")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !draft.name.isEmpty else { return }
                        store.update(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}
