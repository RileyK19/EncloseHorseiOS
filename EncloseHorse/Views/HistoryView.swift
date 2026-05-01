//
//  HistoryView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/23/26.
//

import SwiftUI
import SwiftData

// MARK: - History View
struct HistoryView: View {
    @Query(sort: \DailyPuzzle.puzzleDate, order: .reverse) private var puzzles: [DailyPuzzle]
    @Environment(\.modelContext) private var modelContext
    @State private var isSyncing = false

    var body: some View {
        List {
            if isSyncing && puzzles.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading history…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if puzzles.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Completed puzzles will appear here.")
                )
            } else {
                ForEach(puzzles) { puzzle in
                    NavigationLink(destination: DayLeaderboardView(puzzle: puzzle)) {
                        PuzzleHistoryRow(puzzle: puzzle)
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .top) {
            if isSyncing && !puzzles.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Syncing…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: isSyncing)
        .task {
            await syncHistory()
        }
        .refreshable {
            await syncHistory()
        }
    }

    private func syncHistory() async {
        guard let username = UsernameManager.shared.username else { return }
        isSyncing = true
        defer { isSyncing = false }

        let scores = await SupabaseClient.fetchAllScores(username: username)
        guard !scores.isEmpty else { return }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone.current

        for row in scores {
            guard let dateStr = row["puzzle_date"] as? String,
                  let num     = row["puzzle_number"] as? Int,
                  let score   = row["score"]         as? Int,
                  let date    = f.date(from: "\(dateStr) 12:00") else { continue }  // noon = safe for any timezone

            let solutionStr  = row["solution_json"] as? String
            let solutionData = solutionStr.flatMap { $0.data(using: .utf8) }


            let startOfDay = Calendar.current.startOfDay(for: date)
            let endOfDay   = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
            print("🔍 dateStr=\(dateStr) date=\(date) startOfDay=\(startOfDay)")
            let descriptor = FetchDescriptor<DailyPuzzle>(
                predicate: #Predicate { $0.puzzleDate >= startOfDay && $0.puzzleDate < endOfDay }
            )
            let matches = (try? modelContext.fetch(descriptor)) ?? []

            if let existing = try? modelContext.fetch(descriptor).first {
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
    }
}

// MARK: - Per-day leaderboard (tapped from history)
struct DayLeaderboardView: View {
    let puzzle: DailyPuzzle

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        return fmt.string(from: puzzle.puzzleDate)
    }

    private var isoDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: puzzle.puzzleDate)
    }

    var body: some View {
        LeaderboardView(title: dateString, date: isoDate, puzzle: puzzle) {
            try await SupabaseClient.fetchDailyLeaderboard(date: isoDate)
        }
        .safeAreaInset(edge: .bottom) {
            if puzzle.isSubmitted {
                HStack {
                    Text("Your score")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(puzzle.score)")
                        .font(.headline.bold())
                        .foregroundStyle(.blue)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
    }
}

// MARK: - History Row
struct PuzzleHistoryRow: View {
    let puzzle: DailyPuzzle

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: puzzle.puzzleDate)
    }

    private var medalEmoji: String {
        guard puzzle.isSubmitted else { return "⏳" }
        let optimal = puzzle.optimalScore
        if optimal > 0 {
            let pct = Double(puzzle.score) / Double(optimal)
            if pct >= 1.0  { return "🏆" }
            if pct >= 0.90 { return "🥇" }
            if pct >= 0.70 { return "🥈" }
            if pct >= 0.50 { return "🥉" }
            return "🏅"
        }
        guard let data = puzzle.puzzleData else { return "❓" }
        let pct = Double(puzzle.score) / Double(data.rows * data.cols)
        if pct >= 0.85 { return "💎" }
        if pct >= 0.70 { return "🥇" }
        if pct >= 0.50 { return "🥈" }
        return "🥉"
    }

    private var subtitleText: String {
        guard puzzle.isSubmitted else { return "In progress" }
        let optimal = puzzle.optimalScore
        guard optimal > 0 else { return "Score: \(puzzle.score)" }
        let pct = min(100, Int(Double(puzzle.score) / Double(optimal) * 100))
        return "\(puzzle.score) / \(optimal) optimal (\(pct)%)"
    }

    var body: some View {
        HStack {
            Text(medalEmoji).font(.title2).frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(dateString).font(.headline)
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(puzzle.isSubmitted ? .primary : .secondary)
            }
            Spacer()
            if puzzle.isSubmitted {
                Text("\(puzzle.score)")
                    .font(.title3.bold())
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
