import SwiftUI
import SafariServices

struct OnboardingView: View {
    @Bindable var profileStore: UserProfileStore
    @State private var currentPage = 0
    @State private var selectedBirthYear = 2000
    @State private var selectedBirthMonth = 1
    @State private var selectedBirthDay = 1
    @State private var selectedSex: UserProfile.BiologicalSex = .preferNotToSay
    @State private var selectedLanguage: UserProfile.AppLanguage = .ja
    @State private var showTermsWeb = false
    @State private var showPrivacyWeb = false
    @State private var termsRead = false
    @State private var privacyRead = false
    @State private var recordPlaceNames = true

    private let currentYear = Calendar.current.component(.year, from: Date())

    private var bothRead: Bool { termsRead && privacyRead }

    var body: some View {
        ZStack {
            // Glass UI background
            Color.black.ignoresSafeArea()
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .frame(width: 400, height: 400)
                .foregroundStyle(.ultraThinMaterial)
                .blur(radius: 80)
                .offset(y: -100)

            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                languagePage.tag(1)
                profilePage.tag(2)
                termsPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("N")
                .font(.system(size: 100, weight: .bold))
                .foregroundStyle(.white)

            Text("nehan.ai")
                .font(.title)
                .foregroundStyle(.white)

            Text(String(localized: "onboarding_tagline", defaultValue: "あなたのiPhoneヘルスケアが、\nそのまま日記になる"))
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal)

            Spacer()

            glassButton(String(localized: "onboarding_start", defaultValue: "はじめる")) {
                withAnimation { currentPage = 1 }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 2: Language

    private var languagePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(String(localized: "onboarding_language_title", defaultValue: "言語 / Language"))
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                ForEach(UserProfile.AppLanguage.allCases) { lang in
                    Button {
                        selectedLanguage = lang
                    } label: {
                        HStack {
                            Text(lang.flag).font(.title2)
                            Text(lang.displayName).font(.body)
                            Spacer()
                            if selectedLanguage == lang {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(selectedLanguage == lang ? .white.opacity(0.4) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            glassButton(String(localized: "onboarding_next", defaultValue: "次へ")) {
                withAnimation { currentPage = 2 }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 3: Profile

    private var profilePage: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 32)

                Text(String(localized: "onboarding_profile_title", defaultValue: "プロフィール"))
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(String(localized: "onboarding_profile_desc", defaultValue: "年齢認証、ヘルスケアデータの分析と\n誕生日サプライズに使用します"))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))

                // Birthday (year / month / day combined)
                glassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "onboarding_birthday", defaultValue: "誕生日"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))

                        HStack(spacing: 0) {
                            Picker("", selection: $selectedBirthYear) {
                                ForEach((1930...currentYear - 10).reversed(), id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 90)

                            Picker("", selection: $selectedBirthMonth) {
                                ForEach(1...12, id: \.self) { m in
                                    Text("\(m)月").tag(m)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 90)

                            Picker("", selection: $selectedBirthDay) {
                                ForEach(1...31, id: \.self) { d in
                                    Text("\(d)日").tag(d)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 90)
                        }
                    }
                }

                // Biological sex
                glassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "onboarding_sex", defaultValue: "性別"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))

                        HStack(spacing: 8) {
                            ForEach(UserProfile.BiologicalSex.allCases) { sex in
                                Button {
                                    selectedSex = sex
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(sex.emoji).font(.title2)
                                        Text(sex.displayName).font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(selectedSex == sex ? .white.opacity(0.5) : .clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                            }
                        }

                        if selectedSex == .female {
                            Text(String(localized: "onboarding_female_note", defaultValue: "生理周期の記録機能が有効になります"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }

                glassButton(String(localized: "onboarding_next", defaultValue: "次へ")) {
                    withAnimation { currentPage = 3 }
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 32)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Page 4: Terms

    private var termsPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text(String(localized: "onboarding_terms_title", defaultValue: "利用規約"))
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                termsCardButton(
                    icon: "doc.text",
                    title: String(localized: "onboarding_terms_link", defaultValue: "利用規約を読む"),
                    isRead: termsRead
                ) {
                    showTermsWeb = true
                }

                termsCardButton(
                    icon: "lock.shield",
                    title: String(localized: "onboarding_privacy_link", defaultValue: "プライバシーポリシーを読む"),
                    isRead: privacyRead
                ) {
                    showPrivacyWeb = true
                }
            }
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                summaryRow("location.fill", String(localized: "onboarding_data_location", defaultValue: "位置情報を記録します"))
                summaryRow("heart.fill", String(localized: "onboarding_data_health", defaultValue: "HealthKitデータを記録します"))
                summaryRow("icloud.and.arrow.up", String(localized: "onboarding_data_sync", defaultValue: "データをサーバーに同期します"))
                summaryRow("hand.raised.fill", String(localized: "onboarding_data_noshare", defaultValue: "第三者にデータを提供しません"))
            }
            .padding(.horizontal, 32)

            if !bothRead {
                Text(String(localized: "onboarding_read_both", defaultValue: "利用規約とプライバシーポリシーを確認してください"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Button {
                profileStore.profile.birthYear = selectedBirthYear
                profileStore.profile.birthMonth = selectedBirthMonth
                profileStore.profile.birthDay = selectedBirthDay
                profileStore.profile.biologicalSex = selectedSex
                profileStore.profile.language = selectedLanguage
                profileStore.profile.recordPlaceNames = recordPlaceNames
                profileStore.profile.termsRead = true
                profileStore.profile.privacyRead = true
                profileStore.completeOnboarding()
            } label: {
                Text(String(localized: "onboarding_agree_start", defaultValue: "同意してはじめる"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(bothRead ? .white : .white.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(bothRead ? .black : .white.opacity(0.4))
            }
            .disabled(!bothRead)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showTermsWeb, onDismiss: { termsRead = true }) {
            SafariSheet(url: URL(string: "\(AppConfig.workerURL)/terms")!)
        }
        .sheet(isPresented: $showPrivacyWeb, onDismiss: { privacyRead = true }) {
            SafariSheet(url: URL(string: "\(AppConfig.workerURL)/privacy")!)
        }
    }

    // MARK: - Glass UI Components

    private func glassButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                )
                .foregroundStyle(.white)
        }
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func termsCardButton(icon: String, title: String, isRead: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                Spacer()
                if isRead {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isRead ? .green.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func summaryRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Safari Sheet

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview {
    OnboardingView(profileStore: UserProfileStore.shared)
}
