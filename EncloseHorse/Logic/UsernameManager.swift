//
//  UsernameManager.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/26/26.
//

import Foundation

// MARK: - Username + guest flag stored in UserDefaults (set once, never changes)
class UsernameManager {
    static let shared = UsernameManager()

    private let usernameKey = "enclosed_username"
    private let isGuestKey  = "enclosed_is_guest"

    var username: String? {
        get { UserDefaults.standard.string(forKey: usernameKey) }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }

    /// True when the user chose "Continue as Guest" rather than Sign in with Apple
    var isGuest: Bool {
        get { UserDefaults.standard.bool(forKey: isGuestKey) }
        set { UserDefaults.standard.set(newValue, forKey: isGuestKey) }
    }

    var hasUsername: Bool { username != nil && !(username!.isEmpty) }

    /// Call when completing the guest flow
    func setGuestUsername(_ name: String) {
        username = name
        isGuest  = true
    }

    /// Call after a successful Apple Sign In username setup
    func setAppleUsername(_ name: String) {
        username = name
        isGuest  = false
    }

    /// Clear everything (sign out / reset)
    func clear() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: isGuestKey)
        print("🗑️ UsernameManager cleared: username=\(username ?? "nil"), isGuest=\(isGuest)")
    }
}
