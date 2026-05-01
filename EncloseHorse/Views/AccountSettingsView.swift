//
//  AccountSettingsView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/14/26.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import SwiftData

struct AccountSettingsView: View {
    @ObservedObject var authManager = AuthManager.shared
    @State private var showMigrationSuccess = false
    @State private var showMigrationError = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            // Account Status Section
            Section {
                HStack {
                    Image(systemName: authManager.currentProvider == .guest ? "person.circle" :
                          authManager.currentProvider == .google ? "GoogleLogo" : "applelogo")
                        .foregroundColor(authManager.currentProvider == .guest ? .orange :
                                         authManager.currentProvider == .google ? .blue : .black)
                    
                    VStack(alignment: .leading) {
                        Text("Account Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(authManager.currentProvider == .guest ? "Guest" :
                             authManager.currentProvider == .google ? "Google" : "Apple ID")
                            .font(.headline)
                    }
                }
                
                if let username = UsernameManager.shared.username {
                    HStack {
                        Image(systemName: "person.fill")
                        VStack(alignment: .leading) {
                            Text("Username")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(username)
                                .font(.headline)
                        }
                    }
                }
            } header: {
                Text("Account Info")
            }
            
            // Migration Section (only for guests)
            if UsernameManager.shared.isGuest {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Your progress is not backed up")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        Text("If you delete the app or sign out, you'll lose all your data. Sign in with Apple to protect your progress.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    
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
                    .buttonStyle(.plain)
                    
                } header: {
                    Text("Backup Your Progress")
                } footer: {
                    Text("All your gems, items, and progress will be preserved.")
                }
            }
            
            // Sign Out Section
            if authManager.isSignedIn {
                Section {
                    Button(role: .destructive, action: handleSignOut) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                    }
                } footer: {
                    if UsernameManager.shared.isGuest {
                        Text("⚠️ Signing out as a guest will permanently delete all your progress.")
                            .foregroundColor(.red)
                    } else {
                        Text("You can sign back in anytime to restore your progress.")
                    }
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Migration Successful! 🎉", isPresented: $showMigrationSuccess) {
            Button("OK") { }
        } message: {
            Text("Your progress is now safely backed up with Apple Sign In. You can reinstall the app anytime without losing data.")
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
    
    // MARK: - Handle Sign Out
    private func handleSignOut() {
        let isGuest = UsernameManager.shared.isGuest
        
        if isGuest {
            print("⚠️ Guest signing out - data will be lost")
        }
        
        authManager.signOut()
        UsernameManager.shared.clear()
        GachaManager.shared.resetAll()
        
        // Clear local puzzle history
        let descriptor = FetchDescriptor<DailyPuzzle>()
        if let puzzles = try? modelContext.fetch(descriptor) {
            print("🗑️ Deleting \(puzzles.count) local puzzles")

            for puzzle in puzzles {
                modelContext.delete(puzzle)
            }
            try? modelContext.save()
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

#Preview {
    NavigationStack {
        AccountSettingsView()
    }
}
