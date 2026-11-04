//
//  SplashView.swift
//  HitchWise
//
//  Picks up where the launch screen (Base.lproj/LaunchScreen.storyboard) leaves off: it starts with
//  exactly the same picture, gives the thumbs-up a little wave with a ring pulsing out of the circle,
//  then grows and fades away to reveal the app. Keep the sizes and offsets in step with the storyboard.
//

import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void

    @State private var waveTrigger = 0
    @State private var isPulsing = false
    @State private var isLeaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Same layout as the storyboard: offsets from the centre of the whole screen.
    private static let circleSize: CGFloat = 112
    private static let circleOffset: CGFloat = -28
    private static let titleOffset: CGFloat = 74

    var body: some View {
        ZStack {
            // Ring pulsing out of the circle
            Circle()
                .stroke(.white.opacity(0.6), lineWidth: 2)
                .frame(width: Self.circleSize, height: Self.circleSize)
                .scaleEffect(self.isPulsing ? 1.9 : 1)
                .opacity(self.isPulsing ? 0 : 1)
                .offset(y: Self.circleOffset)

            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: Self.circleSize, height: Self.circleSize)
                .offset(y: Self.circleOffset)

            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)
                .keyframeAnimator(initialValue: Wave(), trigger: self.waveTrigger) { content, wave in
                    content
                        .rotationEffect(.degrees(wave.angle), anchor: .bottom)
                        .scaleEffect(wave.scale)
                        .offset(y: wave.lift)
                } keyframes: { _ in
                    KeyframeTrack(\.angle) {
                        SpringKeyframe(-20, duration: 0.18)
                        SpringKeyframe(12, duration: 0.18)
                        SpringKeyframe(0, duration: 0.3)
                    }
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.22, duration: 0.2)
                        SpringKeyframe(1, duration: 0.45)
                    }
                    KeyframeTrack(\.lift) {
                        SpringKeyframe(-10, duration: 0.2)
                        SpringKeyframe(0, duration: 0.45)
                    }
                }
                .offset(y: Self.circleOffset)

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
        self.waveTrigger += 1
        withAnimation(.easeOut(duration: 0.8)) {
            self.isPulsing = true
        }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.easeIn(duration: 0.32)) {
            self.isLeaving = true
        }
        try? await Task.sleep(for: .milliseconds(320))
        self.onFinished()
    }

    private struct Wave {
        var angle: Double = 0
        var scale: Double = 1
        var lift: Double = 0
    }
}

#Preview {
    SplashView {}
}
