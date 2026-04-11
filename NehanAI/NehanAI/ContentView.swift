import SwiftUI
import CoreLocation
import HealthKit

struct ContentView: View {
    @StateObject private var locationService = LocationService.shared
    @StateObject private var bookmarkStore = PlaceBookmarkStore.shared
    @State private var profileStore = UserProfileStore.shared
    @State private var lastSyncTime: Date?
    @State private var lastHealthTime: Date?
    @State private var sleepSummary: HealthKitService.SleepSummary?
    @State private var stepCount: Int = 0
    @State private var heartRate: HealthKitService.HeartRateSummary?
    @State private var mindfulSummary: HealthKitService.MindfulSummary?
    @State private var stateOfMind: HealthKitService.StateOfMindSummary?
    @State private var showingNameDialog = false
    @State private var newPlaceName = ""
    @State private var newPlaceIsSecret = false
    @State private var newPlaceCategory: PlaceBookmark.Category = .other
    @State private var showingBookmarks = false
    @State private var blogEntry = BlogEntry()
    @State private var isGeneratingBlog = false
    @State private var showBlogEditor = false
    @State private var currentWeather: String?
    @State private var showStreakHelp = false
    @State private var menstrualSummary: HealthKitService.MenstrualSummary?
    @State private var appState = AppState.shared
    @State private var showBufferHelp = false
    @State private var showGPSHelp = false
    @State private var showCoordHelp = false
    @State private var showDreamDialog = false
    @State private var dreamInput = ""
    @State private var lastAutoRefresh: Date?
    @State private var showMoodPicker = false
    @State private var selectedMood: String = ""
    @State private var naps: [HealthKitService.NapSummary] = []
    @State private var publishedBlogURL: String?
    @State private var heartRateTimeline: [HealthKitService.HeartRatePoint] = []
    @State private var aiFlavorText: String?
    @State private var showRegistration = false
    @State private var isInitialLoading = true
    @State private var loadingProgress: Double = 0
    @State private var loadingStatus = "起動中..."

    /// Whether Image Playground (Apple Intelligence imagery) is supported on this device.
    private static var isImagePlaygroundSupported: Bool {
        if #available(iOS 26.0, *) {
            return FoundationModelService.isAvailable
        }
        return false
    }

    private static let hmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        ZStack {
            mainContent
            if isInitialLoading {
                splashOverlay
            }
        }
    }

    private var mainContent: some View {
        NavigationStack {
            List {
                headerSection
                statusSection
                quickRecordSection
                timelineSection
                blogSection
                syncSection
            }
            .refreshable { await pullToRefresh() }
            .navigationTitle("nehan.ai")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    let username = AuthService.shared.currentUser?.username
                        ?? (profileStore.profile.displayName.isEmpty ? nil : profileStore.profile.displayName)
                    if let username {
                        Button {
                            if let url = URL(string: "https://nehan.ai/\(username)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("nehan.ai/\(username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("nehan.ai")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showingNameDialog) {
                CoordMemoEditSheet(
                    name: $newPlaceName,
                    isSecret: $newPlaceIsSecret,
                    category: $newPlaceCategory,
                    onSave: { saveCoordMemo(); showingNameDialog = false },
                    onCancel: { showingNameDialog = false }
                )
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingBookmarks) {
                CoordMemoListView(store: bookmarkStore)
            }
            .sheet(isPresented: $showBlogEditor, onDismiss: {
                BlogPublishService.saveLocal(blogEntry)
            }) {
                BlogEditorView(
                    entry: $blogEntry,
                    onRegenerate: { generateBlogDraft() },
                    onDraft: {
                        BlogPublishService.saveLocal(blogEntry)
                        Task { try? await BlogPublishService.saveDraft(entry: blogEntry) }
                    },
                    onPublish: {
                        BlogPublishService.saveLocal(blogEntry)
                        // Check if user needs to register (Tier 0 → Tier 1)
                        let tier = AuthService.shared.currentUser?.tier ?? 0
                        if tier < 1 {
                            showBlogEditor = false
                            showRegistration = true
                            return
                        }
                        Task {
                            do {
                                try await BlogPublishService.publish(entry: blogEntry)
                                profileStore.recordBlogPost()
                                NotificationService.cancelBlogReminder()
                                await checkBlogStatus()
                            } catch {
                                print("[nehan] Blog publish failed: \(error)")
                            }
                        }
                    },
                    isPublished: isTodayBlogPublished
                )
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showRegistration) {
                RegistrationView(onRegistered: {
                    Task {
                        do {
                            try await BlogPublishService.publish(entry: blogEntry)
                            profileStore.recordBlogPost()
                            NotificationService.cancelBlogReminder()
                            await checkBlogStatus()
                        } catch {
                            print("[nehan] Blog publish after registration failed: \(error)")
                        }
                    }
                })
            }
        }
        .onAppear { setupServices() }
        .onChange(of: appState.shouldOpenBlogEditor) { _, shouldOpen in
            if shouldOpen {
                showBlogEditor = true
                appState.shouldOpenBlogEditor = false
            }
        }
        .sheet(isPresented: $showMoodPicker) {
            MoodPickerSheet(selectedMood: $selectedMood) { mood in
                blogEntry.todayFeeling = mood
                BlogPublishService.saveLocal(blogEntry)
                showMoodPicker = false
            }
            .presentationDetents([.medium])
            .presentationBackground(.ultraThinMaterial)
        }
        .alert("おはようございます!", isPresented: $showDreamDialog) {
            TextField("どんな夢を見た？", text: $dreamInput)
            Button("保存") {
                if !dreamInput.isEmpty {
                    blogEntry.dreamDiary = dreamInput
                    BlogPublishService.saveLocal(blogEntry)
                }
                dreamInput = ""
            }
            Button("夢は見なかった", role: .cancel) {
                dreamInput = ""
            }
        } message: {
            Text("どんな夢を見た？")
        }
    }

    // MARK: - Header (context message + expression + streak)

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                // Expression (Image Playground when available & supported)
                if #available(iOS 18.0, *), Self.isImagePlaygroundSupported {
                    ExpressionPlaygroundView(
                        sleepQuality: sleepSummary.map { $0.deepMinutes > 60 ? "良好" : "普通" } ?? "",
                        stepCount: stepCount,
                        mood: blogEntry.todayFeeling.isEmpty ? nil : blogEntry.todayFeeling
                    )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "face.smiling")
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(contextMessage)
                        .font(.subheadline)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(Date(), format: .dateTime.year().month().day().weekday())
                        if let weather = currentWeather {
                            Text("・\(weather)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Streak (tappable)
                if profileStore.profile.currentStreak > 0 {
                    Button { showStreakHelp = true } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("\(profileStore.profile.currentStreak)")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showStreakHelp) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("連続投稿ストリーク", systemImage: "flame.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                            Text("24時間に1回ブログを投稿すると連続記録が伸びます。毎日の記録を続けてストリークを伸ばしましょう！")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(width: 260)
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
    }

    /// Fallback context message when AI flavor text is unavailable.
    /// Follows same 4 time slots as flavorTextPrompt().
    private var contextMessage: String {
        if let ai = aiFlavorText { return ai }

        let hour = Calendar.current.component(.hour, from: Date())
        let loc = locationService.lastLocation
        let matched = loc.flatMap { bookmarkStore.match(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        let place = matched?.name

        switch hour {
        case 6..<12: // Morning — sleep/dream focus
            if let sleep = sleepSummary, sleep.totalMinutes > 360 {
                return "おはようございます、よく眠れましたね"
            }
            return "おはようございます、今日も良い一日を"
        case 12..<18: // Afternoon — activity focus
            if stepCount > 3000 {
                return "\(stepCount.formatted())歩達成、いい調子です！"
            }
            if let p = place {
                return "\(p)でがんばっていますね"
            }
            return "午後もアクティブにいきましょう"
        case 18..<24: // Evening — wind down
            if stepCount > 6000 {
                return "今日は\(stepCount.formatted())歩、お疲れさま"
            }
            return "お疲れさま、そろそろ休みましょう"
        default: // 0..<6 — late night chill
            return "深夜ですね、ゆっくり休んでください"
        }
    }

    // MARK: - Splash Overlay

    private var splashOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // App logo
                Text("N")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundStyle(.white)

                Text("nehan.ai")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: loadingProgress)
                        .tint(.purple)
                        .scaleEffect(y: 2)
                        .padding(.horizontal, 60)

                    Text(loadingStatus)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.bottom, 60)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Flavor Text

    /// Generate AI flavor text using on-device Foundation Models
    /// System prompt varies by time of day (see AGENTS.md §FlavorText)
    private func generateFlavorText() async {
        guard #available(iOS 26.0, *), FoundationModelService.isAvailable else { return }

        let hour = Calendar.current.component(.hour, from: Date())
        let loc = locationService.lastLocation
        let matched = loc.flatMap { bookmarkStore.match(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        let lang = profileStore.profile.language.rawValue

        // Build health context
        var context = "Time: \(hour):00."
        if let sleep = sleepSummary {
            context += " Sleep: \(sleep.totalMinutes / 60)h\(sleep.totalMinutes % 60)m."
        }
        if stepCount > 0 { context += " Steps: \(stepCount)." }
        if let hr = heartRate {
            context += " Heart rate avg: \(hr.average) bpm, max: \(hr.max) bpm."
            if let resting = hr.resting { context += " Resting: \(resting) bpm." }
            if let hrv = hr.hrv { context += " HRV: \(Int(hrv))ms." }
        }
        if let place = matched?.name { context += " Location: \(place)." }
        if let som = stateOfMind { context += " Mood: \(som.labels.joined(separator: ", "))." }
        if profileStore.profile.currentStreak > 0 {
            context += " Blog streak: \(profileStore.profile.currentStreak) days."
        }

        let prompt = Self.flavorTextPrompt(hour: hour, lang: lang, context: context)

        do {
            if #available(iOS 26.0, *) {
                let raw = try await FoundationModelService.generate(prompt: prompt)
                let cleaned = raw
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "**", with: "")
                    // Strip parenthetical translations e.g. "(Congratulations!)"
                    .replacingOccurrences(of: "\\s*[（(][^)）]*[)）]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    aiFlavorText = String(cleaned.prefix(40))
                }
            }
        } catch {
            print("[nehan] Flavor text generation failed: \(error)")
        }
    }

    /// Time-based system prompt for flavor text generation.
    /// Designed for extensibility: events, promotions, seasons can override.
    /// See AGENTS.md §FlavorText for full specification.
    static func flavorTextPrompt(hour: Int, lang: String, context: String, event: String? = nil) -> String {
        let langName = lang == "ja" ? "Japanese" : "English"

        // Event/promotion override
        if let event {
            return """
            You are a friendly wellness companion. \(event) Based on the user's data, generate ONE short message (max 40 characters) in \(langName). No quotes, no markdown, just plain text.

            Context: \(context)
            """
        }

        // Time-based persona
        let persona: String
        switch hour {
        case 6..<12:
            persona = "Greet with 'Good morning!' energy. Comment on their sleep quality or dreams if data is available. Be bright and encouraging for the day ahead."
        case 12..<18:
            persona = "Be an active supporter. Encourage their activity, steps, and movement. Be energetic and motivating for the afternoon."
        case 18..<24:
            persona = "Acknowledge their hard work today. Gently ask about bedtime plans or winding down. Be warm and appreciative."
        default: // 0..<6
            persona = "It's late night / early morning. Promote relaxation and chill. If they're still up, gently suggest rest. Be calm and soothing."
        }

        return """
        You are a friendly wellness companion. \(persona) Based on the user's health data, generate ONE short encouraging message (max 40 characters) in \(langName) ONLY. Do NOT include translations, parenthetical text, or any other language. Output ONLY the plain message text. No language codes, no quotes, no markdown, no parentheses, no explanation.

        Context: \(context)
        """
    }

    // MARK: - Status (Row 1: tracking + buffer + sync / Row 2: GPS + coord memo)

    private var statusSection: some View {
        Section {
            // Row 1: Tracking status + buffer + last sync
            HStack(spacing: 6) {
                Circle()
                    .fill(locationService.isTracking ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(locationService.isTracking ? "記録中" : "停止中")
                    .font(.subheadline)

                if SyncService.shared.pendingCount > 0 {
                    Button { showBufferHelp = true } label: {
                        Text("\(SyncService.shared.pendingCount)件")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showBufferHelp) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("同期バッファ", systemImage: "tray.full")
                                .font(.subheadline.bold())
                            Text("位置情報・睡眠・メモなどの記録がバッファに\(SyncService.shared.pendingCount)件たまっています。50件に達するか「今すぐ同期」を押すとサーバーに送信されます。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(width: 280)
                        .presentationCompactAdaptation(.popover)
                    }
                }

                Spacer()

                if let t = lastSyncTime {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text(Self.hmFormatter.string(from: t))
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Row 2: GPS accuracy + coord memo name
            if let loc = locationService.lastLocation {
                let coord = loc.coordinate
                let matched = bookmarkStore.match(latitude: coord.latitude, longitude: coord.longitude)

                HStack(spacing: 8) {
                    Button { showGPSHelp = true } label: {
                        gpsAccuracyView(accuracy: loc.horizontalAccuracy)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showGPSHelp) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("GPS精度", systemImage: "location.fill")
                                .font(.subheadline.bold())
                            Text("現在のGPS精度を色で表示しています。")
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 4) {
                                gpsHelpRow(color: .green, text: "±10m以内 — 高精度")
                                gpsHelpRow(color: .yellow, text: "±50m以内 — 中精度")
                                gpsHelpRow(color: .orange, text: "±100m以内 — 低精度")
                                gpsHelpRow(color: .red, text: "±100m以上 — 非常に低精度")
                            }
                        }
                        .padding()
                        .frame(width: 260)
                        .presentationCompactAdaptation(.popover)
                    }

                    if let matched {
                        Button { showCoordHelp = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(matched.name)
                                    .font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showCoordHelp) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("座標メモ", systemImage: "mappin.and.ellipse")
                                    .font(.subheadline.bold())
                                Text("現在地から200m以内に登録された座標メモ「\(matched.name)」(\(matched.category.rawValue))にマッチしています。座標や住所の代わりにこの名前で記録されます。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(width: 280)
                            .presentationCompactAdaptation(.popover)
                        }
                    } else {
                        Text("\(coord.latitude, specifier: "%.4f"), \(coord.longitude, specifier: "%.4f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contextMenu {
                    if matched == nil {
                        Button {
                            UIPasteboard.general.string = "\(coord.latitude), \(coord.longitude)"
                        } label: {
                            Label("座標をコピー", systemImage: "doc.on.doc")
                        }
                    }
                    Button {
                        newPlaceName = matched?.name ?? ""
                        newPlaceIsSecret = matched?.isSecret ?? false
                        showingNameDialog = true
                    } label: {
                        Label(matched != nil ? "座標メモを編集" : "座標メモを登録", systemImage: "mappin.and.ellipse")
                    }
                    if let m = matched {
                        Button(role: .destructive) {
                            bookmarkStore.remove(id: m.id)
                        } label: {
                            Label("座標メモ削除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func gpsHelpRow(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Timeline (ライフログ)

    private var timelineSection: some View {
        Section {
            // 288-cell timeline (00:00-23:55, 5min each)
            TimelineBarView(
                sleepSummary: sleepSummary,
                stepCount: stepCount,
                heartRate: heartRate,
                naps: naps,
                heartRatePoints: heartRateTimeline,
                locationHistory: locationService.recentLocations
            )

            // Health data icons (monochrome)
            HStack(spacing: 16) {
                if let sleep = sleepSummary {
                    let h = sleep.totalMinutes / 60
                    let m = sleep.totalMinutes % 60
                    Label("\(h)h\(m)m", systemImage: "moon.zzz")
                        .font(.caption)
                }
                if stepCount > 0 {
                    Label(stepCount.formatted(), systemImage: "figure.walk")
                        .font(.caption)
                }
                if let mindful = mindfulSummary {
                    Label("\(mindful.totalMinutes)m", systemImage: "brain.head.profile")
                        .font(.caption)
                }
                if let som = stateOfMind {
                    Text("\(som.valenceLabel) \(som.labels.first ?? "")")
                        .font(.caption)
                } else if !selectedMood.isEmpty {
                    Text(selectedMood)
                        .font(.caption)
                } else {
                    Button { showMoodPicker = true } label: {
                        Label("気分を記録", systemImage: "face.smiling")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
                if let mc = menstrualSummary, mc.isOnPeriod {
                    Text(mc.flowLevel.emoji)
                        .font(.caption)
                }
            }
            .foregroundStyle(.primary)

            // Sleep detail (compact)
            if let sleep = sleepSummary {
                HStack(spacing: 10) {
                    if let asleep = sleep.asleep, let awake = sleep.awake {
                        Label("\(asleep.formatted(date: .omitted, time: .shortened))→\(awake.formatted(date: .omitted, time: .shortened))", systemImage: "bed.double")
                            .font(.caption2)
                    }
                    Label("\(sleep.deepMinutes)m", systemImage: "moon.zzz.fill")
                        .font(.caption2)
                    Label("\(sleep.remMinutes)m", systemImage: "brain.head.profile")
                        .font(.caption2)
                    Label("\(sleep.coreMinutes)m", systemImage: "powerplug")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            // Heart rate detail
            if let hr = heartRate {
                HStack(spacing: 10) {
                    Label("avg \(hr.average)", systemImage: "heart.fill")
                        .font(.caption2)
                    Label("max \(hr.max)", systemImage: "heart.bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(hr.max > 150 ? .red : .secondary)
                    if let resting = hr.resting {
                        Label("rest \(resting)", systemImage: "heart.circle")
                            .font(.caption2)
                    }
                    if let hrv = hr.hrv {
                        Label("HRV \(Int(hrv))ms", systemImage: "waveform.path.ecg")
                            .font(.caption2)
                            .foregroundStyle(hrv < 20 ? .orange : .secondary)
                    }
                }
                .foregroundStyle(.secondary)
            }

            // Naps (daytime sleep)
            if !naps.isEmpty {
                ForEach(naps, id: \.startTime) { nap in
                    HStack(spacing: 8) {
                        Image(systemName: "zzz")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Text("\(nap.startTime.formatted(date: .omitted, time: .shortened))〜\(nap.endTime.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                        Text("\(nap.durationMinutes)分")
                            .font(.caption2)
                            .bold()
                        Text(nap.evaluation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("ライフログ")
                Spacer()
                if let t = lastHealthTime {
                    Text(Self.hmFormatter.string(from: t))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Quick Record Section

    private var quickRecordSection: some View {
        Section {
            QuickRecordBar()
        } header: {
            Text("クイック記録")
        }
    }

    // MARK: - Blog Section

    private var blogSection: some View {
        Section {
            if isGeneratingBlog {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("自動ブログ執筆中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !blogEntry.isEmpty {
                // Tappable preview that opens editor
                Button { showBlogEditor = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<6, id: \.self) { index in
                            let text = fieldText(for: index)
                            if !text.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: BlogEntry.icons[index])
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 14)
                                    Text(text)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } else {
                Button {
                    generateBlogDraft()
                } label: {
                    Label("今日のブログを自動作文する", systemImage: "doc.text")
                }
            }
            if publishedBlogURL != nil {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await unpublishBlog()
                        } catch {
                            print("[nehan] Unpublish failed: \(error)")
                        }
                    }
                } label: {
                    Label("下書きに戻す", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
            }
        } header: {
            HStack {
                Text("ブログ")
                Spacer()
                if let blogURL = publishedBlogURL {
                    Button {
                        if let url = URL(string: blogURL) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("公開済み", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else if isTodayBlogPublished {
                    Label("投稿済み", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("\(profileStore.profile.blogPublishHour)時に自動投稿")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("1日1件のブログを書いてストリークを獲得")
                .font(.caption2)
        }
    }

    /// Whether today's blog has already been published (not draft)
    private var isTodayBlogPublished: Bool {
        profileStore.profile.lastBlogDate == BlogEntry.todayDateString
    }

    private func fieldText(for index: Int) -> String {
        switch index {
        case 0: blogEntry.dateWeatherHealth
        case 1: blogEntry.sleepInfo
        case 2: blogEntry.dreamDiary
        case 3: blogEntry.placesVisited
        case 4: blogEntry.todayFeeling
        default: blogEntry.leftover
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section("操作") {
            HStack {
                Button {
                    Task {
                        await SyncService.shared.sync()
                        lastSyncTime = Date()
                        await checkBlogStatus()
                    }
                } label: {
                    Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                }
                Spacer()
                if let t = lastSyncTime {
                    Text(Self.hmFormatter.string(from: t))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    Task {
                        do {
                            let hk = HealthKitService.shared
                            if let sleepEntry = try await hk.fetchSleepData(for: Date()) {
                                SyncService.shared.addEntry(sleepEntry)
                            }
                            if let healthEntry = try await hk.fetchDailyHealthData(for: Date()) {
                                SyncService.shared.addEntry(healthEntry)
                            }
                            await refreshHealthData()
                            lastHealthTime = Date()
                        } catch {
                            print("[nehan] Health fetch error: \(error)")
                        }
                    }
                } label: {
                    Label("ヘルスデータ取得", systemImage: "heart.text.clipboard")
                }

                Spacer()

                // Stop / Start tracking
                Button {
                    if locationService.isTracking {
                        locationService.stopTracking()
                    } else {
                        locationService.requestPermission()
                        locationService.startTracking()
                    }
                } label: {
                    Image(systemName: locationService.isTracking ? "pause.circle" : "play.circle")
                }

                if let t = lastHealthTime {
                    Text(Self.hmFormatter.string(from: t))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showingBookmarks = true
            } label: {
                Label("座標メモ一覧", systemImage: "mappin.and.ellipse")
            }
        }
    }

    // MARK: - GPS Accuracy View

    private func gpsAccuracyView(accuracy: CLLocationAccuracy) -> some View {
        let (icon, color): (String, Color) = {
            if accuracy < 0 { return ("location.slash", .red) }
            else if accuracy <= 10 { return ("location.fill", .green) }
            else if accuracy <= 50 { return ("location.fill", .yellow) }
            else if accuracy <= 100 { return ("location", .orange) }
            else { return ("location", .red) }
        }()

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption2)
            Text("±\(Int(accuracy))m")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Blog Generation

    private func generateBlogDraft() {
        isGeneratingBlog = true
        Task {
            let jstFormatter = DateFormatter()
            jstFormatter.dateFormat = "yyyy年M月d日(E)"
            jstFormatter.locale = Locale(identifier: "ja_JP")
            jstFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
            let dateStr = jstFormatter.string(from: Date())

            // Preserve existing cover image
            let existingCoverImage = blogEntry.coverImage
            let existingCoverURL = blogEntry.coverURL

            var entry = BlogEntry()

            // Restore cover image
            entry.coverImage = existingCoverImage
            entry.coverURL = existingCoverURL

            // Field 0: Date + Weather + Health summary
            var field0 = dateStr
            if let weather = currentWeather {
                field0 += " \(weather)"
            }
            if stepCount > 0 {
                field0 += " / \(stepCount.formatted())歩"
            }
            if let hr = heartRate {
                field0 += " / ♡\(hr.average)bpm"
            }
            entry.dateWeatherHealth = field0

            // Field 1: Sleep info with quality evaluation
            if let sleep = sleepSummary {
                let h = sleep.totalMinutes / 60
                let m = sleep.totalMinutes % 60
                var sleepText = "睡眠 \(h)h\(m > 0 ? "\(m)m" : "")"
                if let asleep = sleep.asleep, let awake = sleep.awake {
                    sleepText += "（\(asleep.formatted(date: .omitted, time: .shortened))→\(awake.formatted(date: .omitted, time: .shortened))）"
                }
                sleepText += " deep:\(sleep.deepMinutes)m rem:\(sleep.remMinutes)m"

                // Sleep quality evaluation
                let totalHours = Double(sleep.totalMinutes) / 60.0
                let quantityEval: String
                if totalHours >= 7.5 { quantityEval = "十分" }
                else if totalHours >= 6.0 { quantityEval = "やや不足" }
                else { quantityEval = "不足" }

                let qualityEval: String
                if sleep.deepMinutes >= 60 && sleep.remMinutes >= 45 { qualityEval = "良好" }
                else if sleep.deepMinutes >= 30 { qualityEval = "普通" }
                else { qualityEval = "浅め" }

                sleepText += "\n量: \(quantityEval) / 質: \(qualityEval)"

                // Append nap info
                if !naps.isEmpty {
                    sleepText += "\n\n昼寝（Naps）:"
                    for nap in naps {
                        sleepText += "\n\(nap.startTime.formatted(date: .omitted, time: .shortened))〜\(nap.endTime.formatted(date: .omitted, time: .shortened)) \(nap.durationMinutes)分 — \(nap.evaluation)"
                    }
                }

                entry.sleepInfo = sleepText
            }

            // Field 2: Dream diary (keep existing if user already typed)
            entry.dreamDiary = blogEntry.dreamDiary

            // Field 3: Places visited
            let lang = profileStore.profile.language
            if let loc = locationService.lastLocation {
                let matched = bookmarkStore.match(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                if let name = matched?.name {
                    entry.placesVisited = name
                } else {
                    entry.placesVisited = lang == .en ? "Haven't gone anywhere yet today" : "今日はまだどこにも行っていない"
                }
            } else {
                entry.placesVisited = lang == .en ? "Haven't gone anywhere yet today" : "今日はまだどこにも行っていない"
            }

            // Field 4: Today feeling (keep existing)
            entry.todayFeeling = blogEntry.todayFeeling

            // Field 5: Leftover (keep existing)
            entry.leftover = blogEntry.leftover

            blogEntry = entry
            isGeneratingBlog = false

            // Try Foundation Models for enhanced generation
            if #available(iOS 26.0, *) {
                Task {
                    await generateWithLLM()
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func generateWithLLM() async {
        let context = FoundationModelService.BlogContext(
            date: blogEntry.dateWeatherHealth,
            weather: currentWeather,
            sleepHours: sleepSummary.map { Double($0.totalMinutes) / 60.0 },
            sleepQuality: sleepSummary.map { $0.deepMinutes > 60 ? "良好" : "普通" },
            stepCount: stepCount > 0 ? stepCount : nil,
            heartRate: heartRate?.average,
            places: blogEntry.placesVisited.isEmpty ? [] : [blogEntry.placesVisited],
            dreamDiary: blogEntry.dreamDiary.isEmpty ? nil : blogEntry.dreamDiary,
            feeling: blogEntry.todayFeeling.isEmpty ? nil : blogEntry.todayFeeling,
            leftover: blogEntry.leftover.isEmpty ? nil : blogEntry.leftover,
            displayName: profileStore.profile.displayName.isEmpty ? nil : profileStore.profile.displayName
        )

        do {
            let generated = try await FoundationModelService.generateBlog(context: context)
            if !generated.isEmpty {
                blogEntry.todayFeeling = generated
            }
        } catch {
            print("[nehan] Foundation Models error: \(error)")
        }
    }

    // MARK: - Helpers

    private func saveCoordMemo() {
        guard let loc = locationService.lastLocation, !newPlaceName.isEmpty else { return }
        let coord = loc.coordinate
        if let existing = bookmarkStore.match(latitude: coord.latitude, longitude: coord.longitude) {
            var updated = existing
            updated.name = newPlaceName
            updated.isSecret = newPlaceIsSecret
            updated.category = newPlaceCategory
            bookmarkStore.update(updated)
        } else {
            bookmarkStore.add(PlaceBookmark(
                name: newPlaceName,
                latitude: coord.latitude,
                longitude: coord.longitude,
                isSecret: newPlaceIsSecret,
                category: newPlaceCategory
            ))
        }
        newPlaceName = ""
        newPlaceIsSecret = false
        newPlaceCategory = .other
    }

    private func setupServices() {
        locationService.onNewLocation = { [bookmarkStore] entry in
            SyncService.shared.addEntry(entry)
            if let loc = LocationService.shared.lastLocation {
                bookmarkStore.updateLastVisited(
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                )
            }
        }
        Task {
            loadingStatus = "HealthKit 接続中..."
            loadingProgress = 0.1
            try? await HealthKitService.shared.requestPermission()

            loadingStatus = "健康データ取得中..."
            loadingProgress = 0.3
            let hadSleepBefore = sleepSummary != nil
            await refreshHealthData()
            lastHealthTime = Date()

            loadingStatus = "クラウド同期中..."
            loadingProgress = 0.5
            let hk = HealthKitService.shared
            if let sleepEntry = try? await hk.fetchSleepData(for: Date()) {
                SyncService.shared.addEntry(sleepEntry)
            }
            if let healthEntry = try? await hk.fetchDailyHealthData(for: Date()) {
                SyncService.shared.addEntry(healthEntry)
            }
            await SyncService.shared.sync()
            lastSyncTime = Date()
            lastAutoRefresh = Date()

            loadingStatus = "ブログ確認中..."
            loadingProgress = 0.7
            await checkBlogStatus()

            loadingStatus = "準備完了"
            loadingProgress = 1.0

            // Show dream diary dialog if new sleep data detected
            if !hadSleepBefore && sleepSummary != nil && blogEntry.dreamDiary.isEmpty {
                showDreamDialog = true
            }

            withAnimation(.easeOut(duration: 0.5)) {
                isInitialLoading = false
            }
        }
        locationService.requestPermission()
        locationService.startTracking()
    }

    private func pullToRefresh() async {
        let hk = HealthKitService.shared
        if let sleepEntry = try? await hk.fetchSleepData(for: Date()) {
            SyncService.shared.addEntry(sleepEntry)
        }
        if let healthEntry = try? await hk.fetchDailyHealthData(for: Date()) {
            SyncService.shared.addEntry(healthEntry)
        }
        await refreshHealthData()
        await SyncService.shared.sync()
        lastHealthTime = Date()
        lastSyncTime = Date()
        await checkBlogStatus()
    }

    /// Check if today's blog is published on the server
    private func checkBlogStatus() async {
        guard let username = AuthService.shared.currentUser?.username
            ?? (profileStore.profile.displayName.isEmpty ? nil : profileStore.profile.displayName) else { return }
        let dateStr = BlogEntry.todayDateString
        let yymmdd = String(dateStr.dropFirst(2)).replacingOccurrences(of: "-", with: "")

        // Check if blog exists by fetching the public page (HEAD request)
        let blogURL = "https://nehan.ai/\(username)/\(yymmdd)"
        guard let checkURL = URL(string: blogURL) else { return }

        var request = URLRequest(url: checkURL)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                publishedBlogURL = blogURL
            } else {
                publishedBlogURL = nil
            }
        } catch {
            publishedBlogURL = nil
        }
    }

    private func unpublishBlog() async throws {
        let dateString = BlogEntry.todayDateString
        guard let url = URL(string: "\(AppConfig.workerURL)/api/blog") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AuthService.shared.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Re-post as draft
        let payload: [String: Any] = [
            "date": dateString,
            "body": blogEntry.fullText.isEmpty ? "draft" : blogEntry.fullText,
            "title": blogEntry.title.isEmpty ? blogEntry.autoTitle : blogEntry.title,
            "is_draft": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        publishedBlogURL = nil
    }

    private func refreshHealthData() async {
        let today = Date()
        let hk = HealthKitService.shared
        sleepSummary = try? await hk.fetchSleepSummary(for: today)
        naps = (try? await hk.fetchNaps(for: today)) ?? []
        stepCount = (try? await hk.fetchStepCount(for: today)) ?? 0
        heartRate = try? await hk.fetchHeartRateSummary(for: today)
        heartRateTimeline = (try? await hk.fetchHeartRateTimeline(for: today)) ?? []
        mindfulSummary = try? await hk.fetchMindfulSummary(for: today)
        if #available(iOS 18.0, *) {
            stateOfMind = try? await hk.fetchStateOfMind(for: today)
        }
        if UserProfileStore.shared.isFemale {
            menstrualSummary = try? await hk.fetchMenstrualSummary(for: today)
        }
        // Generate AI flavor text after health data is available
        await generateFlavorText()
    }
}

// MARK: - Timeline Bar View (288 cells = 24h x 12 per hour)

struct TimelineBarView: View {
    let sleepSummary: HealthKitService.SleepSummary?
    let stepCount: Int
    let heartRate: HealthKitService.HeartRateSummary?
    var naps: [HealthKitService.NapSummary] = []
    var heartRatePoints: [HealthKitService.HeartRatePoint] = []
    var locationHistory: [(time: Date, latitude: Double, longitude: Double)] = []

    private let cellCount = 288 // 24h * 12 (5min each)

    /// Sedentary work analysis: consecutive stationary 5-min slots
    private var sedentarySlots: [Int: SedentaryInfo] {
        guard locationHistory.count >= 2 else { return [:] }
        let cal = Calendar.current

        // Group locations into 5-min slots
        var slotLocations: [Int: (lat: Double, lon: Double)] = [:]
        for loc in locationHistory {
            let idx = cal.component(.hour, from: loc.time) * 12 + cal.component(.minute, from: loc.time) / 5
            slotLocations[idx] = (loc.latitude, loc.longitude)
        }

        // Detect consecutive stationary periods (within 200m)
        var result: [Int: SedentaryInfo] = [:]
        var streakStart: Int?
        var streakRef: (lat: Double, lon: Double)?

        let sortedSlots = slotLocations.keys.sorted()
        for slot in sortedSlots {
            guard let loc = slotLocations[slot] else { continue }
            if let ref = streakRef {
                let dist = haversineMeters(lat1: ref.lat, lon1: ref.lon, lat2: loc.lat, lon2: loc.lon)
                if dist < 200 {
                    // Still stationary
                    let duration = (slot - (streakStart ?? slot)) * 5 // minutes
                    let info = SedentaryInfo(minutesSitting: duration)
                    result[slot] = info
                } else {
                    // Moved — reset streak
                    streakStart = slot
                    streakRef = loc
                }
            } else {
                streakStart = slot
                streakRef = loc
            }
        }

        // Back-fill streak info for all slots in each streak
        // Re-scan to assign duration to all slots in a streak
        var finalResult: [Int: SedentaryInfo] = [:]
        var currentStreakStart: Int?
        var currentRef: (lat: Double, lon: Double)?
        for slot in sortedSlots {
            guard let loc = slotLocations[slot] else { continue }
            if let ref = currentRef, let start = currentStreakStart {
                let dist = haversineMeters(lat1: ref.lat, lon1: ref.lon, lat2: loc.lat, lon2: loc.lon)
                if dist < 200 {
                    let duration = (slot - start + 1) * 5
                    // Update all slots in this streak
                    for s in start...slot {
                        finalResult[s] = SedentaryInfo(minutesSitting: duration)
                    }
                    continue
                }
            }
            currentStreakStart = slot
            currentRef = loc
        }
        return finalResult
    }

    /// HR values bucketed into 5-min slots (average per slot)
    private var hrSlots: [Int: Int] {
        guard !heartRatePoints.isEmpty else { return [:] }
        let cal = Calendar.current
        var buckets: [Int: [Int]] = [:]
        for p in heartRatePoints {
            let idx = cal.component(.hour, from: p.time) * 12 + cal.component(.minute, from: p.time) / 5
            buckets[idx, default: []].append(p.bpm)
        }
        return buckets.mapValues { values in values.reduce(0, +) / values.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Time labels
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    if hour > 0 { Spacer() }
                    Text("\(hour)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    if hour < 24 { Spacer() }
                }
            }

            // Activity timeline with heart rate sparkline overlay
            GeometryReader { geo in
                let cellWidth = geo.size.width / CGFloat(cellCount)
                let barHeight: CGFloat = 20
                ZStack(alignment: .bottom) {
                    // Activity colors (background)
                    HStack(spacing: 0) {
                        ForEach(0..<cellCount, id: \.self) { index in
                            Rectangle()
                                .fill(cellColor(for: index))
                                .frame(width: max(cellWidth, 0.5), height: barHeight)
                        }
                    }

                    // Heart rate sparkline (overlay)
                    if !heartRatePoints.isEmpty {
                        let maxHR = heartRatePoints.map(\.bpm).max() ?? 180
                        let minHR = heartRatePoints.map(\.bpm).min() ?? 40
                        let range = max(Double(maxHR - minHR), 1.0)
                        HStack(spacing: 0) {
                            ForEach(0..<cellCount, id: \.self) { index in
                                if let bpm = hrSlots[index] {
                                    let h = max(2, (barHeight - 2) * (Double(bpm - minHR) / range))
                                    VStack(spacing: 0) {
                                        Spacer(minLength: 0)
                                        Rectangle()
                                            .fill(hrColor(bpm: bpm))
                                            .frame(width: max(cellWidth, 0.5), height: h)
                                    }
                                } else {
                                    Color.clear
                                        .frame(width: max(cellWidth, 0.5), height: barHeight)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Legend
            HStack(spacing: 8) {
                legendItem(color: .purple.opacity(0.7), label: "睡眠")
                if !naps.isEmpty {
                    legendItem(color: .indigo.opacity(0.5), label: "昼寝")
                }
                legendItem(color: .green.opacity(0.6), label: "活動")
                legendItem(color: .blue.opacity(0.5), label: "座位")
                legendItem(color: .orange.opacity(0.6), label: "4h+")
                legendItem(color: .red.opacity(0.7), label: "8h+")
                if !heartRatePoints.isEmpty {
                    legendItem(color: .pink.opacity(0.5), label: "HR")
                }
            }
            .font(.system(size: 10))

            // Help text for work/sedentary colors
            Text("座位: 同じ場所に30分以上滞在。4h+/8h+は連続座位時間。HRは心拍スパークライン")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            // Sedentary work summary
            if let maxSitting = sedentarySlots.values.map(\.minutesSitting).max(), maxSitting >= 60 {
                let hours = maxSitting / 60
                let mins = maxSitting % 60
                HStack(spacing: 4) {
                    Image(systemName: maxSitting >= 480 ? "exclamationmark.triangle.fill" : "chair.fill")
                        .font(.caption2)
                        .foregroundStyle(maxSitting >= 480 ? .red : maxSitting >= 240 ? .orange : .blue)
                    Text("最長連続座位: \(hours)h\(mins)m")
                        .font(.caption2)
                    if maxSitting >= 480 {
                        Text("過集中注意")
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.red)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func cellColor(for index: Int) -> Color {
        let cal = Calendar.current

        // Sleep time
        if let sleep = sleepSummary, let asleep = sleep.asleep, let awake = sleep.awake {
            let sleepHour = cal.component(.hour, from: asleep)
            let sleepMin = cal.component(.minute, from: asleep)
            let wakeHour = cal.component(.hour, from: awake)
            let wakeMin = cal.component(.minute, from: awake)

            let sleepIndex = sleepHour * 12 + sleepMin / 5
            let wakeIndex = wakeHour * 12 + wakeMin / 5

            if sleepIndex > wakeIndex {
                if index >= sleepIndex || index < wakeIndex {
                    return .purple.opacity(0.7)
                }
            } else {
                if index >= sleepIndex && index < wakeIndex {
                    return .purple.opacity(0.7)
                }
            }
        }

        // Nap time
        for nap in naps {
            let napStartIndex = cal.component(.hour, from: nap.startTime) * 12 + cal.component(.minute, from: nap.startTime) / 5
            let napEndIndex = cal.component(.hour, from: nap.endTime) * 12 + cal.component(.minute, from: nap.endTime) / 5
            if index >= napStartIndex && index < napEndIndex {
                return .indigo.opacity(0.5)
            }
        }

        // Future
        let currentIndex = cal.component(.hour, from: Date()) * 12 + cal.component(.minute, from: Date()) / 5
        if index > currentIndex {
            return .secondary.opacity(0.08)
        }

        // Sedentary work detection (from location data)
        if let sedentary = sedentarySlots[index] {
            if sedentary.minutesSitting >= 480 {
                return .red.opacity(0.7)    // 8h+ overwork
            } else if sedentary.minutesSitting >= 240 {
                return .orange.opacity(0.6) // 4-8h long sitting
            } else if sedentary.minutesSitting >= 30 {
                return .blue.opacity(0.5)   // normal work
            }
        }

        // Has heart rate data → at least alive/active
        if hrSlots[index] != nil {
            return .green.opacity(0.4)
        }

        // Daytime with steps = active
        let hour = index / 12
        if stepCount > 0 && hour >= 7 && hour <= 22 {
            return .green.opacity(0.4)
        }

        if hour >= 7 && hour <= 22 {
            return .secondary.opacity(0.2) // awake but no data
        }

        return .secondary.opacity(0.1) // no data
    }

    /// Heart rate bar color: green = normal, orange = elevated, red = high
    private func hrColor(bpm: Int) -> Color {
        if bpm >= 150 { return .red.opacity(0.8) }
        if bpm >= 100 { return .orange.opacity(0.7) }
        return .pink.opacity(0.5)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0
        let toRad = { (d: Double) in d * .pi / 180 }
        let dLat = toRad(lat2 - lat1)
        let dLon = toRad(lon2 - lon1)
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(toRad(lat1)) * cos(toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

struct SedentaryInfo {
    let minutesSitting: Int
}

// MARK: - Coordinate Memo Edit Sheet (Glass)

struct CoordMemoEditSheet: View {
    @Binding var name: String
    @Binding var isSecret: Bool
    @Binding var category: PlaceBookmark.Category
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("場所の名前") {
                    TextField("名前を入力", text: $name)
                }

                Section("カテゴリー") {
                    Picker("カテゴリー", selection: $category) {
                        ForEach(PlaceBookmark.Category.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Toggle("住所を非表示にする", isOn: $isSecret)
                } footer: {
                    Text("ONにすると、ブログや日報に座標・住所が表示されず、登録した名前のみが使用されます。")
                }
            }
            .navigationTitle("座標メモ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: onSave)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Coordinate Memo List

struct CoordMemoListView: View {
    @ObservedObject var store: PlaceBookmarkStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingBookmark: PlaceBookmark?
    @State private var editName = ""
    @State private var editIsSecret = false
    @State private var editCategory: PlaceBookmark.Category = .other

    private static let dtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                // Tips
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("座標メモとは？", systemImage: "lightbulb.min")
                            .font(.body.bold())
                            .foregroundStyle(.primary)
                        Text("GPSの座標や住所を表示・記録せずに、登録した名前だけで記録できます。最大精度なら「自席」レベルでも登録可能。プライバシーを守りながらブログに役立つ地名を管理しましょう。")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                    }
                    .padding(.vertical, 4)
                }

                // Bookmarks
                Section {
                    if store.bookmarks.isEmpty {
                        Text("座標メモなし")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.bookmarks) { bookmark in
                            coordMemoRow(bookmark)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editName = bookmark.name
                                    editIsSecret = bookmark.isSecret
                                    editCategory = bookmark.category
                                    editingBookmark = bookmark
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.remove(id: bookmark.id)
                                    } label: {
                                        Label("", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        editName = bookmark.name
                                        editIsSecret = bookmark.isSecret
                                        editingBookmark = bookmark
                                    } label: {
                                        Label("", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("座標メモ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $editingBookmark) { bookmark in
                CoordMemoEditSheet(
                    name: $editName,
                    isSecret: $editIsSecret,
                    category: $editCategory,
                    onSave: {
                        if var bm = editingBookmark {
                            bm.name = editName
                            bm.isSecret = editIsSecret
                            bm.category = editCategory
                            store.update(bm)
                        }
                        editingBookmark = nil
                    },
                    onCancel: { editingBookmark = nil }
                )
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private func coordMemoRow(_ bookmark: PlaceBookmark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: bookmark.category.icon)
                    .font(.subheadline)
                    .foregroundStyle(.purple)
                    .frame(width: 24)
                Text(bookmark.name)
                    .font(.headline)
                Text(bookmark.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                if bookmark.isSecret {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
            }

            // Last visited
            if let visited = bookmark.lastVisitedAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(Self.dtFormatter.string(from: visited))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            // Coordinates (only if not secret)
            if !bookmark.isSecret {
                Text("\(bookmark.latitude, specifier: "%.4f"), \(bookmark.longitude, specifier: "%.4f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Created at (smaller)
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 9))
                Text(Self.dtFormatter.string(from: bookmark.createdAt))
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Mood Picker Sheet

struct MoodPickerSheet: View {
    @Binding var selectedMood: String
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    struct MoodItem {
        let emoji: String
        let label: String
        let valence: Double
        let hkLabel: String // HKStateOfMind.Label case name
    }

    private let moods: [MoodItem] = [
        MoodItem(emoji: "😊", label: "幸せ", valence: 0.8, hkLabel: "happy"),
        MoodItem(emoji: "🙂", label: "穏やか", valence: 0.5, hkLabel: "calm"),
        MoodItem(emoji: "😐", label: "普通", valence: 0.0, hkLabel: "indifferent"),
        MoodItem(emoji: "😔", label: "悲しい", valence: -0.6, hkLabel: "sad"),
        MoodItem(emoji: "😤", label: "イライラ", valence: -0.5, hkLabel: "irritated"),
        MoodItem(emoji: "😰", label: "不安", valence: -0.7, hkLabel: "anxious"),
        MoodItem(emoji: "🤩", label: "興奮", valence: 0.7, hkLabel: "excited"),
        MoodItem(emoji: "😴", label: "眠い", valence: -0.1, hkLabel: "drained"),
        MoodItem(emoji: "💪", label: "元気", valence: 0.6, hkLabel: "confident"),
        MoodItem(emoji: "🥱", label: "疲れた", valence: -0.3, hkLabel: "drained"),
        MoodItem(emoji: "🤔", label: "考え中", valence: 0.1, hkLabel: "indifferent"),
        MoodItem(emoji: "😌", label: "リラックス", valence: 0.4, hkLabel: "peaceful"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("今の気分は？")
                    .font(.title3.bold())
                    .padding(.top)

                if saved {
                    Label("HealthKitに保存しました", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    ForEach(moods, id: \.emoji) { mood in
                        Button {
                            selectMood(mood)
                        } label: {
                            VStack(spacing: 4) {
                                Text(mood.emoji)
                                    .font(.title)
                                Text(mood.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Text("HealthKitの「心の状態」にも記録されます")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func selectMood(_ mood: MoodItem) {
        let moodText = "\(mood.emoji) \(mood.label)"
        selectedMood = moodText
        onSelect(moodText)

        // Save to HealthKit
        if #available(iOS 18.0, *) {
            Task {
                let hkLabel = mapToHKLabel(mood.hkLabel)
                try? await HealthKitService.shared.saveStateOfMind(
                    valence: mood.valence,
                    labels: [hkLabel]
                )
                withAnimation { saved = true }
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            }
        } else {
            dismiss()
        }
    }

    @available(iOS 18.0, *)
    private func mapToHKLabel(_ name: String) -> HKStateOfMind.Label {
        switch name {
        case "happy": return .happy
        case "calm": return .calm
        case "indifferent": return .indifferent
        case "sad": return .sad
        case "irritated": return .irritated
        case "anxious": return .anxious
        case "excited": return .excited
        case "drained": return .drained
        case "confident": return .confident
        case "peaceful": return .peaceful
        default: return .indifferent
        }
    }
}

// MARK: - Quick Health Record Bar

struct QuickRecordBar: View {
    @State private var counts = HealthKitService.QuickRecordCounts()
    @State private var showCaffeineMenu = false
    @State private var showWaterMenu = false
    @State private var showHeadacheMenu = false
    @State private var feedbackItem: String?

    struct RecordItem: Identifiable {
        let id: String
        let emoji: String
        let label: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Caffeine
                    quickButton(emoji: "☕", label: caffeineLabel) {
                        showCaffeineMenu = true
                    }
                    .confirmationDialog("カフェイン量", isPresented: $showCaffeineMenu) {
                        Button("コーヒー (80mg)") { saveCaffeine(80) }
                        Button("濃いコーヒー (120mg)") { saveCaffeine(120) }
                        Button("お茶 (30mg)") { saveCaffeine(30) }
                        Button("エナジードリンク (150mg)") { saveCaffeine(150) }
                        Button("キャンセル", role: .cancel) {}
                    }

                    // Water
                    quickButton(emoji: "💧", label: waterLabel) {
                        showWaterMenu = true
                    }
                    .confirmationDialog("飲水量", isPresented: $showWaterMenu) {
                        Button("コップ1杯 (200ml)") { saveWater(200) }
                        Button("ペットボトル半分 (250ml)") { saveWater(250) }
                        Button("ペットボトル1本 (500ml)") { saveWater(500) }
                        Button("キャンセル", role: .cancel) {}
                    }

                    // Toothbrushing
                    quickButton(emoji: "🪥", label: toothLabel) {
                        saveToothbrushing()
                    }

                    // Handwashing
                    quickButton(emoji: "🧼", label: handwashLabel) {
                        saveHandwashing()
                    }

                    // Headache
                    quickButton(emoji: "🤕", label: headacheLabel) {
                        showHeadacheMenu = true
                    }
                    .confirmationDialog("頭痛の程度", isPresented: $showHeadacheMenu) {
                        Button("軽度") { saveHeadache(1) }
                        Button("中度") { saveHeadache(2) }
                        Button("重度") { saveHeadache(3) }
                        Button("キャンセル", role: .cancel) {}
                    }
                }
                .padding(.horizontal, 4)
            }

            // Feedback
            if let item = feedbackItem {
                Label("\(item) を記録しました", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .task { await refreshCounts() }
    }

    // MARK: - Labels with counts

    private var caffeineLabel: String {
        counts.caffeineMg > 0 ? "×\(Int(counts.caffeineMg))mg" : "カフェイン"
    }

    private var waterLabel: String {
        counts.waterMl > 0 ? "×\(Int(counts.waterMl))ml" : "飲水"
    }

    private var toothLabel: String {
        counts.toothbrushCount > 0 ? "×\(counts.toothbrushCount)" : "歯磨き"
    }

    private var handwashLabel: String {
        counts.handwashCount > 0 ? "×\(counts.handwashCount)" : "手洗い"
    }

    private var headacheLabel: String {
        counts.headacheCount > 0 ? "×\(counts.headacheCount)" : "頭痛"
    }

    // MARK: - Quick Button

    private func quickButton(emoji: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(emoji)
                    .font(.title3)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 48)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save Actions

    private func saveCaffeine(_ mg: Double) {
        Task {
            try? await HealthKitService.shared.saveCaffeine(mg: mg)
            showFeedback("☕ \(Int(mg))mg")
            await refreshCounts()
        }
    }

    private func saveWater(_ ml: Double) {
        Task {
            try? await HealthKitService.shared.saveWater(ml: ml)
            showFeedback("💧 \(Int(ml))ml")
            await refreshCounts()
        }
    }

    private func saveToothbrushing() {
        Task {
            try? await HealthKitService.shared.saveToothbrushing()
            showFeedback("🪥 歯磨き")
            await refreshCounts()
        }
    }

    private func saveHandwashing() {
        Task {
            try? await HealthKitService.shared.saveHandwashing()
            showFeedback("🧼 手洗い")
            await refreshCounts()
        }
    }

    private func saveHeadache(_ severity: Int) {
        let labels = ["", "軽度", "中度", "重度"]
        Task {
            try? await HealthKitService.shared.saveHeadache(severity: severity)
            showFeedback("🤕 頭痛(\(labels[severity]))")
            await refreshCounts()
        }
    }

    private func showFeedback(_ text: String) {
        withAnimation { feedbackItem = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { feedbackItem = nil }
        }
    }

    private func refreshCounts() async {
        counts = (try? await HealthKitService.shared.fetchTodayQuickRecordCounts()) ?? HealthKitService.QuickRecordCounts()
    }
}

#Preview {
    ContentView()
}
