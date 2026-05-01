//
//  SpriteView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/10/26.
//

import SwiftUI

struct SpriteView: View {
    let tileString: String
    let tileSize: CGFloat
    var isEnclosed: Bool = false
    let spriteToggle: Bool

    private var animalID: String { GachaManager.shared.activeAnimalID }
    private var skin: TileSkin { GachaManager.shared.activeSkin }
    private var spriteKey: String { "sprite_\(animalID)_\(spriteName)" }

    var body: some View {
//        let _ = print("🖼️ spriteKey=\(spriteKey) exists=\(UIImage(named: spriteKey) != nil)")
        if spriteToggle && UIImage(named: spriteKey) != nil {
            Image(spriteKey)
                .resizable()
                .interpolation(.none)  // crisp pixel art
                .scaledToFit()
                .frame(width: tileSize * scale, height: tileSize * scale)
        } else {
            Text(emoji)
                .font(.system(size: tileSize * scale))
        }
    }

    // MARK: - Sprite name (matches asset naming convention in SPRITES.md)
    private var spriteName: String {
        if tileString.isPortal { return "bonus" }
        switch TileType(rawValue: tileString) ?? .grass {
        case .horse:  return "animal"
        case .grass:  return "grass"
        case .water:  return "water"
        case .cherry: return "bonus"
        case .bee:    return "hazard"
        case .gem:    return "gem"
        }
    }

    // MARK: - Emoji fallback
    private var emoji: String {
        if tileString.isPortal { return "🌀" }
        switch TileType(rawValue: tileString) ?? .grass {
        case .horse:  return skin.animal
        case .grass:  return ""
        case .water:  return skin.water
        case .cherry: return skin.bonus
        case .bee:    return skin.hazard
        case .gem:    return skin.gem
        }
    }

    private var scale: CGFloat {
        let key = "sprite_\(GachaManager.shared.activeAnimalID)_animal"
        let useSprite = UIImage(named: key) != nil

        
        if useSprite {
            return 1
        }
        
        switch TileType(rawValue: tileString) ?? .grass {
        case .horse:  return 0.65
        case .water:  return 0.60
        default:      return 0.55
        }
    }
}
