//
//  LeaderboardView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/26/26.
//

import SwiftUI
import SwiftData

// MARK: - Daily Leaderboard with animated date navigation
struct DailyLeaderboardView: View {
    @State private var currentDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var slideDirection: Int = 0  // -1 left, +1 right
    @State private var selectedEntry: LeaderboardEntry? = nil
    @State private var showSolution = false
    @State var puzzle: DailyPuzzle?
    @Environment(\.modelContext) private var modelContext

    init(initialDate: Date = Calendar.current.startOfDay(for: .now), puzzle: DailyPuzzle? = nil) {
        print("🎯 DailyLeaderboardView.init called with initialDate: \(initialDate)")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        print("🎯 initialDate formatted: \(f.string(from: initialDate))")
        _currentDate = State(initialValue: initialDate)
//        self.puzzle = puzzle
        _puzzle = State(initialValue: puzzle)
    }
    
    private var isoDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: currentDate)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(currentDate) }

    private var titleString: String {
        if isToday { return "Today" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: currentDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView("Couldn't load",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error))
                } else if entries.isEmpty {
                    ContentUnavailableView("No scores yet",
                        systemImage: "trophy",
                        description: Text("Be the first to submit!"))
                } else {
                    List {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                            let rank = rankFor(idx, in: entries)
                            Button {
                                guard puzzle != nil else { return }
                                selectedEntry = entry
                            } label: {
                                HStack(spacing: 12) {
                                    Text(medal(for: rank)).font(.title2).frame(width: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.username).font(.headline)
                                        if rank == 0 {
                                            Text("Leader").font(.caption).foregroundStyle(.orange)
                                        }
                                    }
                                    Spacer()
                                    Text("\(entry.score)")
                                        .font(.title3.bold())
                                        .foregroundStyle(rank == 0 ? .orange : .primary)
                                    if puzzle?.isSubmitted == true {
                                        Image(systemName: "eye")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .foregroundStyle(.primary)
                            }
                            .listRowBackground(
                                entry.username == UsernameManager.shared.username
                                    ? Color.blue.opacity(0.08) : Color.clear
                            )
                            .disabled(puzzle == nil)
                        }
                    }
                    .listStyle(.plain)
                    .sheet(item: $selectedEntry) { entry in
                        if let puzzle, puzzle.isSubmitted {
                            SolutionViewerSheet(date: isoDate, entry: entry, puzzle: puzzle)
                        } else {
                            EmptyView()
                        }
                    }
                }
            }
            .id(isoDate)
            .transition(
                slideDirection > 0
                    ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                    : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
            )
        }
        .navigationTitle(titleString)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 20) {
                    Button { navigate(by: -1) } label: {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                    }
                    Text(titleString)
                        .font(.headline)
                        .lineLimit(1)
                        .animation(.none, value: titleString)
                    Button { navigate(by: 1) } label: {
                        Image(systemName: "chevron.right")
                            .fontWeight(.semibold)
                            .foregroundStyle(isToday ? Color.secondary.opacity(0.3) : .primary)
                    }
                    .disabled(isToday)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 && !isToday { navigate(by: 1) }
                    else if value.translation.width > 0 { navigate(by: -1) }
                }
        )
        .background(PopGestureDisabler())
        .onAppear { Task { await load() } }
    }

    // MARK: - Navigation
    private func navigate(by days: Int) {
        let newDate = Calendar.current.date(byAdding: .day, value: days, to: currentDate)!
        slideDirection = days
        withAnimation(.easeInOut(duration: 0.25)) {
            currentDate = newDate
        }

        Task { await load(date: newDate) }
    }

    // MARK: - Fetch
    private func load(date: Date? = nil) async {
        let targetDate = date ?? currentDate
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        let dateStr = f.string(from: targetDate)
        print("🏆 fetching leaderboard for: \(dateStr)")
        
        isLoading = true; error = nil
        do {
            entries = try await SupabaseClient.fetchDailyLeaderboard(date: dateStr)
            
            // Fetch puzzle JSON from Supabase and decode it
            if let jsonString = await SupabaseClient.fetchDailyPuzzle(date: dateStr),
               let data = jsonString.data(using: .utf8),
               let puzzleData = try? JSONDecoder().decode(PuzzleData.self, from: data) {
                
                // Create a DailyPuzzle from the PuzzleData
                let encoded = (try? JSONEncoder().encode(puzzleData))!
                let dayNum = PuzzleScraper().daysSinceEpoch(for: targetDate)
                
                // Check if this puzzle was submitted by looking in SwiftData
                let startOfTarget = Calendar.current.startOfDay(for: targetDate)
                let endOfTarget = Calendar.current.date(byAdding: .day, value: 1, to: startOfTarget)!
                let descriptor = FetchDescriptor<DailyPuzzle>(
                    predicate: #Predicate { $0.puzzleDate >= startOfTarget && $0.puzzleDate < endOfTarget }
                )
                
                if let localPuzzle = try? modelContext.fetch(descriptor).first {
                    puzzle = localPuzzle
                } else {
                    // Create a temporary DailyPuzzle just for viewing
                    let tempPuzzle = DailyPuzzle(puzzleDate: targetDate, puzzleNumber: dayNum, puzzleJSON: encoded)
                    puzzle = tempPuzzle
                }
            }
        }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }
    // MARK: - Rank helpers (ties share the same rank)
    private func rankFor(_ idx: Int, in entries: [LeaderboardEntry]) -> Int {
        let myScore = entries[idx].score
        return entries.prefix(idx).filter { $0.score > myScore }.count
    }

    private func medal(for rank: Int) -> String {
        switch rank {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "\(rank + 1)."
        }
    }
}

// MARK: - Reliably disables swipe-back
private struct PopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { PopGestureVC() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}

private class PopGestureVC: UIViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

// MARK: - Generic Leaderboard View (used for infinite + history)
struct LeaderboardView: View {
    let title: String
    let date: String
    let puzzle: DailyPuzzle?
    let fetchEntries: () async throws -> [LeaderboardEntry]

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedEntry: LeaderboardEntry? = nil
    @State private var showSolution = false

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            } else if let error {
                ContentUnavailableView("Couldn't load",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error))
            } else if entries.isEmpty {
                ContentUnavailableView("No scores yet",
                    systemImage: "trophy",
                    description: Text("Be the first to submit!"))
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                    let rank = rankFor(idx, in: entries)
                    Button {
                        guard let puzzle, puzzle.isSubmitted else { return }
                        selectedEntry = entry
                    } label: {
                        HStack(spacing: 12) {
                            Text(medal(for: rank)).font(.title2).frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.username).font(.headline)
                                if rank == 0 {
                                    Text("Leader").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Text("\(entry.score)")
                                .font(.title3.bold())
                                .foregroundStyle(rank == 0 ? .orange : .primary)
                        }
                        .padding(.vertical, 4)
                        .foregroundStyle(.primary)
                    }
                    .listRowBackground(
                        entry.username == UsernameManager.shared.username
                            ? Color.blue.opacity(0.08) : Color.clear
                    )
                    .disabled(puzzle == nil)
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            if let puzzle {
                SolutionViewerSheet(date: date, entry: entry, puzzle: puzzle)
            } else {
                EmptyView()
            }
        }
        .navigationTitle(title)
        .task { await load() }
    }

    private func load() async {
        isLoading = true; error = nil
        do { entries = try await fetchEntries() }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }

    // MARK: - Rank helpers (ties share the same rank)
    private func rankFor(_ idx: Int, in entries: [LeaderboardEntry]) -> Int {
        let myScore = entries[idx].score
        return entries.prefix(idx).filter { $0.score > myScore }.count
    }

    private func medal(for rank: Int) -> String {
        switch rank {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "\(rank + 1)."
        }
    }
}

struct SolutionViewerSheet: View {
    let date: String
    let entry: LeaderboardEntry
    let puzzle: DailyPuzzle

    @State private var walls: [[Bool]] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading solution…")
                } else if walls.isEmpty || puzzle.puzzleData == nil {
                    ContentUnavailableView("Solution not available",
                        systemImage: "eye.slash",
                        description: Text(""))
                } else {
                    SolutionGridView(data: puzzle.puzzleData!, walls: walls)
                }
            }
            .navigationTitle("\(entry.username)'s solution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            Task {
                let solution = await SupabaseClient.fetchSolution(date: date, username: entry.username)
                print("🔍 fetchSolution date=\(date) username=\(entry.username) result=\(solution?.count ?? -1)")
                walls = solution ?? []
                isLoading = false
            }
        }
    }
}
