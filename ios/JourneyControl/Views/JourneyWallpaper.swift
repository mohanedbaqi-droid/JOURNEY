import SwiftUI
import PhotosUI
import UIKit
import ImageIO

@MainActor
final class JourneyWallpaperStore: ObservableObject {
    static let shared = JourneyWallpaperStore()
    @Published private(set) var image: UIImage?

    private static var photoURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JourneyWallpaper", isDirectory: true)
            .appendingPathComponent("background.jpg")
    }

    private init() {
        image = UIImage(contentsOfFile: Self.photoURL.path)
    }

    func savePhoto(_ data: Data) async throws {
        // Bound memory and disk use even when the selected photo is very large.
        let jpeg = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary),
                  let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return jpeg
        }.value
        try Task.checkCancellation()
        guard let decoded = UIImage(data: jpeg) else { throw CocoaError(.fileReadCorruptFile) }
        let url = Self.photoURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: url, options: .atomic)
        image = decoded
    }
}

struct JourneyWallpaperView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = JourneyWallpaperStore.shared
    @AppStorage("journey.settings.wallpaper") private var wallpaper = "original"
    @AppStorage("journey.settings.wallpaperDim") private var dim = 0.45

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if wallpaper == "photo", let image = store.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    if colorScheme == .light {
                        Color.white.opacity(min(0.85, max(0, dim)))
                    } else {
                        Color.black.opacity(min(0.85, max(0, dim)))
                    }
                } else if wallpaper == "black" {
                    JourneyTheme.surface
                } else {
                    LinearGradient(
                        colors: colorScheme == .light
                            ? [Color(red: 0.92, green: 0.97, blue: 1), .white, Color(red: 0.86, green: 0.93, blue: 0.97)]
                            : wallpaper == "blue"
                            ? [Color(red: 0.01, green: 0.15, blue: 0.26), Color(red: 0.01, green: 0.04, blue: 0.09), .black]
                            : [Color(red: 0.02, green: 0.05, blue: 0.10), Color(red: 0.04, green: 0.11, blue: 0.17), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle().fill(.cyan.opacity(0.09)).frame(width: 360)
                        .blur(radius: 70).offset(x: 130, y: -290)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct JourneyWallpaperSettingsSection: View {
    @ObservedObject private var store = JourneyWallpaperStore.shared
    @AppStorage("journey.settings.wallpaper") private var wallpaper = "original"
    @AppStorage("journey.settings.wallpaperDim") private var dim = 0.45
    @State private var selection: PhotosPickerItem?
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        Section {
            Picker(JL("خلفية الشاشة", "Screen background"), selection: $wallpaper) {
                Text(JL("الأصلية", "Original")).tag("original")
                Text(JL("لون سادة", "Solid color")).tag("black")
                Text(JL("أزرق", "Blue")).tag("blue")
                if store.image != nil {
                    Text(JL("صورتي", "My photo")).tag("photo")
                }
            }

            PhotosPicker(selection: $selection, matching: .images) {
                Label(JL("اختيار صورة من الألبوم", "Choose a photo"), systemImage: "photo.on.rectangle")
            }
            .disabled(loading)

            if loading {
                ProgressView(JL("جاري تجهيز الخلفية…", "Preparing background…"))
            }
            if wallpaper == "photo", store.image != nil {
                VStack(alignment: .leading) {
                    Text(JL("تعتيم الخلفية", "Background dimming"))
                    Slider(value: $dim, in: 0...0.85)
                        .accessibilityLabel(JL("تعتيم الخلفية", "Background dimming"))
                }
            }
            JourneyWallpaperView()
                .frame(height: 145)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(JL("استعادة الخلفية الأصلية", "Restore original background")) {
                wallpaper = "original"
                dim = 0.45
            }
        } header: {
            Label(JL("خلفية الشاشة", "Screen background"), systemImage: "photo")
        } footer: {
            Text(JL("تُحفظ الخلفية على جهازك. عدّل التعتيم حتى تبقى الأزرار والقراءات واضحة.", "The background is saved on your device. Adjust dimming to keep controls and readings clear."))
        }
        .task(id: selection) {
            guard let selection else { return }
            loading = true
            defer { loading = false }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try Task.checkCancellation()
                try await store.savePhoto(data)
                wallpaper = "photo"
            } catch is CancellationError {
                // Leaving the picker or settings keeps the previous background.
            } catch {
                failed = true
            }
        }
        .alert(JL("تعذر تحميل الصورة", "Unable to load photo"), isPresented: $failed) {
            Button(JL("تمام", "OK"), role: .cancel) {}
        } message: {
            Text(JL("جرّب صورة ثانية أو تأكد من تنزيل الصورة من iCloud.", "Try another photo or check that the photo has downloaded from iCloud."))
        }
    }
}
