import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationService = LocationService.shared
    @State private var memoText = ""
    @State private var logCount = 0
    @State private var lastSyncStatus = "未同期"

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
                        Text("\(loc.coordinate.latitude, specifier: "%.4f"), \(loc.coordinate.longitude, specifier: "%.4f")")
                            .font(.caption)
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

#Preview {
    ContentView()
}
