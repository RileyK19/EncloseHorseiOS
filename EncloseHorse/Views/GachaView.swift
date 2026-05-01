//
//  GachaView.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/10/26.
//

import SwiftUI

// MARK: - GachaView
struct GachaView: View {
    @State private var gacha = GachaManager.shared
    @State private var lastPulled: Animal? = nil
    @State private var showResult = false
    @State private var isAnimating = false

    @State private var pullResults: [Animal] = []
    @State private var showReveal = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Gem count
                HStack {
                    Text("💎 \(gacha.gems)")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.horizontal).padding(.top, 8)

                // Collection grid
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(AnimalTheme.all) { animal in
                            AnimalCard(animal: animal,
                                       isOwned: gacha.isOwned(animal.id),
                                       isActive: gacha.activeAnimalID == animal.id)
                                .onTapGesture {
                                    if gacha.isOwned(animal.id) {
                                        gacha.equip(animal.id)
                                    }
                                }
                        }
                    }
                    .padding()
                }

                // Pull buttons
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            performPull()
                        } label: {
                            HStack(spacing: 8) {
                                Text("✨ Pull")
                                    .font(.headline.bold())
                                Text("160 💎")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(gacha.canPull ? Color.purple : Color.gray, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                        }
                        .disabled(!gacha.canPull)
                        
                        Button {
                            performTenPull()
                        } label: {
                            HStack(spacing: 8) {
                                Text("✨ 10 Pull")
                                    .font(.headline.bold())
                                Text("1600 💎")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(gacha.gems >= 1600 ? Color.indigo : Color.gray, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                        }
                        .disabled(gacha.gems < 1600)
                    }

                    if gacha.gems < 160 {
                        Text("Need \(160 - gacha.gems) more gems")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal).padding(.bottom, 16)
                .background(.regularMaterial)
            }
            .navigationTitle("🎰 Gacha")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showResult) {
            if let animal = lastPulled {
                PullResultView(animal: animal, isPresented: $showResult)
            }
        }
        .sheet(isPresented: $showReveal) {
            RevealSheetView(results: pullResults, onDismiss: { showReveal = false })
        }
    }

    private func performPull() {
        guard let animal = gacha.pull() else { return }
        lastPulled = animal
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isAnimating = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isAnimating = false
            showResult = true
        }
    }

    private func performTenPull() {
        pullResults = (0..<10).compactMap { _ in gacha.pull() }
        showReveal = true
    }
}

// MARK: - Reveal Sheet (10-pull one by one)
struct RevealSheetView: View {
    let results: [Animal]
    let onDismiss: () -> Void

    @State private var revealed: Int = 0
    @State private var scale: CGFloat = 0.3
    @State private var opacity: CGFloat = 0

    private var current: Animal? {
        guard revealed < results.count else { return nil }
        return results[revealed]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                if let animal = current {
                    VStack(spacing: 16) {
                        AnimalPortraitView(animal: animal, size: 120)
                            .scaleEffect(scale)
                            .opacity(opacity)

                        VStack(spacing: 8) {
                            TierBadge(tier: animal.tier)
                                .scaleEffect(1.4)
                            Text(animal.name)
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                                .opacity(opacity)
                            Text(GachaManager.shared.isOwned(animal.id) ? "Already owned" : "New!")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                                .opacity(opacity)
                        }

                        Text("\(revealed + 1) / \(results.count)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 8)
                    }
                } else {
                    // All revealed summary
                    VStack(spacing: 16) {
                        Text("All done!")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)

                        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 12) {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, animal in
                                VStack(spacing: 4) {
//                                    Text(animal.skin.animal)
//                                        .font(.system(size: 36))
                                    AnimalPortraitView(animal: animal, size: 36)
                                    TierBadge(tier: animal.tier)
                                }
                            }
                        }
                        .padding()
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    if revealed < results.count {
                        Button {
                            revealed = results.count
                        } label: {
                            Text("Skip")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }

                        Button {
                            nextReveal()
                        } label: {
                            Text(revealed == results.count - 1 ? "Finish" : "Next")
                                .font(.headline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.purple, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                    } else {
                        Button {
                            onDismiss()
                        } label: {
                            Text("Done")
                                .font(.headline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.purple, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .onAppear { animateIn() }
        .onChange(of: revealed) { _, _ in
            if revealed < results.count { animateIn() }
        }
    }

    private func animateIn() {
        scale = 0.3; opacity = 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
        }
    }

    private func nextReveal() {
        withAnimation(.easeIn(duration: 0.15)) {
            scale = 1.3
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            revealed += 1
        }
    }
}

// MARK: - Animal Card
struct AnimalCard: View {
    let animal: Animal
    let isOwned: Bool
    let isActive: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? animal.tier.color.opacity(0.25) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                animal.tier == .ss ? Color.yellow :
                                animal.tier == .s ? Color.purple :
                                isActive ? animal.tier.color : Color.clear,
                                lineWidth: animal.tier == .ss || animal.tier == .s ? 2 : isActive ? 2 : 0
                            )
                            .shadow(
                                color: animal.tier == .ss ? .yellow.opacity(0.8) :
                                       animal.tier == .s ? .purple.opacity(0.8) : .clear,
                                radius: 6
                            )
                    )

                VStack(spacing: 4) {
//                    Text(animal.skin.animal)
//                        .font(.system(size: 40))
                    AnimalPortraitView(animal: animal, size: 40)
                        .opacity(isOwned ? 1.0 : 0.25)

                    TierBadge(tier: animal.tier)
                }
                .padding(.vertical, 10)

                if !isOwned {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.35))
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.title2)
                }

                if isActive {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(animal.tier.color)
                                .font(.caption)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 110)

            Text(animal.name)
                .font(.caption.bold())
                .lineLimit(1)
        }
    }
}

// MARK: - Tier Badge
struct TierBadge: View {
    let tier: AnimalTier

    var body: some View {
        Text(tier.label)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tier.color, in: Capsule())
    }
}

// MARK: - Pull Result (single pull)
struct PullResultView: View {
    let animal: Animal
    @Binding var isPresented: Bool
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

//            Text(appeared ? animal.skin.animal : "✨")
            if appeared {
                AnimalPortraitView(animal: animal, size: 100)
                    .font(.system(size: 100))
                    .scaleEffect(appeared ? 1.0 : 0.3)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)
            } else {
                Text("✨").font(.system(size: 100))
                    .font(.system(size: 100))
                    .scaleEffect(appeared ? 1.0 : 0.3)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)
            }

            VStack(spacing: 8) {
                TierBadge(tier: animal.tier)
                    .scaleEffect(1.5)
                Text(animal.name)
                    .font(.largeTitle.bold())
                Text(GachaManager.shared.isOwned(animal.id) ? "Already owned" : "New!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeIn(duration: 0.3).delay(0.2), value: appeared)

            Spacer()

            Button("Nice!") { isPresented = false }
                .buttonStyle(.borderedProminent)
                .tint(animal.tier.color)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(animal.tier.color.opacity(0.08).ignoresSafeArea())
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { appeared = true } }
    }
}
