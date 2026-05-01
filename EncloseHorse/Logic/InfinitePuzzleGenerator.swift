//
//  InfinitePuzzleGenerator.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/24/26.
//

import Foundation

// MARK: - Seeded RNG
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state
    }
    mutating func nextInt(in range: Range<Int>) -> Int {
        guard range.count > 0 else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(range.count))
    }
    mutating func nextDouble() -> Double { Double(next()) / Double(UInt64.max) }
    mutating func nextBool(probability: Double) -> Bool { nextDouble() < probability }
    mutating func shuffle<T>(_ arr: inout [T]) {
        for i in stride(from: arr.count - 1, through: 1, by: -1) {
            let j = nextInt(in: 0..<(i + 1))
            arr.swapAt(i, j)
        }
    }
}

// MARK: - Difficulty
struct DifficultyParams {
    let rows: Int
    let cols: Int
    let wallBudget: Int
    let numRegions: Int        // 2 = one clear best, 3 = harder choice
    let regionSizeVariance: Double  // 0 = equal sizes, 1 = very different sizes
    let cherryChance: Double
    let beeChance: Double
    let gemChance: Double

    static func forPuzzle(_ n: Int) -> DifficultyParams {
        let stage = min(n / 10, 8)
        return DifficultyParams(
            rows:               9 + stage / 3,
            cols:               9 + stage / 3,
            wallBudget:         5 + stage,
            // Early: 2 regions, one clearly bigger. Late: 3 regions, similar sizes
            numRegions:         stage < 4 ? 2 : 3,
            regionSizeVariance: stage < 4 ? 0.6 : 0.2,
            cherryChance:       0.06,
            beeChance:          stage >= 3 ? 0.04 : 0.0,
            gemChance:          stage >= 2 ? 0.02 : 0.0   // rare, high value
        )
    }
}

// MARK: - Generator
struct InfinitePuzzleGenerator {

    static func generate(puzzleNumber: Int) -> PuzzleData {
        let params = DifficultyParams.forPuzzle(puzzleNumber)
        for attempt in 0..<200 {
            let seed = UInt64(puzzleNumber &+ 1) &* 6364136223846793005
                     &+ UInt64(attempt) &* 2862933555777941757 &+ 1
            var rng = SeededRNG(seed: seed)
            if let puzzle = tryGenerate(params: params, rng: &rng) { return puzzle }
        }
        return makeFallback(params: params)
    }

    // MARK: - Core generation (backwards design)
    private static func tryGenerate(params: DifficultyParams, rng: inout SeededRNG) -> PuzzleData? {
        let rows = params.rows, cols = params.cols
        let dirs4 = [(-1,0),(1,0),(0,-1),(0,1)]
        func inBounds(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < rows && c >= 0 && c < cols }
        func encode(_ r: Int, _ c: Int) -> Int { r * 200 + c }
        func decode(_ v: Int) -> (Int, Int) { (v / 200, v % 200) }
        func key(_ r: Int, _ c: Int) -> String { "\(r)-\(c)" }

        // ── Step 1: Place horse in central third ──────────────────────────────
        let rMin = rows / 3, rMax = rows * 2 / 3
        let cMin = cols / 3, cMax = cols * 2 / 3
        let horseRow = rng.nextInt(in: rMin..<rMax)
        let horseCol = rng.nextInt(in: cMin..<cMax)

        // ── Step 2: Flood-fill to find all reachable tiles from horse ─────────
        // Start with empty grid, BFS to get full reachable area
        func floodFill(from start: (Int,Int), blocked: Set<Int>) -> Set<Int> {
            var visited = Set<Int>()
            var queue = [start]
            while !queue.isEmpty {
                let (r, c) = queue.removeFirst()
                let enc = encode(r, c)
                if visited.contains(enc) { continue }
                if blocked.contains(enc) { continue }
                if !inBounds(r, c) { continue }
                visited.insert(enc)
                for (dr, dc) in dirs4 { queue.append((r+dr, c+dc)) }
            }
            return visited
        }

        let allReachable = floodFill(from: (horseRow, horseCol), blocked: [])
        var reachableArr = Array(allReachable)
        rng.shuffle(&reachableArr)

        // ── Step 3: Carve out N regions around the horse ──────────────────────
        // Each region is a contiguous blob grown from a seed near the horse.
        // Region sizes are controlled by variance param — early puzzles have
        // one big region and one small (obvious best choice), later puzzles
        // have similar sizes (harder to decide).
        let numRegions = params.numRegions
        let totalArea = reachableArr.count

        // Target sizes — variance controls how different they are
        var targetSizes: [Int] = []
        let baseSize = totalArea / (numRegions + 2)  // leave ~2/3 outside regions
        for i in 0..<numRegions {
            if i == 0 && params.regionSizeVariance > 0.4 {
                // First region is the "big" obvious one in easy mode
                targetSizes.append(Int(Double(baseSize) * (1.0 + params.regionSizeVariance)))
            } else {
                let variance = rng.nextDouble() * params.regionSizeVariance * 0.5
                targetSizes.append(Int(Double(baseSize) * (0.8 + variance)))
            }
        }

        // Seed each region from a different quadrant around the horse
        let offsets: [(Int,Int)] = [(-2,-2), (-2,2), (2,-2), (2,2), (0,-3), (0,3), (-3,0), (3,0)]
        var regionSeeds: [(Int,Int)] = []
        var usedOffsets = offsets
        rng.shuffle(&usedOffsets)

        for offset in usedOffsets {
            if regionSeeds.count >= numRegions { break }
            let sr = horseRow + offset.0
            let sc = horseCol + offset.1
            guard inBounds(sr, sc) else { continue }
            // Don't seed two regions too close together
            let tooClose = regionSeeds.contains { abs($0.0 - sr) + abs($0.1 - sc) < 3 }
            if !tooClose { regionSeeds.append((sr, sc)) }
        }
        guard regionSeeds.count >= numRegions else { return nil }

        // Grow each region via BFS up to its target size
        var regionTiles: [Set<Int>] = Array(repeating: [], count: numRegions)
        var allRegionTiles = Set<Int>()
        allRegionTiles.insert(encode(horseRow, horseCol))

        for i in 0..<numRegions {
            let seed = regionSeeds[i]
            var region = Set<Int>()
            var queue = [seed]
            var frontier: [(Int,Int)] = []

            while region.count < targetSizes[i] {
                if queue.isEmpty {
                    if frontier.isEmpty { break }
                    rng.shuffle(&frontier)
                    queue = [frontier.removeFirst()]
                }
                let (r, c) = queue.removeFirst()
                let enc = encode(r, c)
                if region.contains(enc) { continue }
                if allRegionTiles.contains(enc) { continue }
                if !inBounds(r, c) { continue }
                region.insert(enc)
                allRegionTiles.insert(enc)
                var neighbors = dirs4.map { (r+$0.0, c+$0.1) }
                rng.shuffle(&neighbors)
                for n in neighbors {
                    if inBounds(n.0, n.1) { frontier.append(n) }
                }
            }
            regionTiles[i] = region
        }

        // Verify regions are non-empty and non-overlapping
        guard regionTiles.allSatisfy({ !$0.isEmpty }) else { return nil }

        // ── Step 4: Build water boundaries between regions ────────────────────
        // Water goes on tiles that are adjacent to two different regions,
        // or adjacent to a region and "outside" — this creates the walls.
        // We also add a border ring of water to frame the puzzle.
        var waterSet = Set<Int>()

        // Find boundary tiles — adjacent to any region but not in a region
        for enc in allReachable {
            let (r, c) = decode(enc)
            if allRegionTiles.contains(enc) { continue }
            // Check if adjacent to any region
            let adjToRegion = dirs4.contains { (dr, dc) in
                inBounds(r+dr, c+dc) && allRegionTiles.contains(encode(r+dr, c+dc))
            }
            if adjToRegion { waterSet.insert(enc) }
        }

        // Add partial border ring — 50% fill on actual edges for framing
        for c in 0..<cols {
            if rng.nextBool(probability: 0.5) { waterSet.insert(encode(0, c)) }
            if rng.nextBool(probability: 0.5) { waterSet.insert(encode(rows-1, c)) }
        }
        for r in 1..<(rows-1) {
            if rng.nextBool(probability: 0.5) { waterSet.insert(encode(r, 0)) }
            if rng.nextBool(probability: 0.5) { waterSet.insert(encode(r, cols-1)) }
        }

        // ── Step 5: Find gap tiles (boundary tiles NOT made water) ────────────
        // These are the tiles the player needs to wall off.
        // We want exactly wallBudget gaps total across all region boundaries.
        // Strategy: for each region, find its "exits" (boundary tiles touching outside)
        // and keep wallBudget of them open, make rest water.
        var allExits: [Int] = []  // boundary tiles adjacent to horse's free space
        let horseFree = floodFill(from: (horseRow, horseCol), blocked: waterSet)

        for enc in waterSet {
            let (r, c) = decode(enc)
            // An "exit" is a water tile that, if removed, would connect a region to open space
            let adjToOpen = dirs4.contains { (dr, dc) in
                inBounds(r+dr, c+dc) && horseFree.contains(encode(r+dr, c+dc))
            }
            let adjToRegion = dirs4.contains { (dr, dc) in
                inBounds(r+dr, c+dc) && allRegionTiles.contains(encode(r+dr, c+dc))
            }
            if adjToOpen && adjToRegion { allExits.append(enc) }
        }

        // We want wallBudget exits to remain open (as gaps for the player to fill)
        rng.shuffle(&allExits)
        let gapCount = min(params.wallBudget, allExits.count)
        guard gapCount >= 2 else { return nil }

        // Keep first gapCount as open gaps, rest become water
        let gaps = Set(allExits.prefix(gapCount))
        // Remove gaps from water (they're the spots players will wall)
        for gap in gaps { waterSet.remove(gap) }

        // ── Step 6: Build terrain ─────────────────────────────────────────────
        var terrain = Array(repeating: Array(repeating: "g", count: cols), count: rows)
        for enc in waterSet {
            let (r, c) = decode(enc)
            terrain[r][c] = "w"
        }
        terrain[horseRow][horseCol] = "H"

        // ── Step 7: Viability check ───────────────────────────────────────────
        let puzzle0 = PuzzleData(rows: rows, cols: cols, tiles: terrain,
                                 wallCount: params.wallBudget,
                                 horseRow: horseRow, horseCol: horseCol)
        let noWalls = Array(repeating: Array(repeating: false, count: cols), count: rows)
        // Horse must be able to escape with no walls
        guard GameEngine.enclosedTiles(puzzle: puzzle0, walls: noWalls).isEmpty else { return nil }
        // Must have enough grass tiles to place all walls
        let grassCount = terrain.flatMap { $0 }.filter { $0 == "g" }.count
        guard grassCount >= params.wallBudget else { return nil }

        // ── Step 8: Cherries and bees ─────────────────────────────────────────
        // Place inside regions so they reward (or punish) enclosing them
        for enc in allRegionTiles {
            let (r, c) = decode(enc)
            guard terrain[r][c] == "g" else { continue }
            // Never place specials on the outer edge — unreachable for enclosure
            guard r > 0 && r < rows-1 && c > 0 && c < cols-1 else { continue }
            if rng.nextBool(probability: params.gemChance) { terrain[r][c] = "gem" }
            else if rng.nextBool(probability: params.cherryChance) { terrain[r][c] = "c" }
            else if rng.nextBool(probability: params.beeChance) { terrain[r][c] = "b" }
        }

        return PuzzleData(rows: rows, cols: cols, tiles: terrain,
                          wallCount: params.wallBudget,
                          horseRow: horseRow, horseCol: horseCol)
    }

    // MARK: - Fallback
    private static func makeFallback(params: DifficultyParams) -> PuzzleData {
        let rows = params.rows, cols = params.cols
        var tiles = Array(repeating: Array(repeating: "g", count: cols), count: rows)
        for c in 0..<cols { tiles[0][c] = "w"; tiles[rows-1][c] = "w" }
        for r in 1..<(rows-1) { tiles[r][0] = "w"; tiles[r][cols-1] = "w" }
        let hr = rows/2, hc = cols/2
        tiles[hr][hc] = "H"
        return PuzzleData(rows: rows, cols: cols, tiles: tiles,
                          wallCount: params.wallBudget, horseRow: hr, horseCol: hc)
    }
}
