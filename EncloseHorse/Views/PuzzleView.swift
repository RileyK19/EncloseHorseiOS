//
//  PuzzleView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/23/26.
//

import SwiftData
import SwiftUI

struct PuzzleView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var vm: PuzzleViewModel
    
    init(vm: PuzzleViewModel) {
        self.vm = vm
    }


    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                mainContent
                    .popover(isPresented: $vm.showAbout) { aboutPopup }
                    .popover(isPresented: $vm.showSettings) {
                        NavigationStack {
                            VStack(spacing: 0) {
                                // Header
                                HStack {
                                    Text("Settings")
                                        .font(.headline)
                                    Spacer()
                                    Button(action: { vm.showSettings = false }) {
//                                        Image(systemName: "xmark.circle.fill")
//                                            .foregroundStyle(.secondary)
//                                            .font(.title3)
                                        Text("Close")
                                            .font(.headline)
                                    }
                                }
                                .padding(.top, 15)
                                .padding()
                                
                                Divider()
                                 
                                NavigationLink(destination: AccountSettingsView()) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.circle")
                                            .font(.body)
                                            .foregroundStyle(.blue)
                                            .frame(width: 28)
                                        
                                        Text("Account")
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                Divider()
                                
                                // Menu Items
                                VStack(spacing: 0) {
                                    SettingsRow(icon: "sparkles",
                                               label: "Sprites",
                                               isOn: $vm.spriteToggle)
                                    
                                    Divider()
                                    
                                    NavigationLink(destination: HistoryView()) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.body)
                                                .foregroundStyle(.cyan)
                                                .frame(width: 28)
                                            
                                            Text("History")
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    SettingsButton(icon: "questionmark.circle",
                                                  label: "About",
                                                  color: .purple) {
                                        vm.showSettings = false
                                        vm.showAbout = true
                                    }
                                    
                                    Divider()
                                    
                                    SettingsButton(icon: "envelope.fill",
                                                  label: "Send Feedback",
                                                  color: .green) {
                                        if let url = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSf_Nw9Ya6GYcBB4_juWdAkzcwwR7HHzfdrf_xoaPfCYHPp7VQ/viewform?usp=publish-editor") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    SettingsButton(icon: "hand.raised.fill",
                                                  label: "Privacy Policy",
                                                  color: .orange) {
                                        if let url = URL(string: "https://verdant-gaura-e8e.notion.site/Privacy-Policy-for-Enclosed-Horse-App-31eaa40c9944803f8496cf25a0baf8c3") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                
                                Spacer()
                                
                                // Sign Out Button
                                VStack(spacing: 8) {
                                    Text("Signed in as \(UsernameManager.shared.username ?? "User")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Button("Sign Out", role: .destructive) {
                                        vm.showSignOutConfirm.toggle()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }
                                .padding(.bottom, 16)
                                .confirmationDialog("Sign Out", isPresented: $vm.showSignOutConfirm) {
                                    Button("Sign Out", role: .destructive) {
                                        AuthManager.shared.signOut()
                                        UsernameManager.shared.clear()
                                        GachaManager.shared.gems = 0
                                        GachaManager.shared.collection = ["horse"]
                                        GachaManager.shared.activeAnimalID = "horse"
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("You'll need to sign in again to submit scores.")
                                }
                            }
                        }
                    }
                if vm.showSuccessBanner { banner }
            }
            .navigationTitle("🐴 Enclosed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    NavigationLink(destination: DailyLeaderboardView(initialDate: vm.displayDate, puzzle: vm.puzzle)) {
                        Image(systemName: "trophy")
                    }
                    
                    Button {
                        Task { await vm.refreshPuzzle() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { vm.showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }

//                ToolbarItemGroup(placement: .navigationBarTrailing) {
//                    Button { vm.showAbout = true } label: {
//                        Image(systemName: "questionmark")
//                    }
//
//                    NavigationLink(destination: HistoryView()) {
//                        Image(systemName: "clock.arrow.circlepath")
//                    }
//                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if vm.isLoading {
            LoadingView()
        } else if let errorMsg = vm.loadError {
            ZStack(alignment: .top) {
                ErrorView(message: errorMsg) { Task { await vm.loadTodaysPuzzle() } }
                DayNavigationOverlay(vm: vm).padding(.top, 6)
            }
        } else if let puzzle = vm.puzzle, let data = puzzle.puzzleData {
            ZStack(alignment: .top) {
                if vm.isFetchingOptimal, let wv = vm.scraper.currentWebView {
                    WebViewRepresentable(webView: wv)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
                VStack(spacing: 0) {
                    StatsBar(vm: vm, data: data)
                        .padding(.horizontal).padding(.vertical, 8)
                    if vm.isOffline {
                        OfflineBanner().padding(.horizontal).padding(.bottom, 4)
                    }
                    ZoomableGridView(vm: vm, data: data, puzzleID: puzzle.puzzleNumber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .safeAreaInset(edge: .bottom) {
                    ActionButtons(vm: vm)
                        .padding(.horizontal).padding(.vertical, 12)
                        .background(.regularMaterial)
                }
                DayNavigationOverlay(vm: vm).padding(.top, 6)
            }
        } else {
            ZStack(alignment: .top) {
                Text("No puzzle loaded").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                DayNavigationOverlay(vm: vm).padding(.top, 6)
            }
        }
    }

    private var banner: some View {
        SuccessBanner(score: vm.score, optimalScore: vm.puzzle?.optimalScore ?? 0) {
            vm.showSuccessBanner = false
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(10)
    }

    private var aboutPopup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How to Play enclose.horse")
                    .font(.largeTitle).fontWeight(.bold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("The Goal").font(.title2).fontWeight(.semibold)
                    Text("Build a pen around the horse by placing walls on the grid. Tap a grass (green) tile to place a wall. The more grass tiles you trap the horse inside, the higher your score. Each puzzle has a different number of walls you can use.")
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Horse Movement").font(.title2).fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• The horse moves up, down, left, and right — never diagonally.")
                        Text("• It can't cross walls or water.")
                        Text("• If there's a gap to the edge, the horse can escape.")
                        Text("• Pro Tip: Tap the horse in-game to preview escape paths.")
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Special Tiles").font(.title2).fontWeight(.semibold)
                    Text("Some puzzles include bonus items. If they're inside the pen, they affect your score:")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🍒 Cherries — +3 each")
                        Text("🍎 Golden Apples — +10 each")
                        Text("🐝 Bee Swarms — −5 each")
                        Text("🌀 Portals — the horse teleports between them")
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Puzzles & Community").font(.title2).fontWeight(.semibold)
                    Text("A new puzzle drops every day and everyone gets the same one. You get one submission attempt, so plan carefully before submitting!")
                    Text("After submitting, you can see how everyone else scored and view the optimal solution. Past puzzles and community-created levels are available in the menu.")
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Credit to the [Original Website](https://enclose.horse/) by [Shivers](https://x.com/thinkingshivers)")
                        .font(.title3).fontWeight(.semibold)
                    Text("App made by [Me](https://github.com/RileyK19) :)")
                    Text("Feedback is appreciated! (and a place to submit bug reports) ->  [Form](https://docs.google.com/forms/d/e/1FAIpQLSf_Nw9Ya6GYcBB4_juWdAkzcwwR7HHzfdrf_xoaPfCYHPp7VQ/viewform?usp=publish-editor)")
                    
                    Text("Privacy Policy: [Privacy Policy](https://verdant-gaura-e8e.notion.site/Privacy-Policy-for-Enclosed-Horse-App-31eaa40c9944803f8496cf25a0baf8c3)")

                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
    
    private struct SettingsRow: View {
        let icon: String
        let label: String
        @Binding var isOn: Bool
        
        var body: some View {
            Button(action: { isOn.toggle() }) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    
                    Text(label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                        .allowsHitTesting(false)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private struct SettingsButton: View {
        let icon: String
        let label: String
        let color: Color
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(color)
                        .frame(width: 28)
                    
                    Text(label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Day Navigation Overlay
struct DayNavigationOverlay: View {
    let vm: PuzzleViewModel

    var body: some View {
        HStack {
            Button { Task { await vm.loadPuzzle(offset: -1) } } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary.opacity(0.30))
            }
            .buttonStyle(.plain)

            Spacer()

            if !vm.isShowingToday {
                Button { Task { await vm.loadTodaysPuzzle() } } label: {
                    Text("Today")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.blue.opacity(0.75), in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            Button { Task { await vm.loadPuzzle(offset: 1) } } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(vm.isShowingToday ? .clear : .secondary.opacity(0.30))
            }
            .buttonStyle(.plain)
            .disabled(vm.isShowingToday)
            .allowsHitTesting(!vm.isShowingToday)
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: vm.isShowingToday)
    }
}

// MARK: - Stats Bar
struct StatsBar: View {
    let vm: PuzzleViewModel
    let data: PuzzleData
    @State private var showCalendar = false

    var body: some View {
        Button { showCalendar = true } label: {
            HStack(spacing: 0) {
                StatPill(label: "Walls", value: "\(vm.wallsUsed)/\(data.wallCount)",
                         icon: "🧱", color: vm.wallsUsed >= data.wallCount ? .orange : .blue)
                Divider().frame(height: 40)
                StatPill(label: "Score", value: "\(vm.score)", icon: "🏆", color: .green)
                Divider().frame(height: 40)
                StatPill(label: "Best", value: "\(vm.best)", icon: "⭐️", color: .yellow)
                if vm.streak > 1 {
                    Divider().frame(height: 40)
                    StatPill(label: "Streak", value: "\(vm.streak)", icon: "🔥", color: .orange)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: vm.score)
        .sheet(isPresented: $showCalendar) {
            PuzzleCalendarSheet(vm: vm, isPresented: $showCalendar)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Action Buttons
struct ActionButtons: View {
    let vm: PuzzleViewModel
    @State private var showOptimalPopup = false
    @State private var showSubmitConfirm = false

    private var optimalLabel: String {
        if vm.isCheckingOptimal { return "..." }
        if let opt = vm.optimalScoreResult { return opt > 0 ? "Best: \(opt)" : "N/A" }
        return "Check"
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                HStack(spacing: 10) {
                    Button(action: { vm.resetWalls() }) {
                        Label("Reset", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.orange).disabled(vm.isSubmitted)
                    
                    Button(action: { vm.restoreBestSolution() }) {
                        Label("Best", systemImage: "arrow.uturn.backward")                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(vm.isSubmitted || vm.bestWalls.isEmpty)
                }
                HStack(spacing: 10) {
                    Button(action: {
                        if vm.optimalScoreResult != nil {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                showOptimalPopup.toggle()
                            }
                        } else {
                            vm.checkOptimalScore {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    showOptimalPopup = true
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if vm.isCheckingOptimal {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: vm.optimalScoreResult != nil ? "checkmark.seal.fill" : "seal.fill")
                            }
                            Text(optimalLabel).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(vm.optimalScoreResult != nil ? .purple : .secondary)
                    .disabled(vm.isCheckingOptimal)
                    
                    Button(action: {
                        if !vm.isSubmitted {
                            showSubmitConfirm = true
                        }
                    }) {
                        Label(vm.isSubmitted ? "Submitted ✓" : "Submit",
                              systemImage: vm.isSubmitted ? "checkmark.circle.fill" : "paperplane.fill")
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isSubmitted ? .green : .blue)
                    .disabled(vm.isSubmitted)
                    .confirmationDialog(
                        "Submit your solution?",
                        isPresented: $showSubmitConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Submit", role: .none) {
                            showOptimalPopup = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                vm.submit()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Once submitted, you can't make changes to today's puzzle.")
                    }
                }
            }

            if showOptimalPopup, let optimal = vm.optimalScoreResult {
                OptimalScorePopup(
                    playerScore: vm.score,
                    optimalScore: optimal,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) { showOptimalPopup = false }
                    }
                )
                .offset(y: -8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(5)
            }
        }
    }
}

// MARK: - Optimal Score Popup
struct OptimalScorePopup: View {
    let playerScore: Int
    let optimalScore: Int
    let onDismiss: () -> Void

    private var pct: Int {
        guard optimalScore > 0 else { return 0 }
        return min(100, Int(Double(playerScore) / Double(optimalScore) * 100))
    }
    private var isOptimal: Bool { optimalScore > 0 && playerScore >= optimalScore }
    private var closeness: Double {
        guard optimalScore > 0 else { return 0 }
        return min(1.0, Double(playerScore) / Double(optimalScore))
    }
    private var rating: (emoji: String, headline: String, sub: String) {
        if isOptimal { return ("🏆", "Optimal!", "You matched the best possible score.") }
        if pct >= 90 { return ("🔥", "So close!", "You're just \(optimalScore - playerScore) point\(optimalScore - playerScore == 1 ? "" : "s") away from optimal.") }
        if pct >= 70 { return ("💪", "Almost there!", "You've got \(pct)% of the optimal score.") }
        if pct >= 50 { return ("🤔", "Good start", "There's more to enclose — try a different wall placement.") }
        return ("💡", "Keep going", "The optimal score is \(optimalScore). You can do better!")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(rating.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rating.headline).font(.headline.bold())
                    Text(rating.sub).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.body)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4).fill(barColor)
                        .frame(width: geo.size.width * closeness, height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: closeness)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Your score: ").font(.caption).foregroundStyle(.secondary)
                + Text("\(playerScore)").font(.caption.bold())
                Spacer()
                if optimalScore > 0 {
                    Text("Optimal: ").font(.caption).foregroundStyle(.secondary)
                    + Text("\(optimalScore)").font(.caption.bold()).foregroundStyle(.purple)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: -3)
        .padding(.horizontal, 4)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 6) { onDismiss() } }
    }

    private var barColor: Color {
        if isOptimal { return .green }
        if pct >= 90 { return .orange }
        if pct >= 70 { return .yellow }
        return .blue
    }
}

// MARK: - Puzzle Calendar Sheet
struct PuzzleCalendarSheet: View {
    let vm: PuzzleViewModel
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext

    private let earliest = Calendar.current.startOfDay(
        for: DateComponents(calendar: .current, year: 2025, month: 12, day: 30).date ?? .now
    )
    private let today = Calendar.current.startOfDay(for: .now)
    private let cal = Calendar.current

    @State private var displayMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selected: Date = Calendar.current.startOfDay(for: .now)
    @State private var statusMap: [String: DayStatus] = [:]

    enum DayStatus { case submitted, loaded }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let dayLetters = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                            .foregroundStyle(canGoPrev ? .primary : .tertiary)
                    }
                    .disabled(!canGoPrev)
                    Spacer()
                    Text(monthTitle).font(.headline)
                    Spacer()
                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right").fontWeight(.semibold)
                            .foregroundStyle(canGoNext ? .primary : .tertiary)
                    }
                    .disabled(!canGoNext)
                }
                .padding(.horizontal, 24)

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(Array(dayLetters.enumerated()), id: \.offset) { _, d in
                        Text(d).font(.caption.bold()).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.bottom, 4)
                    }
                }
                .padding(.horizontal, 12)

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                        DayCell(date: date, today: today, selected: selected,
                                earliest: earliest,
                                status: date == nil ? nil : statusMap[isoKey(date!)])
                            .onTapGesture {
                                guard let date, isSelectable(date) else { return }
                                selected = date
                            }
                    }
                }
                .padding(.horizontal, 12)

                HStack(spacing: 16) {
                    LegendDot(color: .green, label: "Submitted")
                    LegendDot(color: Color(.systemGray4), label: "Loaded")
                    LegendDot(color: .clear, label: "No data", bordered: true)
                }
                .font(.caption).foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.top, 8)
            .navigationTitle("Jump to date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        isPresented = false
                        Task { await vm.loadPuzzle(for: selected) }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isSelectable(selected))
                }
            }
        }
        .onAppear {
            selected     = vm.displayDate
            displayMonth = startOfMonth(vm.displayDate)
            buildStatusMap()
        }
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: displayMonth)
    }
    private var canGoPrev: Bool {
        startOfMonth(cal.date(byAdding: .month, value: -1, to: displayMonth)!) >= startOfMonth(earliest)
    }
    private var canGoNext: Bool { startOfMonth(displayMonth) < startOfMonth(today) }
    private func shiftMonth(_ delta: Int) {
        displayMonth = cal.date(byAdding: .month, value: delta, to: displayMonth)!
    }
    private func startOfMonth(_ date: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date))!
    }
    private func isSelectable(_ date: Date) -> Bool { date >= earliest && date <= today }
    private var calendarDays: [Date?] {
        let monthStart = startOfMonth(displayMonth)
        let weekdayOfFirst = cal.component(.weekday, from: monthStart) - 1
        let daysInMonth = cal.range(of: .day, in: .month, for: displayMonth)!.count
        var days: [Date?] = Array(repeating: nil, count: weekdayOfFirst)
        for d in 0..<daysInMonth { days.append(cal.date(byAdding: .day, value: d, to: monthStart)) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
    private func isoKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
    private func buildStatusMap() {
        let puzzles = (try? modelContext.fetch(FetchDescriptor<DailyPuzzle>())) ?? []
        var map: [String: DayStatus] = [:]
        for p in puzzles { map[isoKey(p.puzzleDate)] = p.isSubmitted ? .submitted : .loaded }
        statusMap = map
    }
}

private struct DayCell: View {
    let date: Date?
    let today: Date
    let selected: Date
    let earliest: Date
    let status: PuzzleCalendarSheet.DayStatus?
    private let cal = Calendar.current
    private var isToday: Bool    { date.map { cal.isDateInToday($0) } ?? false }
    private var isSelected: Bool { date.map { cal.isDate($0, inSameDayAs: selected) } ?? false }
    private var isSelectable: Bool {
        guard let date else { return false }
        return date >= earliest && date <= today
    }
    var body: some View {
        Group {
            if let date {
                let day = cal.component(.day, from: date)
                ZStack {
                    Circle().fill(dotFill)
                        .overlay(Circle().strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2))
                        .frame(width: 34, height: 34)
                    Text("\(day)").font(isToday ? .callout.bold() : .callout).foregroundStyle(labelColor)
                }
                .frame(maxWidth: .infinity)
                .opacity(isSelectable ? 1.0 : 0.25)
            } else {
                Color.clear.frame(height: 34)
            }
        }
    }
    private var dotFill: Color {
        if isSelected { return Color.blue.opacity(0.15) }
        switch status {
        case .submitted: return Color.green.opacity(0.25)
        case .loaded:    return Color(.systemGray5)
        case nil:        return Color.clear
        }
    }
    private var labelColor: Color {
        if isSelected    { return .blue }
        if isToday       { return .primary }
        if !isSelectable { return .secondary }
        switch status {
        case .submitted: return .green
        default:         return .primary
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var bordered: Bool = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color)
                .overlay(Circle().strokeBorder(Color(.systemGray4), lineWidth: bordered ? 1 : 0))
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}

