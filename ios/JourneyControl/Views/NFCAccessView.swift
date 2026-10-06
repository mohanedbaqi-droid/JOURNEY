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
            .background { JourneyWallpaperView() }
            .navigationTitle(JL("مفاتيح NFC", "NFC keys"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(JL("تم", "Done")) { dismiss() }
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
            }
            .sheet(item: $editingCredential) { credential in
                EditNFCCredentialView(credential: credential)
                    .environmentObject(store)
            }
        }
        .tint(JourneyTheme.accent)
    }

    private var iphoneSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 13) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.title2.bold())
                        .foregroundStyle(JourneyTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(.cyan.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(JL("مفتاح iPhone", "iPhone key")).font(.headline)
                        Text(JL("NFC Tag يفتح التطبيق، ثم Face ID وBLE", "NFC tag opens the app, then Face ID and BLE"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(JL("أساسي", "Primary"))
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.12), in: Capsule())
                }

                Divider()

                Label(store.settings.iphoneActionTitle, systemImage: "lock.open.fill")
                    .font(.subheadline.weight(.semibold))

                Label(JL("Face ID إلزامي قبل تنفيذ أي طلب", "Face ID is required before every request"), systemImage: "faceid")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onTestIPhoneTap) {
                    Label(JL("اختبار تمرير الآيفون", "Test iPhone tap"), systemImage: "wave.3.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 6)
        } header: {
            Text(JL("الآيفون", "iPhone"))
        } footer: {
            Text(JL("التاغ لا يحمل أمراً أو مفتاحاً سرياً. للاختبار أنشئ Automation في Shortcuts يفتح journey-demo://nfc عند تمرير الآيفون.", "The tag contains no command or secret key. For testing, create a Shortcuts automation that opens journey-demo://nfc when you tap the iPhone."))
        }
    }

    private var credentialsSection: some View {
        Section {
            if store.credentials.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "key.radiowaves.forward.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(JourneyTheme.accent)
                    Text(JL("ماكو بطاقات مضافة", "No cards added")).font(.headline)
                    Text(JL("حالياً الإضافة تجريبية. التسجيل الحقيقي يتفعل بعد ربط PN532 بالـESP.", "Adding cards is currently a test. Real enrollment requires PN532 connected to ESP."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(JL("إضافة بطاقة فحص", "Add test card")) { showingAddCredential = true }
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
                                        Text(JL("فحص", "Test"))
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
                            Label(JL("حذف", "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text(JL("البطاقات والمفاتيح", "Cards and keys"))
                Spacer()
                Text(JL("\(store.enabledCredentialCount) مفعّل", "\(store.enabledCredentialCount) enabled"))
            }
        }
    }

    private var safetySection: some View {
        Section(JL("الحماية", "Security")) {
            LabeledContent {
                Text(JL("إجباري", "Required")).foregroundStyle(.green)
            } label: {
                Label(JL("Face ID للآيفون", "iPhone Face ID"), systemImage: "faceid")
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
                LabeledContent(JL("منع القراءة المكررة", "Prevent repeated reads")) {
                    Text(JL("\(store.settings.repeatGuardSeconds) ثوانٍ", "\(store.settings.repeatGuardSeconds) seconds"))
                        .monospacedDigit()
                }
            }

            Label(JL("لا يوجد أمر إطفاء ضمن مسار NFC", "NFC does not send an engine stop command"), systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)
        }
    }

    private var recentEventsSection: some View {
        Section(JL("آخر النشاطات", "Recent activity")) {
            if store.events.isEmpty {
                Text(JL("ماكو نشاط مسجل بعد", "No activity yet"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.events.prefix(6)) { event in
                    HStack(spacing: 10) {
                        Image(systemName: eventSymbol(event.result))
                            .foregroundStyle(eventColor(event.result))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(JLStored(event.title)).font(.subheadline)
                            Text(JLStored(event.detail)).font(.caption).foregroundStyle(.secondary)
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
                Section(JL("المفتاح", "Key")) {
                    TextField(JL("مثال: بطاقة أبو سيف", "Example: Abu Saif's card"), text: $name)
                    Picker(JL("النوع", "Type"), selection: $kind) {
                        ForEach(NFCCredentialKind.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                }

                Section {
                    Label(JL("هذه إضافة فحص محلية فقط، وما ترسل أمراً إلى السيارة.", "This is a local test only. It sends no vehicle command."), systemImage: "hammer.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Text(JL("عند وصول PN532 نستبدل المعرّف التجريبي بالمعرّف الذي يرجعه ESP بعد التحقق من البطاقة.", "When PN532 is connected, the test ID will be replaced by the ID returned by ESP after card verification."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorText {
                    Section { Text(JLStored(errorText)).foregroundStyle(.red) }
                }
            }
            .navigationTitle(JL("إضافة مفتاح NFC", "Add NFC key"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(JL("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(JL("إضافة", "Add")) {
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
                Section(JL("معلومات المفتاح", "Key details")) {
                    TextField(JL("الاسم", "Name"), text: $draft.name)
                    LabeledContent(JL("النوع", "Type"), value: draft.kind.title)
                    LabeledContent(JL("المعرّف", "ID"), value: draft.maskedIdentifier)
                }

                Section(JL("الصلاحيات", "Permissions")) {
                    Toggle(JL("المفتاح مفعّل", "Key enabled"), isOn: $draft.isEnabled)
                    Toggle(JL("يسمح بالتشغيل عن بُعد", "Allow remote start"), isOn: $draft.allowsRemoteStart)
                }

                Section {
                    Label(JL("إلغاء الإطفاء والقفل بالتمرير الثاني حسب الاتفاق الحالي.", "Second-tap shutdown and locking are disabled in the current configuration."), systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(JL("تعديل المفتاح", "Edit key"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(JL("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(JL("حفظ", "Save")) {
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
