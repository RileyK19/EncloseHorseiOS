//
//  SharedGridComponents.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/9/26.
//

import SwiftUI
import WebKit

// MARK: - Grid Interaction Protocol
/// Minimal interface the shared grid needs from either ViewModel.
@MainActor
protocol GridInteractable: AnyObject {
    var walls: [[Bool]] { get }
    var enclosedTiles: Set<String> { get }
    var escapePathTiles: Set<String> { get set }
    var showEscapePath: Bool { get set }
    var isSubmitted: Bool { get }
    var currentPuzzleData: PuzzleData? { get }
    var spriteToggle: Bool { get }

    func toggleWall(row: Int, col: Int)
    func toggleEscapePath()
}

// MARK: - ZoomableGridView (shared)
struct ZoomableGridView<VM: GridInteractable & Observable>: View {
    let vm: VM
    let data: PuzzleData

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var fitScale: CGFloat = 1.0
    @State private var containerSize: CGSize = .zero

    private let minScale: CGFloat = 0.4
    private let maxScale: CGFloat = 4.0
    private let tileSize: CGFloat = 40
    private let gap: CGFloat = 2
    let puzzleID: Int

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let tileStep    = tileSize + gap
                let gridWidth   = CGFloat(data.cols) * tileStep - gap
                let gridHeight  = CGFloat(data.rows) * tileStep - gap
                let computedFit = min(geo.size.width / gridWidth,
                                      geo.size.height / gridHeight) * 0.95

                GridTapCanvas(vm: vm, data: data, tileSize: tileSize, gap: gap)
                    .frame(width: gridWidth, height: gridHeight)
                    .scaleEffect(scale, anchor: .center)
                    .offset(offset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onAppear {
                        containerSize = geo.size
                        fitScale  = computedFit
                        scale     = computedFit
                        lastScale = computedFit
                    }
                    .onChange(of: puzzleID) { _, _ in
                        guard containerSize != .zero else { return }
                        let tileStep   = tileSize + gap
                        let gridWidth  = CGFloat(data.cols) * tileStep - gap
                        let gridHeight = CGFloat(data.rows) * tileStep - gap
                        let newFit     = min(containerSize.width / gridWidth,
                                             containerSize.height / gridHeight) * 0.95
                        offset = .zero; lastOffset = .zero
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            fitScale  = newFit
                            scale     = newFit
                            lastScale = newFit
                        }
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale = min(maxScale, max(minScale, lastScale * $0)) }
                            .onEnded { _ in
                                lastScale = scale
                                clampOffset(geo.size, gridWidth, gridHeight)
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                offset = CGSize(
                                    width:  lastOffset.width  + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
                            }
                            .onEnded { _ in
                                lastOffset = offset
                                clampOffset(geo.size, gridWidth, gridHeight)
                            }
                    )
            }
            .clipped()

            ZoomSlider(scale: $scale, minScale: minScale, maxScale: maxScale, fitScale: fitScale) {
                lastScale = scale
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 6, y: 3)
        .padding(.horizontal)
        .onChange(of: data.horseRow) { _, _ in
            fitScale = 0.0  // triggers onAppear recalc guard to fire again
            scale = 1.0; lastScale = 1.0
            offset = .zero; lastOffset = .zero
        }
    }

    private func clampOffset(_ containerSize: CGSize, _ gridWidth: CGFloat, _ gridHeight: CGFloat) {
        let maxX = max(0, (gridWidth  * scale - containerSize.width)  / 2 + 60)
        let maxY = max(0, (gridHeight * scale - containerSize.height) / 2 + 60)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = CGSize(width:  min(maxX, max(-maxX, offset.width)),
                            height: min(maxY, max(-maxY, offset.height)))
        }
        lastOffset = offset
    }
}

// MARK: - Grid Tap Canvas (shared)
//struct GridTapCanvas<VM: GridInteractable & Observable>: View {
//    let vm: VM
//    let data: PuzzleData
//    let tileSize: CGFloat
//    let gap: CGFloat
//
//    var body: some View {
//        VStack(spacing: gap) {
//            ForEach(0..<data.rows, id: \.self) { row in
//                HStack(spacing: gap) {
//                    ForEach(0..<data.cols, id: \.self) { col in
//                        TileCell(vm: vm, data: data, row: row, col: col, tileSize: tileSize)
//                    }
//                }
//            }
//        }
//    }
//}
struct GridTapCanvas<VM: GridInteractable & Observable>: View {
    let vm: VM
    let data: PuzzleData
    let tileSize: CGFloat
    let gap: CGFloat

    var body: some View {
        ZStack {
            // PASS 1: All sprites and overlays
            VStack(spacing: gap) {
                ForEach(0..<data.rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<data.cols, id: \.self) { col in
                            TileCell(vm: vm, data: data, row: row, col: col, tileSize: tileSize)
                        }
                    }
                }
            }
            
            // PASS 2: All backgrounds
            VStack(spacing: gap) {
                ForEach(0..<data.rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<data.cols, id: \.self) { col in
                            TileBackground(vm: vm, data: data, row: row, col: col, tileSize: tileSize)
                        }
                    }
                }
            }
        }
    }
}

// New view for just the background
struct TileBackground<VM: GridInteractable & Observable>: View {
    let vm: VM
    let data: PuzzleData
    let row: Int
    let col: Int
    let tileSize: CGFloat

    private var tileStr: String { data.tiles[row][col] }
    private var tileType: TileType { TileType(rawValue: tileStr) ?? .grass }
    private var hasWall: Bool {
        vm.walls.indices.contains(row) && vm.walls[row].indices.contains(col)
            ? vm.walls[row][col] : false
    }
    private var isEnclosed: Bool { vm.enclosedTiles.contains("\(row)-\(col)") }
    private var isEscapePath: Bool { vm.escapePathTiles.contains("\(row)-\(col)") }
    private var theme: TileColorTheme { TileColorThemes.theme(for: GachaManager.shared.activeAnimalID) }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
//            .fill(backgroundColor)
            .fill(.clear)
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 2)
            .frame(width: tileSize, height: tileSize)
    }
    
    private var backgroundColor: Color {
        if hasWall { return theme.wall }
        if tileStr.isPortal { return isEnclosed ? Color.green.opacity(0.2) : Color(.systemGray6) }

        let base = theme[tileType]
        switch tileType {
        case .water:  return base.opacity(0.35)
        case .horse:  return isEnclosed ? base.opacity(0.2) : base.opacity(0.3)
        case .cherry: return isEnclosed ? base.opacity(0.2) : isEscapePath ? theme.escape.opacity(0.18) : base.opacity(0.25)
        case .bee:    return isEnclosed ? base.opacity(0.15) : base.opacity(0.2)
        case .gem:    return isEnclosed ? base.opacity(0.2) : isEscapePath ? theme.escape.opacity(0.18) : base.opacity(0.18)
        case .grass:  return isEnclosed ? base.opacity(0.2) : isEscapePath ? theme.escape.opacity(0.12) : base.opacity(0.12)
        }
    }
}

// MARK: - Tile Cell (shared)
struct TileCell<VM: GridInteractable & Observable>: View {
    let vm: VM
    let data: PuzzleData
    let row: Int
    let col: Int
    let tileSize: CGFloat

    private var tileStr: String { data.tiles[row][col] }
    private var tileType: TileType { TileType(rawValue: tileStr) ?? .grass }
    private var hasWall: Bool {
        vm.walls.indices.contains(row) && vm.walls[row].indices.contains(col)
            ? vm.walls[row][col] : false
    }
    private var isEnclosed: Bool { vm.enclosedTiles.contains("\(row)-\(col)") }
    private var isEscapePath: Bool { vm.escapePathTiles.contains("\(row)-\(col)") }
    private var tappable: Bool { tileType == .grass && !vm.isSubmitted }

    @State private var showInfo: Bool = false

    private var infoMessage: String? {
        if tileStr.isPortal {
            let digit = tileStr.replacingOccurrences(of: "portal_", with: "")
            return "🌀 Portal \(digit)\nConnects to the other \(digit) tile — the horse can teleport between them"
        }
        switch tileType {
        case .cherry: return "🍒 Cherry\n+3 points if enclosed"
        case .bee:    return "🐝 Bee swarm\n−5 points if enclosed"
        case .gem:    return "🍎 Golden Apple\n+10 points if enclosed"
        case .water:  return "🌊 Water\nImpassable — acts as a natural wall"
        case .horse:  return vm.isSubmitted ? "🐴 Horse" : "🐴 Horse\nTap to highlight escape route"
        default:      return nil
        }
    }

    var body: some View {
        TileView(tileString: tileStr, hasWall: hasWall, isEnclosed: isEnclosed,
                 isEscapePath: isEscapePath, tileSize: tileSize, spriteToggle: vm.spriteToggle)
            .equatable()
            .contentShape(Rectangle())
            .onTapGesture {
                if tileType == .horse && !vm.isSubmitted {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.toggleEscapePath()
                    }
                } else if tappable {
                    vm.toggleWall(row: row, col: col)
                } else if infoMessage != nil {
                    showInfo = true
                }
                // Dismiss escape path when tapping anything other than the horse
                if tileType != .horse && vm.showEscapePath {
                    vm.toggleEscapePath()
                }
            }
            .popover(isPresented: $showInfo) {
                if let msg = infoMessage {
                    Text(msg)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
    }
}

// MARK: - Tile View (rendering only)
struct TileView: View, Equatable {
    let tileString: String
    let hasWall: Bool
    let isEnclosed: Bool
    let isEscapePath: Bool
    let tileSize: CGFloat
    let spriteToggle: Bool
    let scale = 1.1
    let horseScale = 1.1
    let defaultScale = 0.9
    
    @State private var isFloating = false

    static func == (lhs: TileView, rhs: TileView) -> Bool {
        lhs.tileString   == rhs.tileString &&
        lhs.hasWall      == rhs.hasWall    &&
        lhs.isEnclosed   == rhs.isEnclosed &&
        lhs.isEscapePath == rhs.isEscapePath &&
        lhs.tileSize     == rhs.tileSize &&
        lhs.spriteToggle == rhs.spriteToggle
    }
    
    private func key(_ type: String) -> String  {
        return "sprite_\(GachaManager.shared.activeAnimalID)_\(type)"
    }
    
    private var theme: TileColorTheme { TileColorThemes.theme(for: GachaManager.shared.activeAnimalID) }
    
    private func spriteExists(_ key: String) -> Bool {
        UIImage(named: key) != nil
    }

    private var tileType: TileType { TileType(rawValue: tileString) ?? .grass }

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 2)

            // Content (walls, portals, sprites)
            if hasWall {
                let useSprite = spriteExists(key("wall")) && spriteToggle
                if useSprite {
                    Image(key("wall"))
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .scaleEffect(scale)
                        .frame(width: tileSize, height: tileSize)
                } else {
                    Text("🧱").font(.system(size: tileSize * 0.6))
                }
            } else if tileString.isPortal {
                let digit = tileString.replacingOccurrences(of: "portal_", with: "")
                ZStack {
                    Circle()
                        .fill(portalColor(for: digit))
                        .frame(width: tileSize * 0.7, height: tileSize * 0.7)
                    Text(digit)
                        .font(.system(size: tileSize * 0.38, weight: .bold))
                        .foregroundStyle(.white)
                }
            } else {
                switch tileType {
                case .horse:
                    let useSprite = spriteExists(key("animal")) && spriteToggle
                    SpriteView(tileString: tileString, tileSize: tileSize, spriteToggle: spriteToggle)
                        .scaleEffect(useSprite ? horseScale : defaultScale)
                        .offset(y: isFloating ? -5 : -3)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isFloating)
                        .onAppear { isFloating = true }
                case .water:
                    let useSprite = spriteExists(key("water")) && spriteToggle
                    SpriteView(tileString: tileString, tileSize: tileSize, spriteToggle: spriteToggle)
                        .scaleEffect(useSprite ? scale : defaultScale)
                        .onAppear { isFloating = true }
                case .cherry, .gem:
                    let useSprite = spriteExists(key("bonus")) && spriteToggle
                    SpriteView(tileString: tileString, tileSize: tileSize, spriteToggle: spriteToggle)
                        .scaleEffect(useSprite ? scale : defaultScale)
                        .offset(y: isFloating ? -4 : -2)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isFloating)
                        .onAppear { isFloating = true }
                case .bee:
                    let useSprite = spriteExists(key("bee")) && spriteToggle
                    SpriteView(tileString: tileString, tileSize: tileSize, spriteToggle: spriteToggle)
                        .scaleEffect(useSprite ? scale : defaultScale)
                        .rotationEffect(.degrees(isFloating ? 5 : -5))
                        .offset(y: isFloating ? -3 : -1)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isFloating)
                        .onAppear { isFloating = true }
                case .grass:
                    SpriteView(tileString: tileString, tileSize: tileSize, spriteToggle: spriteToggle)
                }
            }

            // YELLOW TINT OVERLAY FOR ENCLOSED TILES
            if isEnclosed && !hasWall {
                RoundedRectangle(cornerRadius: 5)
//                    .fill(Color.yellow.opacity(0.75))
                    .strokeBorder(theme.enclosed.opacity(0.9), lineWidth: 2.5)
                    .fill(theme.enclosed.opacity(0.25))
                    .allowsHitTesting(false)
            }

            // ESCAPE PATH BORDER (on top of everything)
            if isEscapePath {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(theme.escape.opacity(0.9), lineWidth: 2.5)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: tileSize, height: tileSize)
    }
    
    private var backgroundColor: Color {
        if hasWall { return theme.wall }
        if tileString.isPortal { return isEnclosed ? Color.green.opacity(0.2) : Color(.systemGray6) }

        let base = theme[tileType]
        switch tileType {
        case .water:  return base.opacity(0.35)
        case .horse:  return isEnclosed ? base.opacity(0.2) : base.opacity(0.3)
        case .cherry: return isEnclosed ? base.opacity(0.2) : isEscapePath ? theme.escape.opacity(0.18) : base.opacity(0.25)
        case .bee:    return isEnclosed ? base.opacity(0.15) : base.opacity(0.2)
        case .gem:    return isEnclosed ? base.opacity(0.2) : isEscapePath ? theme.escape.opacity(0.18) : base.opacity(0.18)
        case .grass:  return isEnclosed ? base.opacity(0.2) : isEscapePath ? theme.escape.opacity(0.12) : base.opacity(0.12)
        }
    }

    private var defaultColor: Color {
        switch tileType {
        case .grass:  return .green
        case .water:  return .blue
        case .horse:  return .green
        case .cherry: return .yellow
        case .bee:    return .orange
        case .gem:    return .yellow
        }
    }

    private func portalColor(for digit: String) -> Color {
        let colors: [Color] = [.purple, .cyan, .pink, .indigo, .mint, .teal, .orange, .red, .brown, .blue]
        let idx = Int(digit) ?? 0
        return colors[idx % colors.count]
    }
}

// MARK: - Zoom Slider (unchanged)
struct ZoomSlider: View {
    @Binding var scale: CGFloat
    let minScale: CGFloat
    let maxScale: CGFloat
    let fitScale: CGFloat
    let onChange: () -> Void

    private var isAtFit: Bool { abs(scale - fitScale) < 0.01 }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary).font(.caption)
            Slider(value: $scale, in: minScale...maxScale) { _ in onChange() }.tint(.blue)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary).font(.caption)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    scale = fitScale; onChange()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(isAtFit ? Color.secondary.opacity(0.4) : .blue)
                    .font(.body)
            }
            .disabled(isAtFit)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

// MARK: - StatPill (unchanged)
struct StatPill: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(icon).font(.title3)
            Text(value).font(.headline.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

// MARK: - Success Banner (unchanged)
struct SuccessBanner: View {
    let score: Int
    let optimalScore: Int
    let dismiss: () -> Void

    private var isOptimal: Bool { optimalScore > 0 && score >= optimalScore }
    private var pct: Int {
        guard optimalScore > 0 else { return 0 }
        return min(100, Int(Double(score) / Double(optimalScore) * 100))
    }
    private var medal: String {
        if isOptimal    { return "🏆" }
        if pct >= 90    { return "🥇" }
        if pct >= 70    { return "🥈" }
        if pct >= 50    { return "🥉" }
        return "🏅"
    }
    private var resultText: String {
        if optimalScore <= 0 { return "Score: \(score)" }
        if isOptimal         { return "\(score)/\(optimalScore) — perfect!" }
        return "\(score)/\(optimalScore) optimal (\(pct)%)"
    }

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Text(medal).font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOptimal ? "Optimal solve! 🎉" : "Submitted!").font(.headline.bold())
                    Text(resultText).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 8)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { dismiss() } }
    }
}

// MARK: - Offline Banner (unchanged)
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash").font(.caption)
            Text("Offline — showing last puzzle").font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.orange.opacity(0.85), in: Capsule())
    }
}

// MARK: - Loading / Error
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Loading today's puzzle...").foregroundStyle(.secondary)
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 48)).foregroundStyle(.orange)
            Text("Couldn't load puzzle").font(.title2.bold())
            Text(message).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Try Again", action: retry).buttonStyle(.borderedProminent)
        }
    }
}// MARK: - WebView Representable (for optimal scraping UI context)
struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@Observable
class ReadOnlyGridVM: GridInteractable {
    var walls: [[Bool]]
    var enclosedTiles: Set<String> = []
    var escapePathTiles: Set<String> = []
    var showEscapePath: Bool = false
    var isSubmitted: Bool = true  // prevents any interaction
    var currentPuzzleData: PuzzleData?
    var spriteToggle: Bool = true

    init(data: PuzzleData, walls: [[Bool]]) {
        self.currentPuzzleData = data
        self.walls = walls
        self.enclosedTiles = GameEngine.enclosedTiles(puzzle: data, walls: walls)
    }

    func toggleWall(row: Int, col: Int) {}
    func toggleEscapePath() {}
}

struct SolutionGridView: View {
    let data: PuzzleData
    let walls: [[Bool]]

    var body: some View {
        let vm = ReadOnlyGridVM(data: data, walls: walls)
        ZoomableGridView(vm: vm, data: data, puzzleID: 0)
    }
}

