import SwiftUI
import SafariServices

/// Registration flow shown when a Tier 0 (guest) user taps "Publish" on a blog.
/// Steps: ToS → Email → Code → Username → Done
struct RegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .terms
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var username = ""
    @State private var usernameAvailable: Bool?
    @State private var usernameReason: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showServiceToS = false
    @State private var tosAccepted = false

    var onRegistered: (() -> Void)?

    enum Step {
        case terms, email, code, username, done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Progress indicator
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            Capsule()
                                .fill(i <= stepIndex ? Color.purple : Color.gray.opacity(0.3))
                                .frame(height: 4)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()

                    switch step {
                    case .terms:
                        termsStep
                    case .email:
                        emailStep
                    case .code:
                        codeStep
                    case .username:
                        usernameStep
                    case .done:
                        doneStep
                    }

                    Spacer()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "registration_title", defaultValue: "ユーザー登録"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel", defaultValue: "キャンセル")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var stepIndex: Int {
        switch step {
        case .terms: 0
        case .email: 1
        case .code: 2
        case .username: 3
        case .done: 3
        }
    }

    // MARK: - Step 1: Terms

    private var termsStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text(String(localized: "reg_tos_title", defaultValue: "nehan.ai サービス利用規約"))
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(String(localized: "reg_tos_desc", defaultValue: "ブログを公開するには、nehan.aiサービス利用規約への同意が必要です。"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button {
                showServiceToS = true
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    Text(String(localized: "reg_read_tos", defaultValue: "利用規約を読む"))
                    Spacer()
                    Image(systemName: tosAccepted ? "checkmark.circle.fill" : "arrow.up.right")
                        .foregroundStyle(tosAccepted ? .green : .white.opacity(0.5))
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            actionButton(String(localized: "reg_agree_next", defaultValue: "同意して次へ"), enabled: tosAccepted) {
                withAnimation { step = .email }
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showServiceToS, onDismiss: { tosAccepted = true }) {
            SafariSheet(url: URL(string: "https://nehan.ai/terms/tos/ja")!)
        }
    }

    // MARK: - Step 2: Email

    private var emailStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text(String(localized: "reg_email_title", defaultValue: "メールアドレス"))
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(String(localized: "reg_email_desc", defaultValue: "認証コードを送信します"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            TextField("email@example.com", text: $email)
                .textFieldStyle(.plain)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)

            actionButton(String(localized: "reg_send_code", defaultValue: "認証コードを送信"), enabled: isValidEmail && !isLoading) {
                await sendCode()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Step 3: Code

    private var codeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text(String(localized: "reg_code_title", defaultValue: "認証コード"))
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(String(localized: "reg_code_desc", defaultValue: "\(email) に送信した6桁のコードを入力してください"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            TextField("000000", text: $verificationCode)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)

            actionButton(String(localized: "reg_verify", defaultValue: "認証する"), enabled: verificationCode.count == 6 && !isLoading) {
                await verifyCode()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Step 4: Username

    private var usernameStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text(String(localized: "reg_username_title", defaultValue: "ユーザー名"))
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(String(localized: "reg_username_desc", defaultValue: "nehan.ai/ユーザー名 があなたのブログURLになります"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            HStack {
                Text("nehan.ai/")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("username", text: $username)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    .foregroundStyle(.white)
                    .onChange(of: username) {
                        Task { await checkUsernameAvailability() }
                    }

                if let available = usernameAvailable {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(available ? .green : .red)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            if let reason = usernameReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            actionButton(String(localized: "reg_complete", defaultValue: "登録完了"), enabled: usernameAvailable == true && !isLoading) {
                await completeRegistration()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Step 5: Done

    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text(String(localized: "reg_done_title", defaultValue: "登録完了"))
                .font(.title.bold())
                .foregroundStyle(.white)

            Text(String(localized: "reg_done_desc", defaultValue: "nehan.ai/\(username) でブログが公開されます"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            actionButton(String(localized: "reg_start_publish", defaultValue: "ブログを公開する"), enabled: true) {
                onRegistered?()
                dismiss()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private var isValidEmail: Bool {
        email.contains("@") && email.contains(".")
    }

    private func actionButton(_ label: String, enabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if isLoading {
                    ProgressView().tint(.white)
                }
                Text(label)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(enabled ? Color.purple : Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(!enabled)
    }

    private func sendCode() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AuthService.shared.sendVerificationEmail(email)
            withAnimation { step = .code }
        } catch {
            errorMessage = String(localized: "reg_error_send", defaultValue: "送信に失敗しました。もう一度お試しください。")
        }
        isLoading = false
    }

    private func verifyCode() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AuthService.shared.confirmVerificationCode(verificationCode)
            withAnimation { step = .username }
        } catch {
            errorMessage = String(localized: "reg_error_code", defaultValue: "認証コードが正しくありません。")
        }
        isLoading = false
    }

    private func checkUsernameAvailability() async {
        let name = username.lowercased()
        guard name.count >= 3 else {
            usernameAvailable = nil
            usernameReason = nil
            return
        }

        do {
            let result = try await AuthService.shared.checkUsername(name)
            usernameAvailable = result.available
            usernameReason = result.reason
        } catch {
            usernameAvailable = nil
        }
    }

    private func completeRegistration() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AuthService.shared.upgrade(username: username.lowercased())
            withAnimation { step = .done }
        } catch {
            errorMessage = String(localized: "reg_error_upgrade", defaultValue: "登録に失敗しました。もう一度お試しください。")
        }
        isLoading = false
    }
}
