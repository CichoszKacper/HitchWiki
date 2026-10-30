//
//  AnimatedMeshBackground.swift
//  HitchWiki
//
//  A slowly drifting gradient. The same seed (e.g. a page title) always gets the same colours.
//

import SwiftUI

struct AnimatedMeshBackground: View {
    let seed: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let palettes: [[Color]] = [
        [.orange, .pink, .purple],      // sunset
        [.teal, .blue, .indigo],        // ocean
        [.mint, .green, .teal],         // forest
        [.yellow, .orange, .red],       // desert
        [.purple, .indigo, .blue]       // dusk
    ]

    private var colors: [Color] {
        let hash = self.seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let palette = Self.palettes[abs(hash) % Self.palettes.count]
        return [
            palette[0], palette[0], palette[1],
            palette[1], palette[1], palette[2],
            palette[2], palette[2], palette[0]
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: self.reduceMotion)) { timeline in
            let time = Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            let centerX: Float = 0.5 + 0.18 * sin(time * 0.5)
            let centerY: Float = 0.5 + 0.14 * cos(time * 0.4)
            let points: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(centerX, centerY), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
            ]
            MeshGradient(width: 3, height: 3, points: points, colors: self.colors)
        }
    }
}

#Preview {
    AnimatedMeshBackground(seed: "Kraków")
        .frame(height: 300)
}
