//
//  GuestAlertView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/14/26.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct GuestAlertView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var authManager = AuthManager.shared
    @State private var showMigrationSuccess = false
    @State private var showMigrationError = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            // Title
            Text("Protect Your Progress")
                .font(.title2)
                .fontWeight(.bold)
            
            // Message
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("You're currently playing as a **guest**")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "person.circle")
                        .foregroundColor(.orange)
                }
                
                Text("This means:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                Text("  • Your progress stays on this device only")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("  • Reinstalling the app will reset everything")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("  • Your username isn't claimed permanently")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Divider()
                    .padding(.vertical, 4)
                
                Label {
                    Text("Sign in to back up your progress and claim your username")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Buttons
            VStack(spacing: 12) {
                SignInWithAppleButton(.signUp) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    handleMigrationSignIn(result: result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                
                Button {
                    handleGoogleSignIn()
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
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
                
                Button(action: { dismiss() }) {
                    Text("Maybe Later")
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .alert("Migration Successful! 🎉", isPresented: $showMigrationSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your progress is now safely backed up with Apple Sign In. You can reinstall the app anytime without losing data!")
        }
        .alert("Migration Failed", isPresented: $showMigrationError) {
            Button("OK") { }
        } message: {
            Text(authManager.error ?? "Unknown error occurred")
        }
        .overlay {
            if authManager.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
    }
    
    // MARK: - Handle Migration Sign In
    private func handleMigrationSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                return
            }
            
            Task {
                let success = await authManager.migrateGuestToApple(credential: credential)
                if success {
                    showMigrationSuccess = true
                } else {
                    showMigrationError = true
                }
            }
            
        case .failure(let error):
            print("Migration sign in failed: \(error.localizedDescription)")
        }
    }
    
    func handleGoogleSignIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                print("Google sign in failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            
            Task {
                await AuthManager.shared.signInWithGoogle(idToken: idToken)
            }
        }
    }
}

// MARK: - Modifier to show alert on app launch for guests
struct GuestAlertModifier: ViewModifier {
    @ObservedObject var authManager = AuthManager.shared
    @State private var showAlert = false
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAlert) {
                GuestAlertView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                checkAndShowAlert()
            }
    }
    
    private func checkAndShowAlert() {
        if UsernameManager.shared.isGuest &&
            authManager.session == nil &&
            UsernameManager.shared.hasUsername {  // ← Add this
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showAlert = true
            }
        }
    }
}

extension View {
    func guestAlert() -> some View {
        modifier(GuestAlertModifier())
    }
}
