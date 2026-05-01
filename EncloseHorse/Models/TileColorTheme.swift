//
//  TileColorTheme.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/13/26.
//

import SwiftUI

struct TileColorTheme {
    var grass:    Color = .green
    var water:    Color = .blue
    var horse:    Color = .green
    var cherry:   Color = .yellow
    var bee:      Color = .orange
    var gem:      Color = .yellow
    var wall:     Color = Color(.systemGray4)
    var enclosed: Color = .yellow
    var escape:   Color = .orange

    subscript(type: TileType) -> Color {
        switch type {
        case .grass:  return grass
        case .water:  return water
        case .horse:  return horse
        case .cherry: return cherry
        case .bee:    return bee
        case .gem:    return gem
        }
    }
}

enum TileColorThemes {
    static let themes: [String: TileColorTheme] = [
        "dumpling": TileColorTheme(
            grass: .yellow, water: .red, horse: .green,
            cherry: .green, bee: .gray, gem: .blue,
            wall: .gray,
            enclosed: .white, escape: .brown
        ),
    ]

    static func theme(for animalID: String) -> TileColorTheme {
        themes[animalID] ?? TileColorTheme()
    }
}
