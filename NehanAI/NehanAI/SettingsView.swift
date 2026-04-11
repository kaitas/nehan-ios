import SwiftUI

/// Account management settings — shows user info, tier status, and account deletion
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var profileStore = UserProfileStore.shared

    var body: some View {
        NavigationStack {
            List {
                // Account info
                Section {
                    if let user = AuthService.shared.currentUser {
                        LabeledContent(String(localized: "settings_user_id", defaultValue: "ユーザーID")) {
                            Text("\(user.id)")
                        }
                        LabeledContent(String(localized: "settings_username", defaultValue: "ユーザー名")) {
                            Text(user.username ?? String(localized: "settings_guest", defaultValue: "ゲスト"))
                        }
                        LabeledContent(String(localized: "settings_tier", defaultValue: "プラン")) {
                            Text(user.tier >= 1
                                 ? String(localized: "settings_registered", defaultValue: "登録済み")
                                 : String(localized: "settings_guest_tier", defaultValue: "ゲスト"))
                        }
                        if let email = user.email {
                            LabeledContent(String(localized: "settings_email", defaultValue: "メール")) {
                                HStack {
                                    Text(email)
                                    if user.email_verified_at != nil {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    } else {
                        Text(String(localized: "settings_not_logged_in", defaultValue: "未ログイン"))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "settings_account_section", defaultValue: "アカウント"))
                }

                // Legal
                Section {
                    Link(destination: URL(string: "\(AppConfig.workerURL)/terms/tos/ja")!) {
                        Label(String(localized: "settings_tos", defaultValue: "利用規約"), systemImage: "doc.text")
                    }
                    Link(destination: URL(string: "\(AppConfig.workerURL)/terms/privacy/ja")!) {
                        Label(String(localized: "settings_privacy", defaultValue: "プライバシーポリシー"), systemImage: "lock.shield")
                    }
                    Link(destination: URL(string: "\(AppConfig.workerURL)/terms/ios-tos/ja")!) {
                        Label(String(localized: "settings_ios_tos", defaultValue: "iOSアプリ利用規約"), systemImage: "iphone")
                    }
                } header: {
                    Text(String(localized: "settings_legal_section", defaultValue: "法的情報"))
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(String(localized: "settings_delete_account", defaultValue: "アカウントを削除"), systemImage: "trash")
                    }
                    .disabled(isDeleting)
                } header: {
                    Text(String(localized: "settings_danger_section", defaultValue: "アカウント管理"))
                } footer: {
                    Text(String(localized: "settings_delete_warning", defaultValue: "アカウントを削除すると、すべてのブログ・ログデータが完全に削除されます。この操作は取り消せません。"))
                }
            }
            .navigationTitle(String(localized: "settings_title", defaultValue: "設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "close", defaultValue: "閉じる")) {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                String(localized: "settings_delete_confirm_title", defaultValue: "アカウントを削除しますか？"),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "settings_delete_confirm_action", defaultValue: "削除する"), role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button(String(localized: "cancel", defaultValue: "キャンセル"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings_delete_confirm_message", defaultValue: "すべてのデータ（ブログ・ログ・カバー画像）が削除されます。30日以内に完全削除されます。"))
            }
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        do {
            try await AuthService.shared.deleteAccount()

            // Clear local data
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            profileStore.profile = .default

            dismiss()
        } catch {
            print("[nehan] Account deletion failed: \(error)")
        }
        isDeleting = false
    }
}
