//
//  AnimalTheme.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/10/26.
//

import SwiftUI

// MARK: - Tier
enum AnimalTier: String, Codable, CaseIterable {
    case a  = "A"
    case s  = "S"
    case ss = "SS"

    var color: Color {
        switch self {
        case .a:  return .gray
        case .s:  return .blue
        case .ss: return .purple
        }
    }

    var label: String { rawValue }
}

// MARK: - Tile Skin
/// Emoji placeholders — swap in Image(assetName) later per tile
struct TileSkin {
    let grass:  String  // background tile
    let water:  String  // impassable tile
    let wall:   String  // placed wall
    let animal: String  // main character
    let bonus:  String  // cherry equivalent (+3)
    let hazard: String  // bee equivalent (-5)
    let gem:    String  // gem equivalent (+10)
}

// MARK: - Animal
struct Animal: Identifiable, Codable {
    let id: String          // stable identifier e.g. "horse", "penguin"
    let name: String
    let tier: AnimalTier

    // Emoji skin (used until real sprites are drawn)
    var skin: TileSkin { AnimalTheme.skin(for: id) }
}

// MARK: - Animal Registry
enum AnimalTheme {

    // MARK: - All animals
    static let all: [Animal] = [
        // ── A tier ──────────────────────────────────────────────
        Animal(id: "horse",    name: "Horse",    tier: .a),
        Animal(id: "dog",      name: "Dog",      tier: .a),
        Animal(id: "cat",      name: "Cat",      tier: .a),
        Animal(id: "rabbit",   name: "Rabbit",   tier: .a),
        Animal(id: "bear",     name: "Bear",     tier: .a),
        // ── S tier ──────────────────────────────────────────────
        Animal(id: "penguin",  name: "Penguin",  tier: .s),
        Animal(id: "fox",      name: "Fox",      tier: .s),
        Animal(id: "capybara", name: "Capybara", tier: .s),
        Animal(id: "axolotl",  name: "Axolotl",  tier: .s),
        // ── SS tier ─────────────────────────────────────────────
        Animal(id: "dragon",   name: "Dragon",   tier: .ss),
        Animal(id: "unicorn",  name: "Unicorn",  tier: .ss),
        Animal(id: "goldhorse",name: "Golden Horse", tier: .ss),
    ]

    static func animal(id: String) -> Animal {
        all.first { $0.id == id } ?? all[0]
    }

    // MARK: - Emoji skins per animal
    static func skin(for id: String) -> TileSkin {
        switch id {
        case "horse":
            return TileSkin(grass: "🟩", water: "🌊", wall: "🧱",
                            animal: "🐴", bonus: "🍒", hazard: "🐝", gem: "🍎")
        case "dog":
            return TileSkin(grass: "🟩", water: "🌊", wall: "🧱",
                            animal: "🐶", bonus: "🦴", hazard: "🐝", gem: "⭐️")
        case "cat":
            return TileSkin(grass: "🟩", water: "🌊", wall: "🧱",
                            animal: "🐱", bonus: "🐟", hazard: "🐝", gem: "💎")
        case "rabbit":
            return TileSkin(grass: "🟩", water: "🌊", wall: "🧱",
                            animal: "🐰", bonus: "🥕", hazard: "🐝", gem: "🌟")
        case "bear":
            return TileSkin(grass: "🟩", water: "🌊", wall: "🧱",
                            animal: "🐻", bonus: "🍯", hazard: "🐝", gem: "🫐")
        case "penguin":
            return TileSkin(grass: "🩵", water: "🧊", wall: "❄️",
                            animal: "🐧", bonus: "🐟", hazard: "🦭", gem: "💠")
        case "fox":
            return TileSkin(grass: "🟧", water: "🌊", wall: "🪵",
                            animal: "🦊", bonus: "🍇", hazard: "🐝", gem: "🔮")
        case "capybara":
            return TileSkin(grass: "🟩", water: "💧", wall: "🪨",
                            animal: "🐾", bonus: "🌿", hazard: "🐊", gem: "🌺")
        case "axolotl":
            return TileSkin(grass: "🟦", water: "🫧", wall: "🪸",
                            animal: "🦎", bonus: "🦐", hazard: "🪼", gem: "🔵")
        case "dragon":
            return TileSkin(grass: "🟥", water: "🌋", wall: "🔥",
                            animal: "🐉", bonus: "🪙", hazard: "💀", gem: "👑")
        case "unicorn":
            return TileSkin(grass: "🌸", water: "🌈", wall: "✨",
                            animal: "🦄", bonus: "🍭", hazard: "⚡️", gem: "💫")
        case "goldhorse":
            return TileSkin(grass: "🟨", water: "🌊", wall: "🏆",
                            animal: "🐴", bonus: "💰", hazard: "⚠️", gem: "💛")
        default:
            return TileSkin(grass: "🟩", water: "🌊", wall: "🧱",
                            animal: "🐴", bonus: "🍒", hazard: "🐝", gem: "🍎")
        }
    }
}

struct AnimalPortraitView: View {
    let animal: Animal
    let size: CGFloat

    var body: some View {
        let key = "sprite_\(animal.id)_animal"
        if UIImage(named: key) != nil {
            Image(key)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(animal.skin.animal)
                .font(.system(size: size * 0.75))
        }
    }
}
