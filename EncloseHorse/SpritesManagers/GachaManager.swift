//
//  GachaManager.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/10/26.
//

import Foundation

// MARK: - Gem reward helpers
struct GemReward {

    // MARK: - Daily puzzle reward (based on optimality %)
    static func dailyGems(score: Int, optimal: Int) -> Int {
        guard optimal > 0 else { return 1 }
        let pct = Double(score) / Double(optimal)
        let scaling = 100
        switch pct {
        case 1.0...:  return 1*scaling
        case 0.75...: return Int(0.8)*scaling
        case 0.50...: return Int(0.6)*scaling
        case 0.25...: return Int(0.4)*scaling
        default:      return Int(0.2)*scaling
        }
    }

    // MARK: - Infinite puzzle reward (improvement only, capped at 5 total per level)
    /// Returns how many NEW gems to award given previous gems earned and new score.
    static func infiniteGems(score: Int, optimal: Int, gemsAlreadyEarned: Int) -> Int {
        let newTier  = infiniteTier(score: score, optimal: optimal)
        let newTotal = min(5, newTier)
        let delta    = max(0, newTotal - gemsAlreadyEarned)
        return delta
    }

    /// Gem tier for an infinite score (0-5, used to compute improvements)
    static func infiniteTier(score: Int, optimal: Int) -> Int {
        guard optimal > 0 else { return score > 0 ? 1 : 0 }
        let pct = Double(score) / Double(optimal)
        switch pct {
        case 1.0...:  return 5
        case 0.75...: return 4
        case 0.50...: return 3
        case 0.25...: return 2
        default:      return score > 0 ? 1 : 0
        }
    }
}

// MARK: - GachaManager
@MainActor
@Observable
class GachaManager {
    static let shared = GachaManager()

    private let gemsKey       = "gacha_gems"
    private let collectionKey = "gacha_collection"
    private let activeKey     = "gacha_active_animal"
    private let pullCost      = 160
    private var syncTask: Task<Void, Never>?

    // MARK: - State
    var gems: Int {
        get { UserDefaults.standard.integer(forKey: gemsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: gemsKey)
            scheduleSyncToSupabase()
        }
    }

    var collection: [String] {
        get { UserDefaults.standard.stringArray(forKey: collectionKey) ?? ["horse"] }
        set {
            UserDefaults.standard.set(newValue, forKey: collectionKey)
            scheduleSyncToSupabase()
        }
    }

    var activeAnimalID: String {
        get { UserDefaults.standard.string(forKey: activeKey) ?? "horse" }
        set {
            UserDefaults.standard.set(newValue, forKey: activeKey)
            scheduleSyncToSupabase()
        }
    }

    var activeAnimal: Animal { AnimalTheme.animal(id: activeAnimalID) }
    var activeSkin: TileSkin { activeAnimal.skin }

    var canPull: Bool { gems >= pullCost }

    // MARK: - Pity counters (persisted)
    /// Total pulls since last SS
    var pullsSinceLastSS: Int {
        get { UserDefaults.standard.integer(forKey: "gacha_pity_ss") }
        set { UserDefaults.standard.set(newValue, forKey: "gacha_pity_ss") }
    }

    /// Total pulls since last S or SS
    var pullsSinceLastS: Int {
        get { UserDefaults.standard.integer(forKey: "gacha_pity_s") }
        set { UserDefaults.standard.set(newValue, forKey: "gacha_pity_s") }
    }

    // MARK: - Pity rates
    /// SS rate: 0.6% base, starts ramping at pull 70, guaranteed at pull 90.
    /// Ramp formula: each pull past 70 adds ~5% additively.
    private func ssRate(at pullCount: Int) -> Double {
        if pullCount < 70  { return 0.006 }
        if pullCount >= 90 { return 1.0 }
        // Linear ramp from 0.6% at pull 70 to 100% at pull 90
        let ramp = Double(pullCount - 70) / Double(90 - 70)
        return 0.006 + ramp * (1.0 - 0.006)
    }

    /// S rate: 5.1% base, hard guaranteed at pull 10.
    private func sRate(at pullCount: Int) -> Double {
        pullCount >= 9 ? 1.0 : 0.051
    }

    // MARK: - Award gems
    func awardGems(_ amount: Int) {
        guard amount > 0 else { return }
        gems += amount
        print("💎 +\(amount) gems (total: \(gems))")
    }
    
    func scheduleSyncToSupabase() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await syncToSupabase()
        }
    }
    
    func syncToSupabase() {
        guard let username = UsernameManager.shared.username else { return }
        let userId = AuthManager.shared.session?.userId
        print("💾 syncToSupabase: userId=\(userId ?? "nil") username=\(username) gems=\(gems)")
        Task {
            await SupabaseClient.upsertUserData(
                userId: userId ?? "", username: username,
                gems: gems, collection: collection, activeAnimal: activeAnimalID
            )
        }
    }

    func restoreFromSupabase() async {
        guard let userId = AuthManager.shared.session?.userId else {
            print("⚠️ restoreFromSupabase: no userId")
            return
        }
        guard let row = await SupabaseClient.fetchUserData(userId: userId) else {
            print("⚠️ restoreFromSupabase: no row found for \(userId)")
            return
        }
        print("📦 restoreFromSupabase: row=\(row)")
        if let g = row["gems"] as? Int { gems = max(gems, g) }

        if let col = row["collection"] as? [String] {
            collection = col
        } else if let colStr = row["collection"] as? String {
            collection = colStr.components(separatedBy: ",")
        }
        if let active = row["active_animal"] as? String { activeAnimalID = active }
        
        if let username = row["username"] as? String {
            if !UsernameManager.shared.hasUsername {
                UsernameManager.shared.setAppleUsername(username)
                print("✅ Restored username from restoreFromSupabase: \(username)")
            }
        }
    }

    // MARK: - Pull
    /// Performs one pull. Returns the animal received.
    @discardableResult
    func pull() -> Animal? {
        guard canPull else { return nil }
        gems -= pullCost

        let ssP  = ssRate(at: pullsSinceLastSS)
        let sP   = sRate(at: pullsSinceLastS)
        let roll = Double.random(in: 0..<1)

        let tier: AnimalTier
        if roll < ssP {
            tier = .ss
            pullsSinceLastSS = 0
            pullsSinceLastS  = 0
        } else if roll < ssP + sP {
            tier = .s
            pullsSinceLastSS += 1
            pullsSinceLastS   = 0
        } else {
            tier = .a
            pullsSinceLastSS += 1
            pullsSinceLastS  += 1
        }

        let pool = AnimalTheme.all.filter { $0.tier == tier }
        guard let animal = pool.randomElement() else { return nil }

        if !collection.contains(animal.id) {
            var updated = collection
            updated.append(animal.id)
            collection = updated
        }

        return animal
    }

    // MARK: - Equip
    func equip(_ animalID: String) {
        guard collection.contains(animalID) else { return }
        activeAnimalID = animalID
    }

    func isOwned(_ animalID: String) -> Bool {
        collection.contains(animalID)
    }
    
    func resetAll() {
        gems = 0
        collection = ["horse"]
        activeAnimalID = "horse"
        pullsSinceLastSS = 0
        pullsSinceLastS = 0
    }
}
