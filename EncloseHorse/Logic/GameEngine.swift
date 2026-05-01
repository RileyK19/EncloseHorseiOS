//
//  GameEngine.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/23/26.
//

import Foundation

// MARK: - Game Engine
struct GameEngine {

    // MARK: - Check if horse is enclosed
    static func enclosedTiles(puzzle: PuzzleData, walls: [[Bool]]) -> Set<String> {
        let rows = puzzle.rows
        let cols = puzzle.cols
        let horsePos = (puzzle.horseRow, puzzle.horseCol)

        // Build portal pair map: portalKey -> list of (r,c) positions
        var portalPositions: [String: [(Int, Int)]] = [:]
        for r in 0..<rows {
            for c in 0..<cols {
                let t = puzzle.tiles[r][c]
                if t.isPortal {
                    portalPositions[t, default: []].append((r, c))
                }
            }
        }

        var visited = Set<String>()
        var queue: [(Int, Int)] = [horsePos]
        var reachesBorder = false

        func key(_ r: Int, _ c: Int) -> String { "\(r)-\(c)" }

        while !queue.isEmpty {
            let (r, c) = queue.removeFirst()
            let k = key(r, c)
            if visited.contains(k) { continue }
            visited.insert(k)

            // If this tile is a portal, also enqueue the paired portal tile(s)
            let thisTile = puzzle.tiles[r][c]
            if thisTile.isPortal, let partners = portalPositions[thisTile] {
                for (pr, pc) in partners {
                    let pk = key(pr, pc)
                    if !visited.contains(pk) && !walls[pr][pc] {
                        queue.append((pr, pc))
                    }
                }
            }

            for (dr, dc) in [(-1,0),(1,0),(0,-1),(0,1)] {
                let nr = r + dr
                let nc = c + dc
                if nr < 0 || nr >= rows || nc < 0 || nc >= cols {
                    reachesBorder = true
                    continue
                }
                let nk = key(nr, nc)
                if visited.contains(nk) { continue }
                let tileStr = puzzle.tiles[nr][nc]
                let tileType = TileType(rawValue: tileStr) ?? .grass
                // Portals are passable (treated like grass)
                if tileType == .water { continue }
                if walls[nr][nc] { continue }
                queue.append((nr, nc))
            }
        }

        if reachesBorder { return [] }
        return visited
    }

    // MARK: - Horse escape path (all tiles reachable from horse when NOT enclosed)
    /// Returns the full set of tiles the horse can reach (i.e. its escape route).
    /// Returns empty set when the horse IS enclosed (no escape path to show).
    static func escapePath(puzzle: PuzzleData, walls: [[Bool]]) -> Set<String> {
        guard enclosedTiles(puzzle: puzzle, walls: walls).isEmpty else { return [] }

        let rows = puzzle.rows
        let cols = puzzle.cols
        
        func key(_ r: Int, _ c: Int) -> String { "\(r)-\(c)" }
        
        let start = (puzzle.horseRow, puzzle.horseCol)
        
        var queue: [(Int,Int)] = [start]
        var visited = Set<String>()
        var parent: [String:String] = [:]

        // Portal mapping
        var portalPositions: [String: [(Int,Int)]] = [:]
        for r in 0..<rows {
            for c in 0..<cols {
                let t = puzzle.tiles[r][c]
                if t.isPortal {
                    portalPositions[t, default: []].append((r,c))
                }
            }
        }

        var exitKey: String? = nil
        
        while !queue.isEmpty {
            let (r,c) = queue.removeFirst()
            let k = key(r,c)
            
            if visited.contains(k) { continue }
            visited.insert(k)
            
            // If touching boundary → escaped
            if r < 0 || r >= rows || c < 0 || c >= cols {
                exitKey = k
                break
            }
            
            let tile = puzzle.tiles[r][c]

            // Portal teleport
            if tile.isPortal, let partners = portalPositions[tile] {
                for (pr,pc) in partners where !(pr == r && pc == c) {
                    let pk = key(pr,pc)
                    if !visited.contains(pk) && !walls[pr][pc] {
                        parent[pk] = k
                        queue.append((pr,pc))
                    }
                }
            }

            for (dr,dc) in [(-1,0),(1,0),(0,-1),(0,1)] {
                let nr = r + dr
                let nc = c + dc
                
                // Escape condition
                if nr < 0 || nr >= rows || nc < 0 || nc >= cols {
                    exitKey = k
                    queue.removeAll()
                    break
                }
                
                let nk = key(nr,nc)
                if visited.contains(nk) { continue }
                
                let t = puzzle.tiles[nr][nc]
                if TileType(rawValue: t) == .water { continue }
                if walls[nr][nc] { continue }
                
                parent[nk] = k
                queue.append((nr,nc))
            }
        }

        guard let end = exitKey else { return [] }

        // Reconstruct path
        var path: [String] = []
        var current: String? = end
        
        while let k = current {
            path.append(k)
            current = parent[k]
        }

        return Set(path.reversed())
    }

    // MARK: - Calculate score
    // Matches the site: base + cherries*3 - bees*5 + gems*10
    // Our tile codes: "c"=cherry, "b"=bee, "gem"=golden apple
    static func calculateScore(puzzle: PuzzleData, walls: [[Bool]]) -> (enclosed: Int, cherries: Int, bees: Int, gems: Int, total: Int) {
        let tiles = enclosedTiles(puzzle: puzzle, walls: walls)

        var cherryCount = 0
        var beeCount = 0
        var gemCount = 0
        for key in tiles {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let r = parts[0], c = parts[1]
            let t = puzzle.tiles[r][c]
            if t == "c"   { cherryCount += 1 }
            if t == "b"   { beeCount += 1 }
            if t == "gem" { gemCount += 1 }
        }

        let base  = tiles.count
        let total = base + cherryCount * 3 - beeCount * 5 + gemCount * 10
        return (base, cherryCount, beeCount, gemCount, total)
    }

    // MARK: - Count walls used
    static func wallsUsed(_ walls: [[Bool]]) -> Int {
        walls.flatMap { $0 }.filter { $0 }.count
    }
}
