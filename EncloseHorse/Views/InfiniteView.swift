//
//  InfiniteView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/24/26.
//

import SwiftData
import SwiftUI

struct InfiniteView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm: InfiniteViewModel

    init(modelContext: ModelContext) {
        _vm = State(initialValue: InfiniteViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if let data = vm.currentData {
                    VStack(spacing: 0) {
                        InfiniteHeaderBar(vm: vm)
                            .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

                        InfiniteStatsBar(vm: vm, data: data)
                            .padding(.horizontal).padding(.bottom, 8)

                        ZoomableGridView(vm: vm, data: data, puzzleID: vm.currentPuzzleNumber)                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .safeAreaInset(edge: .bottom) {
                        InfiniteActionButtons(vm: vm)
                            .padding(.horizontal).padding(.vertical, 12)
                            .background(.regularMaterial)
                    }
                } else {
                    ProgressView("Generating puzzle…")
                }

                if vm.showSuccessBanner {
                    InfiniteSuccessBanner(
                        score: vm.score,
                        gemsAwarded: vm.lastGemsAwarded,
                        dismiss: { vm.showSuccessBanner = false }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .navigationTitle("♾️ Infinite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: infiniteLeaderboard) {
                        Image(systemName: "trophy")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: InfiniteHistoryView(vm: vm)) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .task {
                let last = vm.highestPuzzleNumber()
                vm.loadPuzzle(number: max(1, last > 0 ? last : 1))
            }
        }
    }

    private var infiniteLeaderboard: some View {
        LeaderboardView(title: "Puzzle #\(vm.currentPuzzleNumber) Leaderboard",
                        date: "",
                        puzzle: nil) {
            try await SupabaseClient.fetchInfiniteLeaderboard(puzzleNumber: vm.currentPuzzleNumber)
        }
    }
}

// MARK: - Header Bar
struct InfiniteHeaderBar: View {
    let vm: InfiniteViewModel

    var body: some View {
        HStack {
            Button { withAnimation { vm.previousPuzzle() } } label: {
                Image(systemName: "chevron.left").font(.headline)
                    .foregroundStyle(vm.currentPuzzleNumber > 1 ? .primary : .tertiary)
            }
            .disabled(vm.currentPuzzleNumber <= 1)

            Spacer()

            VStack(spacing: 2) {
                Text("Puzzle #\(vm.currentPuzzleNumber)").font(.headline)
                Text(vm.difficultyLabel)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(difficultyColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(difficultyColor)
            }

            Spacer()

            Button { withAnimation { vm.nextPuzzle() } } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
        }
        .padding(.vertical, 4)
    }

    private var difficultyColor: Color {
        switch vm.difficultyLabel {
        case "Easy":   return .green
        case "Medium": return .orange
        case "Hard":   return .red
        default:       return .purple
        }
    }
}

// MARK: - Stats Bar
struct InfiniteStatsBar: View {
    let vm: InfiniteViewModel
    let data: PuzzleData

    var body: some View {
        HStack(spacing: 0) {
            StatPill(label: "Walls", value: "\(vm.wallsUsed)/\(data.wallCount)",
                     icon: "🧱", color: vm.wallsUsed >= data.wallCount ? .orange : .blue)
            Divider().frame(height: 40)
            StatPill(label: "Score", value: "\(vm.score)", icon: "🏆", color: .green)
            Divider().frame(height: 40)
            StatPill(label: "Best", value: "\(vm.best)", icon: "⭐️", color: .yellow)
            Divider().frame(height: 40)
            StatPill(label: "Gems", value: "\(vm.currentRecord?.gemsEarned ?? 0)/5",
                     icon: "💎", color: .purple)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.2), value: vm.score)
    }
}

// MARK: - Action Buttons
struct InfiniteActionButtons: View {
    let vm: InfiniteViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { vm.resetWalls() }) {
                Label("Reset", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.orange)
            .disabled(vm.isCompleted)

            if vm.isCompleted {
                Button(action: { withAnimation { vm.resubmit() } }) {
                    Label("Retry", systemImage: "arrow.counterclockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.blue)
                .disabled((vm.currentRecord?.gemsEarned ?? 0) >= 5)

                Button(action: { withAnimation { vm.nextPuzzle() } }) {
                    Label("Next", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.green)
            } else {
                Button(action: { vm.submit() }) {
                    Label("Submit", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.enclosedTiles.isEmpty)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.isCompleted)
    }
}

// MARK: - Infinite Success Banner
struct InfiniteSuccessBanner: View {
    let score: Int
    let gemsAwarded: Int
    let dismiss: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Text(gemsAwarded > 0 ? "💎" : "✅").font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Submitted!").font(.headline.bold())
                    if gemsAwarded > 0 {
                        Text("+\(gemsAwarded) gem\(gemsAwarded == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.purple)
                    } else {
                        Text("No new gems — try to improve your score")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 8)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { dismiss() } }
    }
}

// MARK: - Infinite History
struct InfiniteHistoryView: View {
    let vm: InfiniteViewModel
    @State private var records: [InfinitePuzzleRecord] = []

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView("No puzzles yet", systemImage: "puzzlepiece",
                    description: Text("Complete some infinite puzzles to see them here."))
            } else {
                ForEach(records, id: \.puzzleNumber) { record in
                    Button {
                        vm.loadPuzzle(number: record.puzzleNumber)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Puzzle #\(record.puzzleNumber)").font(.headline)
                                Text(difficultyLabel(for: record.puzzleNumber))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if record.isCompleted {
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(record.score)").font(.title3.bold())
                                    Text("\(record.gemsEarned)/5 💎")
                                        .font(.caption).foregroundStyle(.purple)
                                }
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Text("In progress").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Infinite History")
        .onAppear { records = vm.fetchHistory() }
    }

    private func difficultyLabel(for n: Int) -> String {
        switch n / 10 {
        case 0:     return "Easy"
        case 1...2: return "Medium"
        case 3...5: return "Hard"
        default:    return "Expert"
        }
    }
}
