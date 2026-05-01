//
//  AuthManager.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/3/26.
//

import AuthenticationServices
import Combine
import Foundation

// MARK: - Supabase session
struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
}

// MARK: - Auth provider enum (for future expansion)
enum AuthProvider: String, Codable {
    case apple
    case google
    case guest
}

// MARK: - Auth errors
enum AuthError: Error {
    case missingToken
    case supabaseExchangeFailed
    case migrationFailed
    case unknown
}

// MARK: - Auth manager (singleton)
@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var session: SupabaseSession?
    @Published var isLoading = false
    @Published var error: String?

    private let sessionKey       = "supabase_session"
    private let supabaseAuthURL  = Constants.supabaseURL
    private let supabaseAnonKey  = Constants.supabaseKey

    var isSignedIn: Bool {
        session != nil || UsernameManager.shared.username != nil
    }
    
    var currentProvider: AuthProvider {
        if session == nil { return .guest }
        let stored = UserDefaults.standard.string(forKey: "authProvider")
        return stored == "google" ? .google : .apple
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let saved = try? JSONDecoder().decode(SupabaseSession.self, from: data) {
            self.session = saved
        }
    }

    // MARK: - Sign in with Apple
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        isLoading = true
        error = nil

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            error = "Missing identity token"
            isLoading = false
            return
        }

        do {
            let session = try await exchangeWithSupabase(identityToken: identityToken)

            // Restore username on reinstall
            if !UsernameManager.shared.hasUsername {
                if let existing = await SupabaseClient.fetchUsernameForUser(userId: session.userId) {
                    UsernameManager.shared.setAppleUsername(existing)
                }
            }
            
            self.session = session
            persist(session)

            // Restore gems + collection
            await GachaManager.shared.restoreFromSupabase()
        } catch {
            self.error = "Sign in failed: \(error.localizedDescription)"
        }

        UserDefaults.standard.set("apple", forKey: "authProvider")

        isLoading = false
    }

    // MARK: - Guest to Apple Migration
    /// Migrates a guest user to Apple Sign In, preserving their local data
    func migrateGuestToApple(credential: ASAuthorizationAppleIDCredential) async -> Bool {
        isLoading = true
        error = nil
        
        guard UsernameManager.shared.isGuest else {
            error = "Not a guest user"
            isLoading = false
            return false
        }
        
        // Store guest data before migration
        let guestUsername = UsernameManager.shared.username
        let guestGems = GachaManager.shared.gems
        let guestCollection = GachaManager.shared.collection
        let guestActiveAnimal = GachaManager.shared.activeAnimalID
        
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            error = "Missing identity token"
            isLoading = false
            return false
        }

        do {
            // Exchange Apple token for Supabase session
            let session = try await exchangeWithSupabase(identityToken: identityToken)
            self.session = session
            persist(session)
            
            // Check if this Apple ID already has a username claimed
            if let existing = await SupabaseClient.fetchUsernameForUser(userId: session.userId) {
                // Apple ID already has an account - restore that data
                UsernameManager.shared.setAppleUsername(existing)
                await GachaManager.shared.restoreFromSupabase()
                print("✅ Restored existing Apple ID account: \(existing)")
            } else {
                // New Apple ID - claim the guest username and upload guest data
                if let guestName = guestUsername {
                    UsernameManager.shared.setAppleUsername(guestName)
                    
                    // Upload guest data to Supabase (claims username + saves progress)
                    await SupabaseClient.upsertUserData(
                        userId: session.userId,
                        username: guestName,
                        gems: guestGems,
                        collection: guestCollection,
                        activeAnimal: guestActiveAnimal
                    )
                    
                    // CRITICAL: Link all guest scores (user_id = null) to this Apple account
                    await SupabaseClient.migrateGuestScores(
                        username: guestName,
                        newUserId: session.userId
                    )
                    
                    print("✅ Guest migration successful: \(guestName) → Apple ID (username + scores claimed)")
                }
            }
            
            isLoading = false
            return true
            
        } catch {
            self.error = "Migration failed: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
    
    // MARK: - Sign in with Google
    func signInWithGoogle(idToken: String) async {
        isLoading = true
        error = nil
        
        do {
            // Get session but don't set it yet
            let session = try await exchangeWithSupabaseGoogle(idToken: idToken)

            // Restore username FIRST
            if let existing = await SupabaseClient.fetchUsernameForUser(userId: session.userId) {
                UsernameManager.shared.setAppleUsername(existing)
                print("✅ Pre-restored username: \(existing)")
            }

            // THEN set session (triggers isSignedIn = true)
            self.session = session
            persist(session)

            // Then restore rest
            await GachaManager.shared.restoreFromSupabase()
        } catch {
            print("❌ exchangeWithSupabaseGoogle failed: \(error)")

            self.error = "Google sign in failed: \(error.localizedDescription)"
        }
        
        UserDefaults.standard.set("google", forKey: "authProvider")
        
        isLoading = false
    }
    
    // MARK: - Guest to Google Migration (placeholder)
    func migrateGuestToGoogle(idToken: String) async -> Bool {
        isLoading = true
        error = nil
        
        guard UsernameManager.shared.isGuest else {
            error = "Not a guest user"
            isLoading = false
            return false
        }
        
        let guestUsername = UsernameManager.shared.username
        let guestGems = GachaManager.shared.gems
        let guestCollection = GachaManager.shared.collection
        let guestActiveAnimal = GachaManager.shared.activeAnimalID
        
        do {
            let session = try await exchangeWithSupabaseGoogle(idToken: idToken)
            self.session = session
            persist(session)
            
            if let existing = await SupabaseClient.fetchUsernameForUser(userId: session.userId) {
                UsernameManager.shared.setAppleUsername(existing)
                await GachaManager.shared.restoreFromSupabase()
            } else if let guestName = guestUsername {
                UsernameManager.shared.setAppleUsername(guestName)
                
                await SupabaseClient.upsertUserData(
                    userId: session.userId,
                    username: guestName,
                    gems: guestGems,
                    collection: guestCollection,
                    activeAnimal: guestActiveAnimal
                )
                
                // Link guest scores to Google account
                await SupabaseClient.migrateGuestScores(
                    username: guestName,
                    newUserId: session.userId
                )
            }
            
            await GachaManager.shared.syncToSupabase()
            
            print("✅ Guest migration successful: \(guestUsername ?? "unknown") → Google")
            
            isLoading = false
            return true
            
        } catch {
            self.error = "Migration failed: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    // MARK: - Refresh session
    /// Call once on app launch. Silently refreshes the access token using the stored refresh token.
    /// If the refresh token has also expired (60 days), signs the user out gracefully.
    func refreshSessionIfNeeded() async {
        guard let session else {
            print("⚠️ refreshSession: no session stored")
            return
        }
        print("🔄 refreshSession: attempting refresh for userId=\(session.userId)")

        guard let url = URL(string: "\(supabaseAuthURL)/token?grant_type=refresh_token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])

        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return }

        // 400/401 means refresh token itself expired — sign out cleanly
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            print("⚠️ refreshSession: failed with \(http.statusCode), signing out")
            signOut()
            return
        }

        guard let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess  = json["access_token"]  as? String,
              let newRefresh = json["refresh_token"] as? String else { return }

        print("✅ refreshSession: success")

        updateSession(accessToken: newAccess, refreshToken: newRefresh)
        await GachaManager.shared.restoreFromSupabase()

        // Keep Supabase current so reinstall always has latest state
        await GachaManager.shared.scheduleSyncToSupabase()
    }

    // MARK: - Update tokens in-place
    func updateSession(accessToken: String, refreshToken: String) {
        guard let existing = session else { return }
        let updated = SupabaseSession(accessToken: accessToken,
                                      refreshToken: refreshToken,
                                      userId: existing.userId)
        session = updated
        persist(updated)
    }

    // MARK: - Sign out
    func signOut() {
        // Clear Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "supabaseSession"
        ]
        SecItemDelete(query as CFDictionary)
        
        session = nil
        UsernameManager.shared.clear()
        UserDefaults.standard.removeObject(forKey: "authProvider")
    }

    // MARK: - Exchange Apple token with Supabase
    private func exchangeWithSupabase(identityToken: String) async throws -> SupabaseSession {
        var req = URLRequest(url: URL(string: "\(supabaseAuthURL)/token?grant_type=id_token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: Any] = ["provider": "apple", "id_token": identityToken]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.supabaseExchangeFailed
        }

        guard let json         = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken  = json["access_token"]  as? String,
              let refreshToken = json["refresh_token"] as? String,
              let user         = json["user"]          as? [String: Any],
              let userId       = user["id"]            as? String else {
            throw AuthError.supabaseExchangeFailed
        }

        return SupabaseSession(accessToken: accessToken,
                               refreshToken: refreshToken,
                               userId: userId)
    }
    
    // MARK: - Exchange Google token with Supabase (placeholder)
    private func exchangeWithSupabaseGoogle(idToken: String) async throws -> SupabaseSession {
        var req = URLRequest(url: URL(string: "\(supabaseAuthURL)/token?grant_type=id_token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: Any] = ["provider": "google", "id_token": idToken]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.supabaseExchangeFailed
        }

        guard let json         = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken  = json["access_token"]  as? String,
              let refreshToken = json["refresh_token"] as? String,
              let user         = json["user"]          as? [String: Any],
              let userId       = user["id"]            as? String else {
            throw AuthError.supabaseExchangeFailed
        }

        return SupabaseSession(accessToken: accessToken,
                               refreshToken: refreshToken,
                               userId: userId)
    }

    // MARK: - Persist session
    private func persist(_ session: SupabaseSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }
}
