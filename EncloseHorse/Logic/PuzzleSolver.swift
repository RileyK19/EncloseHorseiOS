//
//  PuzzleSolver.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/23/26.
//

import Foundation

// TO BE IMPLEMENTED SOON

// MARK: - Optimal Solver

extension GameEngine {

    /// Find the optimal score for a puzzle.
    /// Returns the maximum score achievable with puzzle.wallCount walls.
    ///
    /// Called from PuzzleViewModel.submit() on a background thread,
    /// so feel free to do expensive computation here.
    /// The result is stored in DailyPuzzle.optimalScore.
    static func findOptimalScore(puzzle: PuzzleData) -> Int {
        return 0  // replace with real implementation
    }
}
