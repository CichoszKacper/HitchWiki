//
//  SplashView.swift
//  HitchWise
//
//  Picks up where the launch screen (Base.lproj/LaunchScreen.storyboard) leaves off: the same logo on
//  the same plain background (white in light mode, black in dark mode). The logo gives a small pop, then
//  grows and fades away to reveal the app. Keep the size in step with the storyboard.
//

import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void

    @State private var isPopping = false
    @State private var isLeaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Same as the storyboard: 240 x 240 pt, centred on the screen.
    private static let logoSize: CGFloat = 240

    var body: some View {
        Image("LaunchLogo")
            .resizable()
            .scaledToFit()
            .frame(width: Self.logoSize, height: Self.logoSize)
            .scaleEffect(self.isLeaving ? 1.15 : (self.isPopping ? 1.06 : 1))
            .opacity(self.isLeaving ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).opacity(self.isLeaving ? 0 : 1))
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .task {
                await self.play()
            }
    }

    private func play() async {
        if !self.reduceMotion {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                self.isPopping = true
            }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isPopping = false
            }
            try? await Task.sleep(for: .milliseconds(350))
        } else {
            try? await Task.sleep(for: .milliseconds(200))
        }
        withAnimation(.easeIn(duration: 0.3)) {
            self.isLeaving = true
        }
        try? await Task.sleep(for: .milliseconds(300))
        self.onFinished()
    }
}

#Preview {
    SplashView {}
}
