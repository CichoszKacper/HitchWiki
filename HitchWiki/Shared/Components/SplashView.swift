//
//  SplashView.swift
//  HitchWise
//
//  Picks up where the launch screen (Base.lproj/LaunchScreen.storyboard) leaves off: it starts with
//  exactly the same picture, then the cardboard sign swings and the thumbs-up sticker pops and waves,
//  and everything grows and fades away to reveal the app. Keep the sizes and offsets in step with the
//  storyboard.
//

import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void

    @State private var trigger = 0
    @State private var isLeaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Same layout as the storyboard: offsets from the centre of the whole screen.
    private static let markSize: CGFloat = 210
    private static let markOffset: CGFloat = -56
    private static let titleOffset: CGFloat = 74
    /// Where the layers turn, as a fraction of the 210 pt canvas (see tools/brand/mark.py):
    /// the sign hangs from its tape, the thumb pivots on the wrist.
    nonisolated private static let signPivot = UnitPoint(x: 0.5, y: 0.37)
    nonisolated private static let thumbPivot = UnitPoint(x: 0.6, y: 0.76)

    var body: some View {
        ZStack {
            Image("LaunchSign")
                .resizable()
                .frame(width: Self.markSize, height: Self.markSize)
                .keyframeAnimator(initialValue: 0.0, trigger: self.trigger) { content, angle in
                    content.rotationEffect(.degrees(angle), anchor: Self.signPivot)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(-6, duration: 0.22)
                        SpringKeyframe(4, duration: 0.22)
                        SpringKeyframe(0, duration: 0.35)
                    }
                }
                .offset(y: Self.markOffset)

            Image("LaunchThumb")
                .resizable()
                .frame(width: Self.markSize, height: Self.markSize)
                .keyframeAnimator(initialValue: Pop(), trigger: self.trigger) { content, pop in
                    content
                        .rotationEffect(.degrees(pop.angle), anchor: Self.thumbPivot)
                        .scaleEffect(pop.scale, anchor: Self.thumbPivot)
                        .offset(y: pop.lift)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.14, duration: 0.2)
                        SpringKeyframe(1, duration: 0.45)
                    }
                    KeyframeTrack(\.lift) {
                        SpringKeyframe(-14, duration: 0.2)
                        SpringKeyframe(0, duration: 0.45)
                    }
                    KeyframeTrack(\.angle) {
                        LinearKeyframe(0, duration: 0.08)
                        SpringKeyframe(-12, duration: 0.16)
                        SpringKeyframe(9, duration: 0.16)
                        SpringKeyframe(0, duration: 0.3)
                    }
                }
                .offset(y: Self.markOffset)

            Text(verbatim: "HitchWise")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(.white)
                .offset(y: Self.titleOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Image("LaunchBackground")
                .resizable()
                .scaledToFill()
        }
        .scaleEffect(self.isLeaving ? 1.12 : 1)
        .opacity(self.isLeaving ? 0 : 1)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task {
            await self.play()
        }
    }

    private func play() async {
        if self.reduceMotion {
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.3)) {
                self.isLeaving = true
            }
            try? await Task.sleep(for: .milliseconds(300))
            self.onFinished()
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        self.trigger += 1
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.easeIn(duration: 0.32)) {
            self.isLeaving = true
        }
        try? await Task.sleep(for: .milliseconds(320))
        self.onFinished()
    }

    private struct Pop {
        var scale: Double = 1
        var lift: Double = 0
        var angle: Double = 0
    }
}

#Preview {
    SplashView {}
}
