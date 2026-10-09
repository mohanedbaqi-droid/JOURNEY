import SwiftUI
import PhotosUI
import UIKit

enum CustomerDocumentKind: String, Identifiable {
    case annual
    case unified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .annual:
            return pd("السنوية", "Vehicle registration", "سنویەی ئۆتۆمبێل", "Araç ruhsatı", "کارت خودرو")
        case .unified:
            return pd("البطاقة الموحدة", "Unified ID card", "کارتی نیشتمانی", "Ulusal kimlik kartı", "کارت ملی")
        }
    }

    var icon: String {
        self == .annual ? "doc.text.image.fill" : "person.text.rectangle.fill"
    }
}

enum CustomerDocumentStorage {
    private static let rootName = "PunisherCustomerDocuments"

    static func save(_ image: UIImage, vehicleID: UUID, kind: CustomerDocumentKind) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.86) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport
            .appendingPathComponent(rootName, isDirectory: true)
            .appendingPathComponent(vehicleID.uuidString, isDirectory: true)

        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folderURL = folder
        try? folderURL.setResourceValues(values)

        let fileURL = folder.appendingPathComponent(kind.rawValue + ".jpg")
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)

        return rootName + "/" + vehicleID.uuidString + "/" + kind.rawValue + ".jpg"
    }

    static func image(relativePath: String?) -> UIImage? {
        guard let url = resolve(relativePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(relativePath: String?) {
        guard let url = resolve(relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func resolve(_ relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty,
              let appSupport = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
              )
        else { return nil }
        // Refuse parent-directory traversal and paths outside the private docs store.
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == rootName,
              UUID(uuidString: String(parts[1])) != nil,
              parts[2] == "annual.jpg" || parts[2] == "unified.jpg" else { return nil }
        return appSupport
            .appendingPathComponent(rootName, isDirectory: true)
            .appendingPathComponent(String(parts[1]), isDirectory: true)
            .appendingPathComponent(String(parts[2]), isDirectory: false)
    }
}

struct CustomerDocumentsView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @Environment(\.dismiss) private var dismiss

    let vehicle: GarageVehicle

    @State private var customerName: String
    @State private var customerPhone: String
    @State private var annualPath: String?
    @State private var unifiedPath: String?
    @State private var annualPhotoItem: PhotosPickerItem?
    @State private var unifiedPhotoItem: PhotosPickerItem?
    @State private var cameraKind: CustomerDocumentKind?
    @State private var showCamera = false
    @State private var errorText: String?

    init(vehicle: GarageVehicle) {
        self.vehicle = vehicle
        _customerName = State(initialValue: vehicle.customerName ?? "")
        _customerPhone = State(initialValue: vehicle.customerPhone ?? "")
        _annualPath = State(initialValue: vehicle.annualCardDocumentPath)
        _unifiedPath = State(initialValue: vehicle.unifiedIDDocumentPath)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.05, green: 0.01, blue: 0.02), Color(red: 0.0, green: 0.06, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerCard
                    customerCard
                    documentCard(.annual, path: annualPath)
                    documentCard(.unified, path: unifiedPath)
                    privacyCard
                    saveButton
                }
                .padding(16)
            }
        }
        .navigationTitle(pd("معلومات الزبون", "Customer information", "زانیاری کڕیار", "Müşteri bilgileri", "اطلاعات مشتری"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            CameraImagePicker { image in
                guard let kind = cameraKind else { return }
                store(image, for: kind)
                showCamera = false
            }
            .ignoresSafeArea()
        }
        // Separate photo selections prevent saving the ID photo under registration,
        // and allow choosing the same photo again after the selection is reset.
        .onChange(of: annualPhotoItem) { _, item in
            importPhoto(item, for: .annual)
        }
        .onChange(of: unifiedPhotoItem) { _, item in
            importPhoto(item, for: .unified)
        }
        .alert(pd("تعذر حفظ المستمسك", "Could not save document", "پاشەکەوتکردن سەرکەوتوو نەبوو", "Belge kaydedilemedi", "ذخیره مدرک انجام نشد"), isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            PunisherBrandMark(size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.displayName)
                    .font(.headline)
                Text(vehicle.vehiclePlateText.isEmpty ? "—" : vehicle.vehiclePlateText)
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.cyan)
            }
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)))
    }

    private var customerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                pd("بيانات صاحب السيارة", "Vehicle owner", "خاوەنی ئۆتۆمبێل", "Araç sahibi", "مالک خودرو"),
                systemImage: "person.crop.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(.cyan)

            TextField(pd("الاسم الكامل", "Full name", "ناوی تەواو", "Ad soyad", "نام کامل"), text: $customerName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .privateField()

            TextField(pd("رقم الهاتف", "Phone number", "ژمارەی تەلەفۆن", "Telefon numarası", "شماره تلفن"), text: $customerPhone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .privateField()
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.cyan.opacity(0.18)))
    }

    private func documentCard(_ kind: CustomerDocumentKind, path: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(kind.title, systemImage: kind.icon)
                    .font(.headline)
                    .foregroundStyle(kind == .annual ? .red : .cyan)
                Spacer()
                statusBadge(path != nil)
            }

            if let image = CustomerDocumentStorage.image(relativePath: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .blur(radius: 3.5)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.title2)
                            Text(pd("معاينة مخفية لحماية البيانات", "Preview blurred for privacy", "پێشبینین بۆ پاراستن تەمومژاویە", "Gizlilik için önizleme bulanık", "پیش‌نمایش برای حریم خصوصی تار شده"))
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .privacySensitive()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.28))
                    .frame(height: 112)
                    .overlay {
                        VStack(spacing: 7) {
                            Image(systemName: kind.icon)
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text(pd("ماكو مستمسك مضاف", "No document added", "هیچ بەڵگەیەک زیاد نەکراوە", "Belge eklenmedi", "مدرکی اضافه نشده"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            HStack(spacing: 8) {
                Button {
                    cameraKind = kind
                    showCamera = true
                } label: {
                    Label(pd("تصوير", "Camera", "کامێرا", "Kamera", "دوربین"), systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .documentActionButton(tint: .red)

                PhotosPicker(selection: kind == .annual ? $annualPhotoItem : $unifiedPhotoItem, matching: .images) {
                    Label(pd("الصور", "Photos", "وێنەکان", "Fotoğraflar", "تصاویر"), systemImage: "photo.fill")
                        .frame(maxWidth: .infinity)
                }
                .documentActionButton(tint: .cyan)

                if path != nil {
                    Button(role: .destructive) {
                        delete(kind, path: path)
                    } label: {
                        Image(systemName: "trash.fill")
                            .frame(width: 42)
                    }
                    .documentActionButton(tint: .orange)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke((kind == .annual ? Color.red : Color.cyan).opacity(0.18)))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(pd("الخصوصية", "Privacy", "تایبەتمەندی", "Gizlilik", "حریم خصوصی"), systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(pd(
                "المستمسكات تبقى حالياً داخل التطبيق ومحمية بحماية ملفات الجهاز. ما تنرفع لأي سيرفر إلا بعد تهيئة Customer Server والموافقة على الرفع.",
                "Documents currently stay inside the app with device file protection. Nothing is uploaded until Customer Server is configured and upload is approved.",
                "بەڵگەکان ئێستا تەنها ناوخۆی ئەپ دەمێننەوە و پارێزراون. تا Customer Server ڕێک نەخرێت هیچ شتێک بار ناکرێت.",
                "Belgeler şimdilik uygulama içinde cihaz dosya korumasıyla saklanır. Customer Server yapılandırılmadan hiçbir şey yüklenmez.",
                "مدارک فعلاً فقط داخل برنامه و با حفاظت فایل دستگاه نگهداری می‌شوند. تا تنظیم Customer Server چیزی بارگذاری نمی‌شود."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.green.opacity(0.18)))
    }

    private var saveButton: some View {
        Button {
            garage.updateCustomerDocuments(
                vehicle,
                customerName: customerName,
                customerPhone: customerPhone,
                annualCardPath: annualPath,
                unifiedIDPath: unifiedPath
            )
            dismiss()
        } label: {
            Label(pd("حفظ معلومات الزبون", "Save customer information", "پاشەکەوتکردنی زانیاری کڕیار", "Müşteri bilgilerini kaydet", "ذخیره اطلاعات مشتری"), systemImage: "checkmark.shield.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.red, .cyan], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ exists: Bool) -> some View {
        Text(exists ? pd("محفوظ محلياً", "Saved locally", "ناوخۆ پاشەکەوت کرا", "Yerel kaydedildi", "محلی ذخیره شد") : pd("غير مضاف", "Not added", "زیاد نەکراوە", "Eklenmedi", "اضافه نشده"))
            .font(.caption2.bold())
            .foregroundStyle(exists ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((exists ? Color.green : Color.white).opacity(0.08), in: Capsule())
    }

    private func importPhoto(_ item: PhotosPickerItem?, for kind: CustomerDocumentKind) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        errorText = pd("الصورة غير مدعومة", "Unsupported image", "وێنە پشتگیری ناکرێت", "Desteklenmeyen resim", "تصویر پشتیبانی نمی‌شود")
                        resetPhotoSelection(for: kind)
                    }
                    return
                }
                await MainActor.run {
                    store(image, for: kind)
                    resetPhotoSelection(for: kind)
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    resetPhotoSelection(for: kind)
                }
            }
        }
    }

    private func resetPhotoSelection(for kind: CustomerDocumentKind) {
        if kind == .annual {
            annualPhotoItem = nil
        } else {
            unifiedPhotoItem = nil
        }
    }

    private func persistDocumentChanges() {
        garage.updateCustomerDocuments(
            vehicle,
            customerName: customerName,
            customerPhone: customerPhone,
            annualCardPath: annualPath,
            unifiedIDPath: unifiedPath
        )
    }

    private func store(_ image: UIImage, for kind: CustomerDocumentKind) {
        do {
            let relative = try CustomerDocumentStorage.save(image, vehicleID: vehicle.id, kind: kind)
            if kind == .annual {
                annualPath = relative
            } else {
                unifiedPath = relative
            }
            // Save document references immediately so navigation without pressing
            // the details Save button cannot leave a missing/stale document path.
            persistDocumentChanges()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ kind: CustomerDocumentKind, path: String?) {
        CustomerDocumentStorage.delete(relativePath: path)
        if kind == .annual {
            annualPath = nil
        } else {
            unifiedPath = nil
        }
        persistDocumentChanges()
    }
}

private extension View {
    func privateField() -> some View {
        self
            .padding(.horizontal, 13)
            .frame(height: 50)
            .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
            .privacySensitive()
    }

    func documentActionButton(tint: Color) -> some View {
        self
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.vertical, 11)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(tint.opacity(0.20)))
            .buttonStyle(.plain)
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void

        init(onImage: @escaping (UIImage) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
