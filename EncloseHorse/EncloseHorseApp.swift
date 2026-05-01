//
//  EncloseHorseApp.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/23/26.
//

import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct EncloseHorseApp: App {

    let container: ModelContainer
    @StateObject private var auth = AuthManager.shared

    init() {
        do {
            container = try ModelContainer(for: DailyPuzzle.self, InfinitePuzzleRecord.self)
            
//            // Only restore Google if not already signed in with Apple
//            if AuthManager.shared.session == nil {
//                GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
//                    if let user = user, let idToken = user.idToken?.tokenString {
//                        Task {
//                            await AuthManager.shared.signInWithGoogle(idToken: idToken)
//                        }
//                    }
//                }
//            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if auth.isSignedIn {
                ContentView()
                    .modelContainer(container)
                    .environmentObject(auth)
                    .onAppear {
                        Task {
                            if let session = AuthManager.shared.session {
                                print("🔍 Current userId: \(session.userId)")
                                print("🔍 Username: \(UsernameManager.shared.username ?? "nil")")
                                print("🔍 isGuest: \(UsernameManager.shared.isGuest)")
                                
                                if let userData = await SupabaseClient.fetchUserData(userId: session.userId) {
                                    print("📦 user_data from DB: \(userData)")
                                }
                            }
                        }
                    }

            } else {
                SignInView()
                    .environmentObject(auth)
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var auth: AuthManager
    @State private var showUsernameSetup = !UsernameManager.shared.hasUsername
    @State private var puzzleVM: PuzzleViewModel?

    var body: some View {
        TabView {
            Group {
                if let vm = puzzleVM {
                    PuzzleView(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .tabItem { Label("Daily", systemImage: "calendar") }

            InfiniteView(modelContext: modelContext)
                .tabItem { Label("Infinite", systemImage: "infinity") }

//            GachaView()
//                .tabItem { Label("Gacha", systemImage: "sparkles") }
        }
        .guestAlert()
        .onAppear {
            if puzzleVM == nil {
                let vm = PuzzleViewModel(modelContext: modelContext)
                puzzleVM = vm
                Task {
                    await vm.loadTodaysPuzzle()
                    await vm.backfillPuzzlesToSupabase()
                    await auth.refreshSessionIfNeeded()
                }
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if !signedIn {
                // Clear local puzzle history on sign out
                let descriptor = FetchDescriptor<DailyPuzzle>()
                if let puzzles = try? modelContext.fetch(descriptor) {
                    print("🗑️ Deleting \(puzzles.count) local puzzles on sign out")
                    for puzzle in puzzles { modelContext.delete(puzzle) }
                    try? modelContext.save()
                }
            }
            if signedIn { showUsernameSetup = !UsernameManager.shared.hasUsername }
        }
        .sheet(isPresented: $showUsernameSetup) {
            UsernameSetupView(isPresented: $showUsernameSetup)
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { showUsernameSetup = !UsernameManager.shared.hasUsername }
        }
    }
}
