import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationService = LocationService.shared
    @StateObject private var bookmarkStore = PlaceBookmarkStore.shared
    @State private var memoText = ""
    @State private var lastSyncStatus = "未同期"
    @State private var showingNameDialog = false
    @State private var newPlaceName = ""
    @State private var newPlaceIsSecret = false
    @State private var showingBookmarks = false

    var body: some View {
        NavigationStack {
            List {
                Section("ステータス") {
                    HStack {
                        Circle()
                            .fill(locationService.isTracking ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(locationService.isTracking ? "記録中" : "停止中")
                    }

                    if let loc = locationService.lastLocation {
                        let coord = loc.coordinate
                        let matched = bookmarkStore.match(latitude: coord.latitude, longitude: coord.longitude)

                        VStack(alignment: .leading, spacing: 4) {
                            if let matched {
                                Text(matched.name)
                                    .font(.subheadline)
                                    .bold()
                            }
                            if matched?.isSecret != true {
                                Text("\(coord.latitude, specifier: "%.4f"), \(coord.longitude, specifier: "%.4f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            if matched?.isSecret != true {
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
                                Label(matched != nil ? "名前を変更" : "この場所に名前をつける", systemImage: "mappin.and.ellipse")
                            }
                            if matched != nil {
                                Button(role: .destructive) {
                                    if let m = matched {
                                        bookmarkStore.remove(id: m.id)
                                    }
                                } label: {
                                    Label("ブックマーク削除", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Text("バッファ: \(SyncService.shared.pendingCount)件")
                    Text("同期: \(lastSyncStatus)")
                }

                Section("メモ") {
                    TextField("打合せメモ、やったこと等", text: $memoText, axis: .vertical)
                        .lineLimit(3...6)

                    Button("メモを記録") {
                        guard !memoText.isEmpty else { return }
                        let entry = LogEntry(type: .memo, payload: memoText)
                        SyncService.shared.addEntry(entry)
                        memoText = ""
                    }
                    .disabled(memoText.isEmpty)
                }

                Section("操作") {
                    Button("今すぐ同期") {
                        Task {
                            await SyncService.shared.sync()
                            lastSyncStatus = "\(Date().formatted(date: .omitted, time: .shortened))"
                        }
                    }

                    Button("睡眠データ取得") {
                        Task {
                            do {
                                if let entry = try await HealthKitService.shared.fetchSleepData(for: Date()) {
                                    SyncService.shared.addEntry(entry)
                                    lastSyncStatus = "睡眠データ追加"
                                }
                            } catch {
                                lastSyncStatus = "Error: \(error.localizedDescription)"
                            }
                        }
                    }

                    Button("ブックマーク一覧") {
                        showingBookmarks = true
                    }
                }
            }
            .navigationTitle("nehan.ai")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(locationService.isTracking ? "停止" : "開始") {
                        if locationService.isTracking {
                            locationService.stopTracking()
                        } else {
                            locationService.requestPermission()
                            locationService.startTracking()
                        }
                    }
                }
            }
            .alert("場所に名前をつける", isPresented: $showingNameDialog) {
                TextField("名前 (例: 自宅, オフィス)", text: $newPlaceName)
                Toggle("秘密 (座標を送信しない)", isOn: $newPlaceIsSecret)
                Button("保存") {
                    guard let loc = locationService.lastLocation, !newPlaceName.isEmpty else { return }
                    let coord = loc.coordinate
                    if let existing = bookmarkStore.match(latitude: coord.latitude, longitude: coord.longitude) {
                        var updated = existing
                        updated.name = newPlaceName
                        updated.isSecret = newPlaceIsSecret
                        bookmarkStore.update(updated)
                    } else {
                        let bookmark = PlaceBookmark(
                            name: newPlaceName,
                            latitude: coord.latitude,
                            longitude: coord.longitude,
                            isSecret: newPlaceIsSecret
                        )
                        bookmarkStore.add(bookmark)
                    }
                    newPlaceName = ""
                    newPlaceIsSecret = false
                }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(isPresented: $showingBookmarks) {
                BookmarkListView(store: bookmarkStore)
            }
        }
        .onAppear {
            setupServices()
        }
    }

    private func setupServices() {
        locationService.onNewLocation = { entry in
            SyncService.shared.addEntry(entry)
        }

        Task {
            try? await HealthKitService.shared.requestPermission()
        }

        locationService.requestPermission()
        locationService.startTracking()
    }
}

struct BookmarkListView: View {
    @ObservedObject var store: PlaceBookmarkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.bookmarks.isEmpty {
                    Text("ブックマークなし")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.bookmarks) { bookmark in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(bookmark.name)
                                    .font(.headline)
                                if bookmark.isSecret {
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            if !bookmark.isSecret {
                                Text("\(bookmark.latitude, specifier: "%.4f"), \(bookmark.longitude, specifier: "%.4f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indices in
                        for i in indices {
                            store.remove(id: store.bookmarks[i].id)
                        }
                    }
                }
            }
            .navigationTitle("ブックマーク")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
