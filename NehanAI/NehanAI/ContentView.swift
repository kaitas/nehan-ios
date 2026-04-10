import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationService = LocationService.shared
    @StateObject private var bookmarkStore = PlaceBookmarkStore.shared
    @State private var profileStore = UserProfileStore.shared
    @State private var lastSyncTime: Date?
    @State private var lastHealthTime: Date?
    @State private var sleepSummary: HealthKitService.SleepSummary?
    @State private var stepCount: Int = 0
    @State private var heartRate: HealthKitService.HeartRateSummary?
    @State private var showingNameDialog = false
    @State private var newPlaceName = ""
    @State private var newPlaceIsSecret = false
    @State private var showingBookmarks = false
    @State private var blogEntry = BlogEntry()
    @State private var isGeneratingBlog = false
    @State private var showBlogEditor = false
    @State private var currentWeather: String?
    @State private var showStreakHelp = false
    @State private var menstrualSummary: HealthKitService.MenstrualSummary?
    @State private var appState = AppState.shared

    private static let hmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                headerSection
                statusSection
                timelineSection
                blogSection
                syncSection
            }
            .refreshable { await pullToRefresh() }
            .navigationTitle("nehan.ai")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    headerTrailing
                }
            }
            .sheet(isPresented: $showingNameDialog) {
                CoordMemoEditSheet(
                    name: $newPlaceName,
                    isSecret: $newPlaceIsSecret,
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
                        Task {
                            try? await BlogPublishService.publish(entry: blogEntry)
                            profileStore.recordBlogPost()
                            NotificationService.cancelBlogReminder()
                        }
                    },
                    isPublished: isTodayBlogPublished
                )
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .onAppear { setupServices() }
        .onChange(of: appState.shouldOpenBlogEditor) { _, shouldOpen in
            if shouldOpen {
                showBlogEditor = true
                appState.shouldOpenBlogEditor = false
            }
        }
    }

    // MARK: - Header (context message + expression + streak)

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                // Expression (Image Playground when available)
                if #available(iOS 18.0, *) {
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

    @ViewBuilder
    private var headerTrailing: some View {
        EmptyView()
    }

    /// Generate context-aware message based on time, location, health data
    private var contextMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let loc = locationService.lastLocation
        let matched = loc.flatMap { bookmarkStore.match(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        let place = matched?.name

        // Time-based greeting
        switch hour {
        case 5..<10:
            if let sleep = sleepSummary, sleep.totalMinutes > 360 {
                return "おはようございます、よく眠れましたね"
            }
            return "おはようございます"
        case 10..<12:
            if stepCount > 3000 {
                return "午前中から\(stepCount.formatted())歩、いい調子です！"
            }
            return "良い午前を過ごしていますね"
        case 12..<14:
            return "お昼ですね。少し休憩しましょう"
        case 14..<18:
            if let p = place {
                return "\(p)でお仕事中ですね"
            }
            return "午後もがんばっていますね"
        case 18..<21:
            if stepCount > 6000 {
                return "今日は\(stepCount.formatted())歩！よく動きました"
            }
            return "お疲れさまでした"
        case 21..<24:
            if let p = place {
                return "こんな時間まで\(p)ですか、元気ですね！"
            }
            return "そろそろ休みましょう"
        default:
            if let sleep = sleepSummary, sleep.totalMinutes < 300 {
                return "睡眠が少なめです、早めに休みましょう"
            }
            return "夜更かし中ですか？"
        }
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
                    Text("\(SyncService.shared.pendingCount)件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
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
                    gpsAccuracyView(accuracy: loc.horizontalAccuracy)

                    if let matched {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(matched.name)
                                .font(.subheadline)
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

    // MARK: - Timeline (ライフログ)

    private var timelineSection: some View {
        Section {
            // 288-cell timeline (00:00-23:55, 5min each)
            TimelineBarView(
                sleepSummary: sleepSummary,
                stepCount: stepCount,
                heartRate: heartRate
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
                if let hr = heartRate {
                    Label("\(hr.average)", systemImage: "heart")
                        .font(.caption)
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
        } header: {
            HStack {
                Text("ブログ")
                Spacer()
                if isTodayBlogPublished {
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

            var entry = BlogEntry()

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

            // Field 1: Sleep info
            if let sleep = sleepSummary {
                let h = sleep.totalMinutes / 60
                let m = sleep.totalMinutes % 60
                var sleepText = "睡眠 \(h)h\(m > 0 ? "\(m)m" : "")"
                if let asleep = sleep.asleep, let awake = sleep.awake {
                    sleepText += "（\(asleep.formatted(date: .omitted, time: .shortened))→\(awake.formatted(date: .omitted, time: .shortened))）"
                }
                sleepText += " deep:\(sleep.deepMinutes)m rem:\(sleep.remMinutes)m"
                entry.sleepInfo = sleepText
            }

            // Field 2: Dream diary (keep existing if user already typed)
            entry.dreamDiary = blogEntry.dreamDiary

            // Field 3: Places visited
            if let loc = locationService.lastLocation {
                let matched = bookmarkStore.match(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                if let name = matched?.name {
                    entry.placesVisited = name
                }
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
            bookmarkStore.update(updated)
        } else {
            bookmarkStore.add(PlaceBookmark(
                name: newPlaceName,
                latitude: coord.latitude,
                longitude: coord.longitude,
                isSecret: newPlaceIsSecret
            ))
        }
        newPlaceName = ""
        newPlaceIsSecret = false
    }

    private func setupServices() {
        locationService.onNewLocation = { entry in
            SyncService.shared.addEntry(entry)
        }
        Task {
            try? await HealthKitService.shared.requestPermission()
            await refreshHealthData()
            lastHealthTime = Date()
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
    }

    private func refreshHealthData() async {
        let today = Date()
        let hk = HealthKitService.shared
        sleepSummary = try? await hk.fetchSleepSummary(for: today)
        stepCount = (try? await hk.fetchStepCount(for: today)) ?? 0
        heartRate = try? await hk.fetchHeartRateSummary(for: today)
        if UserProfileStore.shared.isFemale {
            menstrualSummary = try? await hk.fetchMenstrualSummary(for: today)
        }
    }
}

// MARK: - Timeline Bar View (288 cells = 24h x 12 per hour)

struct TimelineBarView: View {
    let sleepSummary: HealthKitService.SleepSummary?
    let stepCount: Int
    let heartRate: HealthKitService.HeartRateSummary?

    private let cellCount = 288 // 24h * 12 (5min each)

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

            // Timeline cells
            GeometryReader { geo in
                let cellWidth = geo.size.width / CGFloat(cellCount)
                HStack(spacing: 0) {
                    ForEach(0..<cellCount, id: \.self) { index in
                        Rectangle()
                            .fill(cellColor(for: index))
                            .frame(width: max(cellWidth, 0.5), height: 16)
                    }
                }
            }
            .frame(height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Legend
            HStack(spacing: 12) {
                legendItem(color: .purple.opacity(0.7), label: "睡眠")
                legendItem(color: .blue.opacity(0.7), label: "活動")
                legendItem(color: .yellow.opacity(0.5), label: "静止")
                legendItem(color: .secondary.opacity(0.15), label: "未記録")
            }
            .font(.system(size: 9))
        }
    }

    private func cellColor(for index: Int) -> Color {
        let hour = index / 12

        // Sleep time estimation
        if let sleep = sleepSummary, let asleep = sleep.asleep, let awake = sleep.awake {
            let cal = Calendar.current
            let sleepHour = cal.component(.hour, from: asleep)
            let sleepMin = cal.component(.minute, from: asleep)
            let wakeHour = cal.component(.hour, from: awake)
            let wakeMin = cal.component(.minute, from: awake)

            let sleepIndex = sleepHour * 12 + sleepMin / 5
            let wakeIndex = wakeHour * 12 + wakeMin / 5

            if sleepIndex > wakeIndex {
                // Overnight sleep
                if index >= sleepIndex || index < wakeIndex {
                    return .purple.opacity(0.7)
                }
            } else {
                if index >= sleepIndex && index < wakeIndex {
                    return .purple.opacity(0.7)
                }
            }
        }

        // Current time marker
        let now = Calendar.current
        let currentIndex = now.component(.hour, from: Date()) * 12 + now.component(.minute, from: Date()) / 5
        if index > currentIndex {
            return .secondary.opacity(0.08) // future
        }

        // Approximate: daytime with steps = active
        if stepCount > 0 && hour >= 7 && hour <= 22 {
            return .blue.opacity(0.5)
        }

        if hour >= 7 && hour <= 22 {
            return .yellow.opacity(0.3) // stationary
        }

        return .secondary.opacity(0.15) // no data
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Coordinate Memo Edit Sheet (Glass)

struct CoordMemoEditSheet: View {
    @Binding var name: String
    @Binding var isSecret: Bool
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("名前 (例: 自宅, オフィス)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)

                Toggle(isOn: $isSecret) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("秘密", systemImage: "lock.fill")
                            .font(.subheadline)
                        Text("座標を記録せずに \"Unknown\" としてクラウドに保存")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.orange)

                Button(action: onSave) {
                    Text("保存")
                        .frame(maxWidth: .infinity)
                        .glassEffect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("座標メモ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
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
                    onSave: {
                        if var bm = editingBookmark {
                            bm.name = editName
                            bm.isSecret = editIsSecret
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
            HStack {
                Text(bookmark.name)
                    .font(.headline)
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

#Preview {
    ContentView()
}
