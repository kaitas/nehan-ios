import SwiftUI
import PhotosUI
import ImagePlayground

struct BlogEntry {
    var title: String = ""
    var coverURL: String = ""
    var coverImage: UIImage?
    var dateWeatherHealth: String = ""
    var sleepInfo: String = ""
    var dreamDiary: String = ""
    var placesVisited: String = ""
    var todayFeeling: String = ""
    var leftover: String = ""

    var fullText: String {
        [dateWeatherHealth, sleepInfo, dreamDiary, placesVisited, todayFeeling, leftover]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var isEmpty: Bool {
        dateWeatherHealth.isEmpty && sleepInfo.isEmpty && dreamDiary.isEmpty
        && placesVisited.isEmpty && todayFeeling.isEmpty && leftover.isEmpty
    }

    /// Display order: date, sleep, dream, places, leftover, feeling
    static let displayOrder = [0, 1, 2, 3, 5, 4]

    static let placeholders = [
        "今日の天気、ヘルスケアの要約...",
        "睡眠時間、質の記録...",
        "こんな夢を見た...",
        "行った場所の履歴...",
        "今日はどんな日だったか（感想 or emoji）...",
        "やり残したこと..."
    ]

    static let icons = [
        "sun.max",
        "moon.zzz",
        "moon.stars",
        "mappin.and.ellipse",
        "face.smiling",
        "checklist"
    ]

    static let minLines: [Int: Int] = [
        4: 6  // todayFeeling gets 6+ lines
    ]

    var autoTitle: String {
        let streak = UserProfileStore.shared.profile.currentStreak + 1
        return "連続投稿\(streak)日目"
    }

    /// Today's date string (JST)
    static var todayDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.string(from: Date())
    }

    @discardableResult
    mutating func saveCoverImage() -> URL? {
        guard let image = coverImage,
              let data = image.pngData() else { return nil }

        let dateStr = Self.todayDateString.replacingOccurrences(of: "-", with: "")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = dir.appendingPathComponent("cover_\(dateStr).png")

        do {
            try data.write(to: fileURL)
            print("[nehan] Cover art saved: \(fileURL.lastPathComponent) (\(data.count) bytes)")
            return fileURL
        } catch {
            print("[nehan] Failed to save cover art: \(error)")
            return nil
        }
    }
}

struct BlogEditorView: View {
    @Binding var entry: BlogEntry
    var onRegenerate: () -> Void
    var onDraft: () -> Void
    var onPublish: () -> Void
    var isPublished: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showRegenerateConfirm = false
    @State private var showImagePlayground = false
    @State private var showCoverMenu = false
    @State private var photoSelection: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    coverArtSection

                    TextField("タイトル", text: $entry.title)
                        .font(.headline)
                        .padding(.horizontal, 4)

                    Divider()

                    ForEach(BlogEntry.displayOrder, id: \.self) { index in
                        blogField(index: index)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("ブログ編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Button { showRegenerateConfirm = true } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        Button {
                            onDraft()
                            dismiss()
                        } label: {
                            Text("下書き")
                                .font(.subheadline)
                        }
                        Button {
                            onPublish()
                            dismiss()
                        } label: {
                            Text(isPublished ? "更新" : "公開")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .alert("自動生成しますか？", isPresented: $showRegenerateConfirm) {
                Button("Yes") { onRegenerate() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("古い内容は上書きされます")
            }
            .onAppear {
                if entry.title.isEmpty {
                    entry.title = entry.autoTitle
                }
            }
            .onChange(of: photoSelection) { _, item in
                loadPhoto(item)
            }
            .modifier(ImagePlaygroundModifier(
                isPresented: $showImagePlayground,
                entry: $entry
            ))
        }
    }

    // MARK: - Cover Art (16:9)

    private var coverArtSection: some View {
        VStack(spacing: 8) {
            // Image display
            Group {
                if let uiImage = entry.coverImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(16/9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("カバーアート")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }

            // Action buttons
            HStack(spacing: 16) {
                // Photo picker (always available)
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Label("写真を選ぶ", systemImage: "photo.on.rectangle")
                        .font(.caption)
                }

                // Image Playground (iOS 18.1+)
                if imagePlaygroundAvailable {
                    Button {
                        showImagePlayground = true
                    } label: {
                        Label("iPhoneのAIで生成", systemImage: "wand.and.stars")
                            .font(.caption)
                    }
                }

                // Remove cover
                if entry.coverImage != nil {
                    Button(role: .destructive) {
                        entry.coverImage = nil
                    } label: {
                        Label("削除", systemImage: "trash")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var imagePlaygroundAvailable: Bool {
        if #available(iOS 26.0, *) {
            return FoundationModelService.isAvailable
        }
        return false
    }

    // MARK: - Photo Loading

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                entry.coverImage = uiImage.croppedTo16x9()
                entry.saveCoverImage()
            }
        }
    }

    // MARK: - Blog Fields

    private func blogField(index: Int) -> some View {
        let binding: Binding<String> = switch index {
        case 0: $entry.dateWeatherHealth
        case 1: $entry.sleepInfo
        case 2: $entry.dreamDiary
        case 3: $entry.placesVisited
        case 4: $entry.todayFeeling
        default: $entry.leftover
        }

        let lineLimit = BlogEntry.minLines[index] ?? 2

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: BlogEntry.icons[index])
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 8)

            TextField(BlogEntry.placeholders[index], text: binding, axis: .vertical)
                .lineLimit(lineLimit...max(lineLimit, 10))
                .font(.subheadline)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Image Playground Integration

struct ImagePlaygroundModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var entry: BlogEntry

    func body(content: Content) -> some View {
        if #available(iOS 18.1, *) {
            content.imagePlaygroundSheet(
                isPresented: $isPresented,
                concepts: buildConcepts()
            ) { url in
                loadGeneratedImage(from: url)
            }
        } else {
            content
        }
    }

    private func buildConcepts() -> [ImagePlaygroundConcept] {
        var concepts: [ImagePlaygroundConcept] = []

        if !entry.title.isEmpty {
            concepts.append(.text(entry.title))
        }
        if !entry.dateWeatherHealth.isEmpty {
            concepts.append(.text(entry.dateWeatherHealth))
        }
        if !entry.placesVisited.isEmpty {
            concepts.append(.text("Scene: \(entry.placesVisited)"))
        }
        if !entry.todayFeeling.isEmpty {
            concepts.append(.text("Mood: \(entry.todayFeeling)"))
        }
        if !entry.dreamDiary.isEmpty {
            concepts.append(.text("Dream: \(entry.dreamDiary)"))
        }
        if concepts.isEmpty {
            concepts.append(.text("A peaceful lifelog illustration for today"))
        }

        return concepts
    }

    private func loadGeneratedImage(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let uiImage = UIImage(data: data) else { return }

        entry.coverImage = uiImage.croppedTo16x9()
        entry.saveCoverImage()
    }
}

// MARK: - UIImage 16:9 Crop

extension UIImage {
    /// Center-crop to 16:9 aspect ratio
    func croppedTo16x9() -> UIImage {
        let targetRatio: CGFloat = 16.0 / 9.0
        let currentRatio = size.width / size.height

        let cropRect: CGRect
        if currentRatio > targetRatio {
            // Wider than 16:9 → crop sides
            let newWidth = size.height * targetRatio
            let x = (size.width - newWidth) / 2
            cropRect = CGRect(x: x, y: 0, width: newWidth, height: size.height)
        } else if currentRatio < targetRatio {
            // Taller than 16:9 → crop top/bottom
            let newHeight = size.width / targetRatio
            let y = (size.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: y, width: size.width, height: newHeight)
        } else {
            return self // Already 16:9
        }

        // Scale cropRect to pixel coordinates
        let scale = self.scale
        let pixelRect = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )

        guard let cgImage = self.cgImage?.cropping(to: pixelRect) else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}
