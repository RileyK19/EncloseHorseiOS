# 🐴 EncloseHorse for iOS

A native iPhone app for [enclose.horse](https://enclose.horse) — a daily puzzle game where you enclose a horse in the biggest pen you can build with a limited number of walls.

![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift) ![Platform](https://img.shields.io/badge/iOS-17%2B-blue?logo=apple) ![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-blue) ![SwiftData](https://img.shields.io/badge/SwiftData-✓-green) ![Supabase](https://img.shields.io/badge/Supabase-✓-3ECF8E?logo=supabase)

---

## Note

This project requires a private configuration file (`Constants.swift`) with API endpoints that is not included in this repository. To run locally, create `EncloseHorse/Constants.swift` with the following:

```swift
struct Constants {
    static let baseURL = "..."       // enclose.horse base URL
    static let supabaseKey = "..."   // Supabase anon key
    static let supabaseURL = "..."   // Supabase REST URL
}
```

---

## Screenshots

<p float="left">
  <img src="EncloseHorse/Screenshots/PuzzleView.PNG" width="200" />
  <img src="EncloseHorse/Screenshots/CheckButton.PNG" width="200" />
  <img src="EncloseHorse/Screenshots/Calendar.PNG" width="200" />
  <img src="EncloseHorse/Screenshots/HistoryView.PNG" width="200" />
  <img src="EncloseHorse/Screenshots/InfiniteView.PNG" width="200" />
  <img src="EncloseHorse/Screenshots/AboutView.PNG" width="200" />
</p>

---

## Why

The browser version works fine on desktop but feels awkward on mobile — pinch-to-zoom, small tap targets, the keyboard popping up at the wrong times. This is the game built as a proper iPhone app, with an infinite mode that works entirely offline.

---

## Features

### Daily mode
- Fetches each day's puzzle via a three-tier strategy: **local SwiftData cache → Supabase DB → live scrape**. The first user each day loads the puzzle in a hidden `WKWebView`, reads `window.__LEVEL__` via JavaScript injection, parses it locally, and uploads it so everyone else reads from the DB instantly
- Offline fallback — if both Supabase and the scraper fail, loads the most recent cached puzzle with a banner indicator
- Global leaderboard for each day's puzzle with swipe-to-navigate between dates
- Calendar date picker with colour-coded submission history
- Streak tracking across consecutive days played

### Infinite mode
- Procedurally generated puzzles seeded by puzzle number — puzzle #42 is always the same map on any device
- Gradually harder as puzzle number increases: grid size, wall budget, water density, cherries, bees, and gems all scale with difficulty
- Per-puzzle leaderboard so scores are directly comparable across users

### Both modes
- Pinch-to-zoom and pan with a zoom reset slider
- Haptic feedback — light tap on wall place/remove, medium thud when enclosure forms, success notification on submit
- Tap cherries, bees, gems, or water to see what they do in-game
- Score and personal best tracked live as walls are placed
- Portal tiles supported — BFS teleportation across paired tiles

### Auth
- Sign in with Apple and Google Sign In, with full guest mode
- Guest-to-Apple and guest-to-Google migration flows that preserve all local scores and progress
- Session refresh on launch with graceful sign-out on token expiry

### Animal collection *(built, not active)*
- Gacha system with pity guarantees 
- Per-animal emoji skin sets for all grid tiles; sprite asset support with pixel-art rendering
- Gem economy tied to daily and infinite puzzle performance

---

## How scoring works

Scoring runs entirely on-device using a BFS flood fill from the horse's position. The horse is enclosed if the BFS cannot reach outside the grid boundary. The formula matches the site exactly:

```
score = enclosed tiles + (cherries × 3) − (bees × 5) + (gems × 10)
```

Portals are handled by extending the BFS — when the flood fill visits a portal tile, it immediately enqueues all matching portal partners, so the horse can teleport through them.

---

## Architecture

The app follows **MVVM** throughout. `PuzzleViewModel` and `InfiniteViewModel` both conform to a shared `GridInteractable` protocol, allowing `ZoomableGridView` and all shared grid components to work against either mode without duplication.

`TileView` conforms to `Equatable` with a manual implementation so SwiftUI skips re-renders when tile state hasn't changed — important for larger grids where naive diffing gets expensive.

Swift Concurrency (`async/await`, `Task`, `@MainActor`) is used throughout for all network and Supabase calls. The scraper wraps `WKWebView`'s callback-based API in a `CheckedContinuation` with a `Task`-based timeout.

---

## Backend

Supabase (Postgres) with four tables:

| Table | Purpose |
|---|---|
| `daily_puzzles` | Puzzle cache — first scrape of the day uploads here, everyone else reads |
| `daily_scores` | Daily leaderboard, one row per user per day |
| `infinite_scores` | Infinite leaderboard, one row per user per puzzle number |
| `user_data` | Username, gem count, and animal collection per user |

Row-level security allows public read/write with unique constraints preventing duplicate submissions. Scores submitted as a guest (no Apple/Google account) are linked to an account retroactively when the user later signs in, via a PATCH on `user_id`.

---

## Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9 |
| UI | SwiftUI |
| Persistence | SwiftData |
| Backend | Supabase (Postgres REST API) |
| Auth | Sign in with Apple, Google Sign In |
| Web scraping | WKWebView + JavaScript evaluation |
| Concurrency | Swift async/await, structured concurrency |
| Minimum deployment | iOS 17 |

---

## Project structure

```
EncloseHorse/
├── EncloseHorseApp.swift
├── Constants.swift              # gitignored — see setup note above
├── Logic/
│   ├── AuthManager.swift        # Apple/Google sign in, session refresh, guest migration
│   ├── GameEngine.swift         # BFS flood fill, escape path, score calculation
│   ├── InfinitePuzzleGenerator.swift  # Seeded procedural puzzle generation
│   ├── PuzzleScraper.swift      # WKWebView scraper + Supabase/API fallback
│   ├── PuzzleSolver.swift       # Optimal solver stub
│   ├── ScoreUploadTracker.swift # Prevents duplicate Supabase uploads
│   ├── SupabaseClient.swift     # REST client for all Supabase tables
│   └── UsernameManager.swift    # Guest/Apple username persistence
├── Models/
│   ├── PuzzleModel.swift        # SwiftData models + PuzzleData codable
│   └── TileColorTheme.swift     # Per-animal colour theming
├── ViewModels/
│   ├── PuzzleViewModel.swift    # Daily mode state + data fetch orchestration
│   └── InfiniteViewModel.swift  # Infinite mode state + SwiftData persistence
├── Views/
│   ├── SharedGridComponents.swift  # ZoomableGridView, TileView, GridInteractable
│   ├── PuzzleView.swift
│   ├── InfiniteView.swift
│   ├── LeaderboardView.swift
│   ├── HistoryView.swift
│   ├── SignInView.swift
│   ├── AccountSettingsView.swift
│   └── GachaView.swift          # Built, not active
└── SpritesManagers/
    ├── GachaManager.swift
    ├── AnimalTheme.swift
    └── SpriteView.swift
```

---

## Dependency on enclose.horse

The daily puzzle tab scrapes enclose.horse for new puzzles, but only once per day — after that, the puzzle is cached in Supabase and the site is never hit again. Infinite mode is entirely self-contained: the generator, BFS engine, scoring, and persistence are all on-device with no external dependencies.

This project is not affiliated with enclose.horse or its creator. Built for personal use and to gain experience developing in Swift.
