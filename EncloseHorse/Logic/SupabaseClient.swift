//
//  SupabaseClient.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/26/26.
//

import Foundation

struct SupabaseClient {
    
    static let url      = Constants.supabaseURL
    static let anonKey  = Constants.supabaseKey
    
    private static var authToken: String {
        AuthManager.shared.session?.accessToken ?? anonKey
    }
    
    private static var getHeaders: [String: String] {
        ["apikey": anonKey,
         "Authorization": "Bearer \(anonKey)",
         "Content-Type": "application/json"]
    }
    
    private static var postHeaders: [String: String] {
        ["apikey": anonKey,
         "Authorization": "Bearer \(authToken)",
         "Content-Type": "application/json",
         "Prefer": "resolution=merge-duplicates,return=representation"]
    }
    
    // MARK: - Generic helpers
    
    private static func buildURL(_ table: String, query: String) -> URL? {
        var components = URLComponents(string: "\(url)/\(table)")
        components?.percentEncodedQuery = query
        return components?.url
    }
    
    private static func get(_ table: String, query: String) async throws -> Data {
        guard let reqURL = buildURL(table, query: query) else { throw URLError(.badURL) }
        var req = URLRequest(url: reqURL)
        req.timeoutInterval = 15
        getHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        return data
    }
    
    private static func post(_ table: String, body: [String: Any]) async throws -> Data {
        guard let reqURL = URL(string: "\(url)/\(table)") else { throw URLError(.badURL) }
        
        func makeRequest(token: String) throws -> URLRequest {
            var req = URLRequest(url: reqURL)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }
        
        var req = try makeRequest(token: authToken)
        var (data, response) = try await URLSession.shared.data(for: req)
        
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            await MainActor.run { AuthManager.shared.signOut() }
            req = try makeRequest(token: anonKey)
            (data, response) = try await URLSession.shared.data(for: req)
        }
        
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        return data
    }
    
    private static func decodeLeaderboard(_ data: Data) throws -> [LeaderboardEntry] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return rows.compactMap { row in
            guard let username = row["username"] as? String,
                  let score    = row["score"]    as? Int else { return nil }
            return LeaderboardEntry(username: username, score: score)
        }
    }
    
    // MARK: - Daily puzzle cache
    
    static func fetchDailyPuzzle(date: String) async -> String? {
        guard let data = try? await get("daily_puzzles",
                                        query: "puzzle_date=eq.\(date)&select=puzzle_json,optimal&limit=1") else { return nil }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first,
              let jsonString = first["puzzle_json"] as? String else { return nil }
        
        // Merge optimal column into puzzle_json if puzzle_json has 0
        let optimal = first["optimal"] as? Int ?? 0
        if optimal > 0,
           var json = try? JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any],
           (json["optimalScore"] as? Int ?? 0) == 0 {
            json["optimalScore"] = optimal
            if let merged = try? JSONSerialization.data(withJSONObject: json),
               let mergedString = String(data: merged, encoding: .utf8) {
                return mergedString
            }
        }
        
        return jsonString
    }
    static func uploadDailyPuzzle(date: String, puzzleNumber: Int, puzzleJSON: String) async {
        _ = try? await post("daily_puzzles", body: [
            "puzzle_date":   date,
            "puzzle_number": puzzleNumber,
            "puzzle_json":   puzzleJSON
        ])
    }
    
    // MARK: - Daily leaderboard
    
    static func submitDailyScore(date: String, puzzleNumber: Int,
                                 username: String, score: Int,
                                 solutionJSON: String? = nil) async throws {
        var body: [String: Any] = [
            "puzzle_date":   date,
            "puzzle_number": puzzleNumber,
            "username":      username,
            "score":         score
        ]
        if let uid = AuthManager.shared.session?.userId { body["user_id"] = uid }
        if let sol = solutionJSON { body["solution_json"] = sol }
        _ = try await post("daily_scores", body: body)
    }
    
    static func scoreExistsInDB(date: String, username: String) async -> Bool {
        let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        guard let data = try? await get("daily_scores",
                                        query: "puzzle_date=eq.\(date)&username=eq.\(encodedUser)&limit=1&select=score"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        return !rows.isEmpty
    }
    
    static func fetchDailyLeaderboard(date: String) async throws -> [LeaderboardEntry] {
        let data = try await get("daily_scores",
                                 query: "puzzle_date=eq.\(date)&order=score.desc&limit=20")
        return try decodeLeaderboard(data)
    }
    
    static func fetchTopDailyScore(date: String) async -> Int? {
        guard let data = try? await get("daily_scores",
                                        query: "puzzle_date=eq.\(date)&order=score.desc&limit=1&select=score") else { return nil }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first,
              let score = first["score"] as? Int else { return nil }
        return score
    }
    
    
    // MARK: - Optimal score (daily_puzzles table)
    
    
    /// Returns count of daily puzzles where optimal is still 0 or missing
    static func fetchMissingOptimalCount() async -> Int {
        guard let data = try? await get("daily_puzzles",
                                        query: "optimal=eq.0&select=puzzle_date") else { return 0 }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return 0 }
        return rows.count
    }
    
    static func fetchOptimalScore(date: String) async -> Int? {
        guard let data = try? await get("daily_puzzles",
                                        query: "puzzle_date=eq.\(date)&select=optimal&limit=1") else { return nil }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first,
              let optimal = first["optimal"] as? Int else { return nil }
        return optimal
    }
    
    static func uploadOptimalScore(date: String, optimal: Int) async {
        _ = try? await patch("daily_puzzles",
                             query: "puzzle_date=eq.\(date)",
                             body: ["optimal": optimal])
        print("💾 Uploaded optimal=\(optimal) for \(date)")
    }
    
    static func fetchUserData(userId: String) async -> [String: Any]? {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        guard let data = try? await get("user_data",
            query: "user_id=eq.\(encoded)&limit=1") else { return nil }
        print("🔍 fetchUserData raw: \(String(data: data, encoding: .utf8) ?? "nil")")
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first
    }

    static func upsertUserData(userId: String, username: String, gems: Int,
                                collection: [String], activeAnimal: String) async {
        _ = try? await post("user_data", body: [
            "user_id":       userId,
            "username":      username,
            "gems":          gems,
            "collection":    collection,
            "active_animal": activeAnimal
        ])
    }

    static func fetchAllScores(username: String) async -> [[String: Any]] {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        guard let data = try? await get("daily_scores",
            query: "username=eq.\(encoded)&order=puzzle_date.desc&select=puzzle_date,puzzle_number,score,solution_json")
        else { return [] }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
    
    
    private static func patch(_ table: String, query: String, body: [String: Any]) async throws -> Data {
        guard let reqURL = URL(string: "\(url)/\(table)?\(query)") else { throw URLError(.badURL) }
        
        func makeRequest(token: String) throws -> URLRequest {
            var req = URLRequest(url: reqURL)
            req.httpMethod = "PATCH"
            req.timeoutInterval = 15
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("return=representation", forHTTPHeaderField: "Prefer")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }
        
        var req = try makeRequest(token: authToken)
        var (data, response) = try await URLSession.shared.data(for: req)
        
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            await MainActor.run { AuthManager.shared.signOut() }
            req = try makeRequest(token: anonKey)
            (data, response) = try await URLSession.shared.data(for: req)
        }
        
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: body])
        }
        
        return data
    }
    
    // MARK: - Infinite leaderboard
    
    static func submitInfiniteScore(puzzleNumber: Int, username: String, score: Int) async throws {
        var body: [String: Any] = [
            "puzzle_number": puzzleNumber,
            "username":      username,
            "score":         score
        ]
        if let uid = AuthManager.shared.session?.userId { body["user_id"] = uid }
        _ = try await post("infinite_scores", body: body)
    }
    
    static func fetchInfiniteLeaderboard(puzzleNumber: Int) async throws -> [LeaderboardEntry] {
        let data = try await get("infinite_scores",
                                 query: "puzzle_number=eq.\(puzzleNumber)&order=score.desc&limit=20")
        return try decodeLeaderboard(data)
    }
    
    static func fetchTopInfiniteScore(puzzleNumber: Int) async -> Int? {
        guard let data = try? await get("infinite_scores",
                                        query: "puzzle_number=eq.\(puzzleNumber)&order=score.desc&limit=1&select=score") else { return nil }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first,
              let score = first["score"] as? Int else { return nil }
        return score
    }
    
    // MARK: - Username availability
    
    static func checkUsernameAvailable(_ username: String, userId: String? = nil) async -> Bool {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        
        for table in ["daily_scores", "infinite_scores"] {
            if let data = try? await get(table,
                                         query: "username=eq.\(encoded)&user_id=not.is.null&limit=1&select=username,user_id"),
               let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let row = rows.first {
                // If this row belongs to the signing-in user, it's their username — allow it
                if let uid = userId, (row["user_id"] as? String) == uid { continue }
                return false
            }
        }
        return true
    }
    
    static func fetchUsernameForUser(userId: String) async -> String? {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        if let data = try? await get("user_data",
             query: "user_id=eq.\(encoded)&limit=1&select=username"),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let username = rows.first?["username"] as? String {
            return username
        }
        return nil
    }
    
    static func fetchSolution(date: String, username: String) async -> [[Bool]]? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        guard let data = try? await get("daily_scores",
            query: "puzzle_date=eq.\(date)&username=eq.\(encoded)&select=solution_json&limit=1")
        else { return nil }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first,
              let solStr = first["solution_json"] as? String,
              let solData = solStr.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode([[Bool]].self, from: solData)
    }
    
    // MARK: - Migrate guest scores to Apple account
    static func migrateGuestScores(username: String, newUserId: String) async {
        guard let session = AuthManager.shared.session else {
            print("⚠️ Cannot migrate scores: no session")
            return
        }
        
        // Update daily_scores
        await updateScoresTable(
            table: "daily_scores",
            username: username,
            newUserId: newUserId,
            accessToken: session.accessToken
        )
        
        // Update infinite_scores
        await updateScoresTable(
            table: "infinite_scores",
            username: username,
            newUserId: newUserId,
            accessToken: session.accessToken
        )
    }

    private static func updateScoresTable(table: String, username: String, newUserId: String, accessToken: String) async {
        guard let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(url)/\(table)?username=eq.\(encodedUsername)&user_id=is.null") else {
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = ["user_id": newUserId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else {
            print("⚠️ Failed to migrate \(table) for \(username)")
            return
        }
        
        if http.statusCode == 200 || http.statusCode == 204 {
            print("✅ Migrated \(table) for \(username) to user_id \(newUserId)")
        } else {
            print("⚠️ \(table) migration returned \(http.statusCode)")
        }
    }
}

// MARK: - Models
struct LeaderboardEntry: Identifiable {
    var id: String { username }
    let username: String
    let score: Int
}
