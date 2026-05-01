//
//  InfinitePuzzleRecord.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/24/26.
//

import Foundation
import SwiftData
import UIKit

// MARK: - Infinite Puzzle Record (persisted)
@Model
class InfinitePuzzleRecord {
    var puzzleNumber: Int
    var puzzleJSON: Data
    var solutionJSON: Data?
    var score: Int
    var isCompleted: Bool
    var playedAt: Date
    var gemsEarned: Int = 0   // tracks gems awarded so far for this level (max 5)

    init(puzzleNumber: Int, puzzleJSON: Data) {
        self.puzzleNumber = puzzleNumber
        self.puzzleJSON   = puzzleJSON
        self.score        = 0
        self.isCompleted  = false
        self.playedAt     = .now
        self.gemsEarned   = 0
    }

    var puzzleData: PuzzleData? {
        try? JSONDecoder().decode(PuzzleData.self, from: puzzleJSON)
    }

    var wallGrid: [[Bool]]? {
        guard let data = solutionJSON else { return nil }
        return try? JSONDecoder().decode([[Bool]].self, from: data)
    }
}

// MARK: - InfiniteViewModel
@MainActor
@Observable
class InfiniteViewModel: GridInteractable {

    // MARK: - State
    var currentRecord: InfinitePuzzleRecord?
    var walls: [[Bool]] = []
    var enclosedTiles: Set<String> = []
    var escapePathTiles: Set<String> = []
    var showEscapePath: Bool = false
    let spriteToggle: Bool = false
    var score: Int = 0
    var cherries: Int = 0
    var bees: Int = 0
    var gems: Int = 0
    var wallsUsed: Int = 0
    var isCompleted: Bool = false
    var isSubmitted: Bool { isCompleted }
    var showSuccessBanner: Bool = false
    var currentPuzzleNumber: Int = 1
    var best: Int = 0
    var lastGemsAwarded: Int = 0   // shown in success banner

    // GridInteractable
    var currentPuzzleData: PuzzleData? { currentRecord?.puzzleData }

    private var modelContext: ModelContext
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        impactLight.prepare()
        impactMedium.prepare()
        notification.prepare()
    }

    // MARK: - Load puzzle by number
    func loadPuzzle(number: Int) {
        currentPuzzleNumber = number

        let descriptor = FetchDescriptor<InfinitePuzzleRecord>(
            predicate: #Predicate { $0.puzzleNumber == number }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            applyRecord(existing)
            return
        }

        let puzzle = InfinitePuzzleGenerator.generate(puzzleNumber: number)
        guard let encoded = try? JSONEncoder().encode(puzzle) else { return }

        let record = InfinitePuzzleRecord(puzzleNumber: number, puzzleJSON: encoded)
        modelContext.insert(record)
        try? modelContext.save()
        applyRecord(record)
    }

    private func applyRecord(_ record: InfinitePuzzleRecord) {
        currentRecord   = record
        isCompleted     = record.isCompleted
        best            = record.isCompleted ? record.score : 0
        showEscapePath  = false
        escapePathTiles = []
        lastGemsAwarded = 0

        guard let data = record.puzzleData else { return }
        walls = record.wallGrid
            ?? Array(repeating: Array(repeating: false, count: data.cols), count: data.rows)
        recalculate()
    }

    // MARK: - Next / Previous
    func nextPuzzle() { loadPuzzle(number: currentPuzzleNumber + 1) }

    func previousPuzzle() {
        guard currentPuzzleNumber > 1 else { return }
        loadPuzzle(number: currentPuzzleNumber - 1)
    }

    // MARK: - GridInteractable

    func toggleEscapePath() {
        guard let data = currentRecord?.puzzleData, !isCompleted else { return }
        showEscapePath.toggle()
        escapePathTiles = showEscapePath
            ? GameEngine.escapePath(puzzle: data, walls: walls)
            : []
    }

    func toggleWall(row: Int, col: Int) {
        guard !isCompleted else { return }
        guard let data = currentRecord?.puzzleData else { return }

        let tileType = TileType(rawValue: data.tiles[row][col]) ?? .grass
        guard tileType == .grass else { return }

        let current = walls[row][col]
        if !current && GameEngine.wallsUsed(walls) >= data.wallCount { return }

        walls[row][col].toggle()
        impactLight.impactOccurred(intensity: current ? 0.4 : 1.0)
        recalculate()
        saveSolution()
    }

    // MARK: - Recalculate
    private func recalculate() {
        guard let data = currentRecord?.puzzleData else { return }
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
    }

    private func saveSolution() {
        guard let record = currentRecord else { return }
        record.solutionJSON = try? JSONEncoder().encode(walls)
        record.score        = score
        try? modelContext.save()
    }

    // MARK: - Submit (resubmittable — awards improvement gems only)
    func submit() {
        guard let record = currentRecord else { return }

        record.isCompleted = true
        record.score       = score
        isCompleted        = true
        showSuccessBanner  = true
        showEscapePath     = false
        escapePathTiles    = []
        notification.notificationOccurred(.success)
        try? modelContext.save()

        let num           = currentPuzzleNumber
        let submittedScore = score
        let previousGems  = record.gemsEarned

        Task {
            // Upload score first so it counts toward leaderboard top
            if let username = UsernameManager.shared.username {
                try? await SupabaseClient.submitInfiniteScore(
                    puzzleNumber: num, username: username, score: submittedScore
                )
            }

            // Fetch leaderboard top as optimal
            let optimal = await SupabaseClient.fetchTopInfiniteScore(puzzleNumber: num) ?? 0
            let newGems = GemReward.infiniteGems(
                score: submittedScore, optimal: optimal, gemsAlreadyEarned: previousGems
            )

            record.gemsEarned = previousGems + newGems
            lastGemsAwarded   = newGems
            try? modelContext.save()

            if newGems > 0 {
                GachaManager.shared.awardGems(newGems)
            }
        }
    }

    // Allow re-submitting to improve score
    func resubmit() {
        guard let record = currentRecord else { return }
        isCompleted        = false
        record.isCompleted = false
        try? modelContext.save()
    }

    func resetWalls() {
        guard !isCompleted, let data = currentRecord?.puzzleData else { return }
        walls = Array(repeating: Array(repeating: false, count: data.cols), count: data.rows)
        showEscapePath  = false
        escapePathTiles = []
        impactLight.impactOccurred(intensity: 0.6)
        recalculate()
        saveSolution()
    }

    // MARK: - History
    func fetchHistory() -> [InfinitePuzzleRecord] {
        let descriptor = FetchDescriptor<InfinitePuzzleRecord>(
            sortBy: [SortDescriptor(\.puzzleNumber, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func highestPuzzleNumber() -> Int {
        let descriptor = FetchDescriptor<InfinitePuzzleRecord>(
            sortBy: [SortDescriptor(\.puzzleNumber, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor))?.first?.puzzleNumber ?? 0
    }

    var currentData: PuzzleData? { currentRecord?.puzzleData }

    var difficultyLabel: String {
        switch currentPuzzleNumber / 10 {
        case 0:     return "Easy"
        case 1...2: return "Medium"
        case 3...5: return "Hard"
        default:    return "Expert"
        }
    }
}
