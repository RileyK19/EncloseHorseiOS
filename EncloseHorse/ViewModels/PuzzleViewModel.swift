//
//  PuzzleViewModel.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/23/26.
//

import Foundation
import SwiftData
import UIKit

@MainActor
@Observable
class PuzzleViewModel: GridInteractable {

    // MARK: - State
    var puzzle: DailyPuzzle?
    var walls: [[Bool]] = []
    var enclosedTiles: Set<String> = []
    var escapePathTiles: Set<String> = []
    var showEscapePath: Bool = false
    var score: Int = 0
    var cherries: Int = 0
    var bees: Int = 0
    var gems: Int = 0
    var wallsUsed: Int = 0
    var isLoading: Bool = false
    var loadError: String?
    var isOffline: Bool = false
    var showSuccessBanner: Bool = false
    var isSubmitted: Bool = false
    var best: Int = 0
    var streak: Int = 0
    var optimalScoreResult: Int? = nil
    var isCheckingOptimal: Bool = false
    var displayDate: Date = Calendar.current.startOfDay(for: .now)
    var showAbout: Bool = false
    var hasLoaded = false
    var isFetchingOptimal = false
    var bestWalls: [[Bool]] = []
    var spriteToggle: Bool = true
    var showSettings: Bool = false
    var showSignOutConfirm: Bool = false

    // GridInteractable
    var currentPuzzleData: PuzzleData? { puzzle?.puzzleData }

    private var modelContext: ModelContext
    let scraper = PuzzleScraper()

    // Haptics
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy  = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
        print("🆕 PuzzleViewModel init")
    }

    // MARK: - Public entry points

    func loadTodaysPuzzle() async {
        await AuthManager.shared.refreshSessionIfNeeded()
        await syncPendingScores()
        displayDate = Calendar.current.startOfDay(for: .now)
        await loadPuzzle(for: displayDate)
        streak = computeStreak()
        await restoreHistoryIfNeeded()
    }
    
    func restoreHistoryIfNeeded() async {
        let key = "history_sync_date_v4"
        let todayStr = scraper.isoDate(.now)
        guard UserDefaults.standard.string(forKey: key) != todayStr else { return }
        
        guard let username = UsernameManager.shared.username else { return }
        
        let scores = await SupabaseClient.fetchAllScores(username: username)
        guard !scores.isEmpty else { return }
        
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        
        let allPuzzles = (try? modelContext.fetch(FetchDescriptor<DailyPuzzle>())) ?? []
        
        for row in scores {
            guard let dateStr = row["puzzle_date"]  as? String,
                  let num     = row["puzzle_number"] as? Int,
                  let score   = row["score"]         as? Int,
                  let date    = f.date(from: dateStr) else { continue }
            
            let solutionStr  = row["solution_json"] as? String
            let solutionData = solutionStr.flatMap { $0.data(using: .utf8) }

            let startOfDay = Calendar.current.startOfDay(for: date)
            let endOfDay   = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
            
            let existing = allPuzzles.first { $0.puzzleDate >= startOfDay && $0.puzzleDate < endOfDay }
            
            if let existing {
                existing.isSubmitted  = true
                existing.score        = score
                existing.solutionJSON = solutionData ?? existing.solutionJSON
            } else {
                let localDate = Calendar.current.startOfDay(for: date)
                let stub = DailyPuzzle(puzzleDate: localDate, puzzleNumber: num, puzzleJSON: Data())
                stub.score        = score
                stub.isSubmitted  = true
                stub.solutionJSON = solutionData
                modelContext.insert(stub)
            }
        }
        try? modelContext.save()
        UserDefaults.standard.set(todayStr, forKey: key)
    }
    
    func loadPuzzle(offset: Int) async {
        let newDate = Calendar.current.date(byAdding: .day, value: offset, to: displayDate) ?? displayDate
        let today   = Calendar.current.startOfDay(for: .now)
        guard newDate <= today else { return }
        displayDate = newDate
        await loadPuzzle(for: displayDate)
    }

    var isShowingToday: Bool {
        Calendar.current.isDateInToday(displayDate)
    }

    // MARK: - Core loader
    func loadPuzzle(for targetDate: Date) async {
        displayDate = Calendar.current.startOfDay(for: targetDate)
        
        // 1. Local cache with valid optimal
        let startOfTarget = Calendar.current.startOfDay(for: targetDate)
        let endOfTarget = Calendar.current.date(byAdding: .day, value: 1, to: startOfTarget)!
        let descriptor = FetchDescriptor<DailyPuzzle>(
            predicate: #Predicate { $0.puzzleDate >= startOfTarget && $0.puzzleDate < endOfTarget }
        )
        if let cached = try? modelContext.fetch(descriptor).first, cached.optimalScore > 0 {
            applyPuzzle(cached)
            return
        }

        isLoading = true
        loadError = nil
        isOffline = false

        do {
            // 2. Scraper (gets puzzle + optimal together)
            let puzzleData = try await scraper.fetchPuzzle(for: targetDate)
            let encoded = try JSONEncoder().encode(puzzleData)
            let dayNum = scraper.daysSinceEpoch(for: targetDate)
            
            // Update or create local record
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.puzzleJSON = encoded
                applyPuzzle(existing)
            } else {
                let daily = DailyPuzzle(puzzleDate: targetDate, puzzleNumber: dayNum, puzzleJSON: encoded)
                modelContext.insert(daily)
                try? modelContext.save()
                applyPuzzle(daily)
            }
            
            // Upload to Supabase in background
            if let jsonString = String(data: encoded, encoding: .utf8) {
                Task {
                    await SupabaseClient.uploadDailyPuzzle(date: scraper.isoDate(targetDate),
                                                            puzzleNumber: dayNum, puzzleJSON: jsonString)
                    print("📤 uploading optimal=\(puzzleData.optimalScore) for \(scraper.isoDate(targetDate))")
                    if puzzleData.optimalScore > 0 {
                        await SupabaseClient.uploadOptimalScore(date: scraper.isoDate(targetDate),
                                                                optimal: puzzleData.optimalScore)
                        print("✅ uploaded optimal")
                    }
                }
            }
        } catch {
            loadError = "Today's puzzle isn't available yet. Try again soon."
            print("❌ Failed to load puzzle: \(error)")
        }

        isLoading = false
    }

    private func applyPuzzle(_ daily: DailyPuzzle) {
        print("📅 applyPuzzle: puzzleDate=\(daily.puzzleDate) isoDate=\(scraper.isoDate(daily.puzzleDate)) puzzleNumber=\(daily.puzzleNumber) optimalScore=\(daily.optimalScore)")
        puzzle             = daily
        isSubmitted        = daily.isSubmitted
        best               = daily.isSubmitted ? daily.score : 0
        showEscapePath     = false
        escapePathTiles    = []
        optimalScoreResult = nil
        loadError          = nil

        guard let data = daily.puzzleData else { return }
        walls = daily.wallGrid
            ?? Array(repeating: Array(repeating: false, count: data.cols), count: data.rows)
        recalculate()
        
        if daily.optimalScore == 0 {
            guard !isFetchingOptimal else { return }
            isFetchingOptimal = true
            isCheckingOptimal = true  // ← shows spinner in UI
            let date = daily.puzzleDate
            let expectedNumber = daily.puzzleNumber
            Task { @MainActor in
                defer {
                    isFetchingOptimal = false
                    isCheckingOptimal = false  // ← hides spinner
                }
                let dateStr = scraper.isoDate(date)
                if let cached = await SupabaseClient.fetchOptimalScore(date: dateStr), cached > 0 {
                    updateOptimal(cached, for: daily, expectedNumber: expectedNumber)
                    return
                }
                let optimal = await scraper.scrapeOptimal(for: date)
                guard optimal > 0 else { return }
                updateOptimal(optimal, for: daily, expectedNumber: expectedNumber)
            }
        }
        
        if daily.optimalScore > 0 {
            let dateStr = scraper.isoDate(daily.puzzleDate)
            Task {
                let existing = await SupabaseClient.fetchOptimalScore(date: dateStr)
                if existing == nil || existing == 0 {
                    await SupabaseClient.uploadOptimalScore(date: dateStr, optimal: daily.optimalScore)
                    print("📤 uploaded optimal=\(daily.optimalScore) for \(dateStr)")
                }
            }
        }

        // Restore submitted state from Supabase if reinstalled
        if !daily.isSubmitted, let username = UsernameManager.shared.username {
            let dateStr = scraper.isoDate(daily.puzzleDate)
            Task {
                let exists = await SupabaseClient.scoreExistsInDB(date: dateStr, username: username)
                if exists {
                    daily.isSubmitted = true
                    isSubmitted = true
                    try? modelContext.save()
                }
            }
        }
    }
    
    private func updateOptimal(_ optimal: Int, for daily: DailyPuzzle, expectedNumber: Int) {
        guard puzzle?.puzzleNumber == expectedNumber else { return }
        guard let data = daily.puzzleData else { return }
        let updated = PuzzleData(rows: data.rows, cols: data.cols, tiles: data.tiles,
                                 wallCount: data.wallCount, horseRow: data.horseRow,
                                 horseCol: data.horseCol, optimalScore: optimal)
        daily.puzzleJSON = (try? JSONEncoder().encode(updated)) ?? daily.puzzleJSON
        try? modelContext.save()
        optimalScoreResult = optimal
    }

    // MARK: - GridInteractable

    func toggleEscapePath() {
        guard let data = puzzle?.puzzleData, !isSubmitted else { return }
        showEscapePath.toggle()
        escapePathTiles = showEscapePath
            ? GameEngine.escapePath(puzzle: data, walls: walls)
            : []
    }

    func toggleWall(row: Int, col: Int) {
        guard !isSubmitted else { return }
        guard let data = puzzle?.puzzleData else { return }

        let tileType = TileType(rawValue: data.tiles[row][col]) ?? .grass
        guard tileType == .grass else { return }

        let current = walls[row][col]
        if !current && GameEngine.wallsUsed(walls) >= data.wallCount { return }

        walls[row][col].toggle()
        current ? impactLight.impactOccurred(intensity: 0.4) : impactLight.impactOccurred()

        recalculate()
        saveSolution()
    }

    // MARK: - Recalculate
    private func recalculate() {
        guard let data = puzzle?.puzzleData else { return }
        let prevEnclosed = !enclosedTiles.isEmpty
        enclosedTiles = GameEngine.enclosedTiles(puzzle: data, walls: walls)
        let result    = GameEngine.calculateScore(puzzle: data, walls: walls)
        score     = result.total
        cherries  = result.cherries
        bees      = result.bees
        gems      = result.gems
        wallsUsed = GameEngine.wallsUsed(walls)
        if score > best { best = score }

        let nowEnclosed = !enclosedTiles.isEmpty
        if nowEnclosed && !prevEnclosed      { impactMedium.impactOccurred() }
        else if !nowEnclosed && prevEnclosed { impactLight.impactOccurred(intensity: 0.5) }

        if showEscapePath {
            escapePathTiles = GameEngine.escapePath(puzzle: data, walls: walls)
        }
        if score >= best {
            best = score
            bestWalls = walls
        }
    }

    private func saveSolution() {
        guard let puzzle else { return }
        puzzle.solutionJSON = try? JSONEncoder().encode(walls)
        puzzle.score = score
        try? modelContext.save()
    }

    // MARK: - Submit
    func submit() {
        guard let puzzle else { return }
        puzzle.isSubmitted = true
        puzzle.score       = score
        isSubmitted        = true
        showSuccessBanner  = true
        showEscapePath     = false
        escapePathTiles    = []
        try? modelContext.save()
        notification.notificationOccurred(.success)

        let optimal = puzzle.optimalScore
        let earned  = GemReward.dailyGems(score: score, optimal: optimal)
        GachaManager.shared.awardGems(earned)

        guard let username = UsernameManager.shared.username else { return }
        let dateStr = scraper.isoDate(puzzle.puzzleDate)
        let num = puzzle.puzzleNumber
        let s   = score
        let solutionData = try? JSONEncoder().encode(walls)
        let solutionStr = solutionData.flatMap { String(data: $0, encoding: .utf8) }

        Task {
            do {
                try await SupabaseClient.submitDailyScore(
                    date: dateStr, puzzleNumber: num, username: username,
                    score: s, solutionJSON: solutionStr
                )
                ScoreUploadTracker.shared.markUploaded(date: dateStr)
            } catch {
                print("⚠️ Score upload failed: \(error)")
            }
        }
    }

    // MARK: - Sync pending scores
    func syncPendingScores() async {
        guard let username = UsernameManager.shared.username else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<DailyPuzzle>())) ?? []
        let submitted = all.filter { $0.isSubmitted }

        for puzzle in submitted {
            let dateStr = scraper.isoDate(puzzle.puzzleDate)
            guard !ScoreUploadTracker.shared.isUploaded(date: dateStr) else { continue }
            
            // Check DB first before attempting upload
            let alreadyInDB = await SupabaseClient.scoreExistsInDB(date: dateStr, username: username)
            if alreadyInDB {
                ScoreUploadTracker.shared.markUploaded(date: dateStr)
                continue
            }
            
            do {
                let solutionStr = puzzle.solutionJSON.flatMap { String(data: $0, encoding: .utf8) }
                try await SupabaseClient.submitDailyScore(
                    date: dateStr, puzzleNumber: puzzle.puzzleNumber,
                    username: username, score: puzzle.score,
                    solutionJSON: solutionStr
                )
                ScoreUploadTracker.shared.markUploaded(date: dateStr)
                print("✅ Synced pending score for \(dateStr): \(puzzle.score)")
            } catch {
                print("⚠️ Retry failed for \(dateStr): \(error)")
                break
            }
        }
    }

    // MARK: - Reset
    func resetWalls() {
        guard !isSubmitted, let data = puzzle?.puzzleData else { return }
        walls = Array(repeating: Array(repeating: false, count: data.cols), count: data.rows)
        impactLight.impactOccurred(intensity: 0.6)
        recalculate()
        saveSolution()
    }

    // MARK: - Check Optimal Score
    func checkOptimalScore(completion: (() -> Void)? = nil) {
        guard !isCheckingOptimal else { return }
        isCheckingOptimal = true
        impactLight.impactOccurred(intensity: 0.5)

        if let jsOptimal = puzzle?.optimalScore, jsOptimal > 0 {
            optimalScoreResult = jsOptimal
            isCheckingOptimal  = false
            completion?()
            return
        }

        guard let puzzle else { isCheckingOptimal = false; return }
        let dateStr = scraper.isoDate(puzzle.puzzleDate)
        Task {
            let top = await SupabaseClient.fetchTopDailyScore(date: dateStr)
            optimalScoreResult = top ?? 0
            isCheckingOptimal  = false
            completion?()
        }
    }

    // MARK: - Streak
    func computeStreak() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<DailyPuzzle>(
            sortBy: [SortDescriptor(\.puzzleDate, order: .reverse)]
        ))) ?? []
        let submitted = all.filter { $0.isSubmitted }
        guard !submitted.isEmpty else { return 0 }

        let cal = Calendar.current
        var streak    = 0
        var checkDate = cal.startOfDay(for: .now)

        for puzzle in submitted {
            let puzzleDay = cal.startOfDay(for: puzzle.puzzleDate)
            if puzzleDay == checkDate {
                streak += 1
                checkDate = cal.date(byAdding: .day, value: -1, to: checkDate)!
            } else { break }
        }
        return streak
    }

    func fetchHistory(context: ModelContext) -> [DailyPuzzle] {
        let descriptor = FetchDescriptor<DailyPuzzle>(
            sortBy: [SortDescriptor(\.puzzleDate, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Backfill
    func backfillPuzzlesToSupabase() async {
        let key = "supabase_backfill_complete_v1"
        guard UserDefaults.standard.string(forKey: key) == nil else { return }
        print("🚀 Starting backfill...")

        let cal       = Calendar.current
        let epoch     = cal.startOfDay(
            for: DateComponents(calendar: .current, year: 2025, month: 12, day: 30).date ?? .now
        )
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))!
        var current   = epoch

        while current <= yesterday {
            // Dec 29 2025 had no puzzle (day 1 was Dec 30)
            let dateStr_check = scraper.isoDate(current)
            if dateStr_check == "2025-12-29" {
                current = cal.date(byAdding: .day, value: 1, to: current)!
                continue
            }

            let dateStr = scraper.isoDate(current)
            print("🔄 Fetching \(dateStr)...")

            guard
                let url = URL(string: Constants.baseURL + "api/daily/\(dateStr)"),
                let (data, _) = try? await URLSession.shared.data(from: url),
                let json      = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let mapString = json["map"] as? String
            else {
                print("⚠️ Failed to fetch \(dateStr)")
                current = cal.date(byAdding: .day, value: 1, to: current)!
                continue
            }

            let budget  = json["budget"]    as? Int ?? 10
            let dayNum  = json["dayNumber"] as? Int ?? scraper.daysSinceEpoch(for: current)
            let optimal = json["optimal"]   as? Int ?? 0

            let puzzleData = scraper.parseMap(mapString, wallCount: budget, optimalScore: optimal)
            guard
                let encoded    = try? JSONEncoder().encode(puzzleData),
                let jsonString = String(data: encoded, encoding: .utf8)
            else {
                current = cal.date(byAdding: .day, value: 1, to: current)!
                continue
            }

            await SupabaseClient.uploadDailyPuzzle(date: dateStr, puzzleNumber: dayNum, puzzleJSON: jsonString)
            print("✅ Uploaded: \(dateStr)")
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }

        UserDefaults.standard.set("done", forKey: key)
        print("✅ Backfill complete")
    }
    
    func refreshPuzzle() async {
        let descriptor = FetchDescriptor<DailyPuzzle>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let startOfDay = Calendar.current.startOfDay(for: displayDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        for puzzle in all where puzzle.puzzleDate >= startOfDay && puzzle.puzzleDate < endOfDay {
            modelContext.delete(puzzle)
        }
        try? modelContext.save()
        await loadPuzzle(for: displayDate)
        
        // Restore submitted solution from Supabase if exists
        guard let username = UsernameManager.shared.username,
              let puzzle else { return }
        let dateStr = scraper.isoDate(puzzle.puzzleDate)
        let scores = await SupabaseClient.fetchAllScores(username: username)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        if let row = scores.first(where: { ($0["puzzle_date"] as? String) == dateStr }),
           let solStr = row["solution_json"] as? String,
           let solData = solStr.data(using: .utf8),
           let savedWalls = try? JSONDecoder().decode([[Bool]].self, from: solData) {
            walls = savedWalls
            puzzle.solutionJSON = solData
            puzzle.isSubmitted = true
            isSubmitted = true
            try? modelContext.save()
            recalculate()
        }
    }
    
    func restoreBestSolution() {
        guard !isSubmitted, !bestWalls.isEmpty else { return }
        walls = bestWalls
        showEscapePath = false
        escapePathTiles = []
        impactLight.impactOccurred(intensity: 0.6)
        recalculate()
    }
}
