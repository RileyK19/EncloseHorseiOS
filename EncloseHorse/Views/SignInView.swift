//
//  SignInView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/3/26.
//

import AuthenticationServices
import SwiftUI
import Combine
import GoogleSignIn

// MARK: - Sign In / Guest entry screen
struct SignInView: View {
    @ObservedObject var auth = AuthManager.shared
    @Environment(\.colorScheme) var colorScheme

    /// Show the username picker after choosing guest
    @State private var showUsernameSetup = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon
            VStack(spacing: 12) {
                Text("🐴")
                    .font(.system(size: 80))
                Text("EncloseHorse")
                    .font(.largeTitle.bold())
                Text("Daily puzzle. Fence in the horse.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 14) {
                // Apple Sign In
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                        Task { await AuthManager.shared.signInWithApple(credential: cred) }
                    case .failure(let err):
                        print("Apple sign in error: \(err)")
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .cornerRadius(10)
                
                // Google
                Button {
                    handleGoogleSignIn()
                } label: {
                    HStack {
                        Image("GoogleLogo")
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text("Sign In with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .foregroundStyle(.black)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(.systemGray4), lineWidth: 1)
                    )
                }
                
                // Divider
                HStack {
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                    Text("or").font(.footnote).foregroundStyle(.secondary)
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                }

                // Guest button
                Button {
                    showUsernameSetup = true
                } label: {
                    HStack {
                        Image(systemName: "person.fill")
                        Text("Continue as Guest")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(.systemGray4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Text("Guest accounts appear on leaderboards but aren't linked to your Apple ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if auth.isLoading {
                    ProgressView()
                }

                if let err = auth.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .sheet(isPresented: $showUsernameSetup) {
            UsernameSetupView(isPresented: $showUsernameSetup, isGuest: true)
        }
    }
    
    func handleGoogleSignIn() {
        print("🔵 Google Sign In button tapped")
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            print("❌ No root VC")
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                print("❌ Google sign in error: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                print("❌ No user or token")
                return
            }
            
            print("✅ Got Google token: \(idToken.prefix(50))...")
            
            Task {
                print("🔵 Calling signInWithGoogle...")
                await AuthManager.shared.signInWithGoogle(idToken: idToken)
                print("🔵 signInWithGoogle completed")
            }
        }
    }
}

// MARK: - Username Setup (used for both guest flow and post-Apple-sign-in)
struct UsernameSetupView: View {
    @Binding var isPresented: Bool
    var isGuest: Bool = false

    @State private var draft = ""
    @State private var checkState: CheckState = .idle
    @FocusState private var focused: Bool

    // Debounce timer
    @State private var debounceTask: Task<Void, Never>?

    enum CheckState {
        case idle
        case checking
        case available
        case taken
        case error
    }

    private var isClean: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSubmit: Bool {
        isClean && checkState == .available
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Choose a username")
                    .font(.title2.bold())

                Text("This shows on the leaderboard.\nYou can't change it later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Text field + status indicator
                HStack(spacing: 8) {
                    TextField("Username", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onChange(of: draft) { _, newValue in
                            scheduleCheck(for: newValue)
                        }

                    statusIcon
                        .frame(width: 24)
                }
                .padding(.horizontal)

                // Status message
                statusMessage
                    .font(.caption)
                    .frame(height: 16)

                Button("Set Username") {
                    commitUsername()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Spacer()
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isGuest {
                    // Non-guest can skip (they signed in with Apple already)
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { isPresented = false }
                    }
                }
            }
            .onAppear { focused = true }
        }
        .interactiveDismissDisabled(isGuest) // guests must pick a username or close the sheet
    }

    // MARK: - Status views

    @ViewBuilder
    private var statusIcon: some View {
        switch checkState {
        case .idle:      Color.clear
        case .checking:  ProgressView().scaleEffect(0.7)
        case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .taken:     Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .error:     Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch checkState {
        case .idle:      Text("").foregroundStyle(.secondary)
        case .checking:  Text("Checking availability…").foregroundStyle(.secondary)
        case .available: Text(isGuest ? "✓ Looks good!" : "✓ Available!").foregroundStyle(.green)
        case .taken:     Text("That username is already taken.").foregroundStyle(.red)
        case .error:     Text("Couldn't check — try again.").foregroundStyle(.orange)
        }
    }

    // MARK: - Debounced availability check

    private func scheduleCheck(for value: String) {
        debounceTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            checkState = .idle
            return
        }

        checkState = .checking
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await runCheck(trimmed)
        }
    }

    private func runCheck(_ username: String) async {
        if UsernameManager.shared.username == username {
            checkState = .available
            return
        }
        let userId = AuthManager.shared.session?.userId
        let available = await SupabaseClient.checkUsernameAvailable(username, userId: userId)
        checkState = available ? .available : .taken
    }

    // MARK: - Commit

    private func commitUsername() {
        let clean = draft.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        if isGuest {
            UsernameManager.shared.setGuestUsername(clean)
        } else {
            UsernameManager.shared.setAppleUsername(clean)
        }
        isPresented = false
        AuthManager.shared.objectWillChange.send()
    }
}
