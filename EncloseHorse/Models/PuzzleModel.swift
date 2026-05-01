//
//  PuzzleModel.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/23/26.
//

import Foundation
import SwiftData

// MARK: - Tile Types
enum TileType: String, Codable {
    case grass  = "g"
    case water  = "w"
    case horse  = "H"
    case cherry = "c"   // +3 when enclosed
    case bee    = "b"   // -5 when enclosed
    case gem    = "gem" // +10 when enclosed
    // Portals are stored as "portal_0".."portal_9" — use isPortal() helper
}

extension String {
    var isPortal: Bool { hasPrefix("portal_") }
    var portalKey: String? { isPortal ? self : nil }
}

// MARK: - Grid Tile
struct GridTile: Codable, Identifiable {
    var id: String { "\(row)-\(col)" }
    let row: Int
    let col: Int
    var type: TileType
    var hasWall: Bool = false
}

// MARK: - Puzzle Data
struct PuzzleData: Codable {
    let rows: Int
    let cols: Int
    let tiles: [[String]]
    let wallCount: Int
    let horseRow: Int
    let horseCol: Int
    let optimalScore: Int   // from window.__LEVEL__.optimal — 0 means unknown

    // Default arg so InfinitePuzzleGenerator doesn't need to change
    init(rows: Int, cols: Int, tiles: [[String]], wallCount: Int,
         horseRow: Int, horseCol: Int, optimalScore: Int = 0) {
        self.rows = rows; self.cols = cols; self.tiles = tiles
        self.wallCount = wallCount
        self.horseRow = horseRow; self.horseCol = horseCol
        self.optimalScore = optimalScore
    }
}

// MARK: - SwiftData Model
@Model
class DailyPuzzle {
    var puzzleDate: Date
    var puzzleNumber: Int
    var puzzleJSON: Data
    var solutionJSON: Data?
    var score: Int
    var isCompleted: Bool
    var isSubmitted: Bool
    var fetchedAt: Date
    // NOTE: optimalScore is intentionally NOT a stored property here.
    // It lives inside puzzleJSON (PuzzleData.optimalScore) to avoid
    // SwiftData migrations when the schema changes.

    init(puzzleDate: Date, puzzleNumber: Int, puzzleJSON: Data, fetchedAt: Date = .now) {
        self.puzzleDate   = puzzleDate
        self.puzzleNumber = puzzleNumber
        self.puzzleJSON   = puzzleJSON
        self.score        = 0
        self.isCompleted  = false
        self.isSubmitted  = false
        self.fetchedAt    = fetchedAt
    }

    var puzzleData: PuzzleData? {
        try? JSONDecoder().decode(PuzzleData.self, from: puzzleJSON)
    }

    var wallGrid: [[Bool]]? {
        guard let data = solutionJSON else { return nil }
        return try? JSONDecoder().decode([[Bool]].self, from: data)
    }

    // Convenience passthrough — reads from JSON, no stored property needed
    var optimalScore: Int { puzzleData?.optimalScore ?? 0 }
}
