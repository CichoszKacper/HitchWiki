//
//  CollapsibleCard.swift
//  HitchWiki
//
//  A card whose header toggles its content open and closed with a spring.
//

import SwiftUI

struct CollapsibleCard<Header: View, Content: View>: View {
    @Binding var isExpanded: Bool
    private let header: () -> Header
    private let content: () -> Content

    init(isExpanded: Binding<Bool>,
         @ViewBuilder header: @escaping () -> Header,
         @ViewBuilder content: @escaping () -> Content) {
        self._isExpanded = isExpanded
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.spring) {
                    self.isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    self.header()
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(self.isExpanded ? 0 : -90))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: self.isExpanded)
            .accessibilityHint(self.isExpanded ? "Collapses the section" : "Expands the section")

            if self.isExpanded {
                self.content()
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .offset(y: -10)))
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    @Previewable @State var isExpanded = true
    CollapsibleCard(isExpanded: $isExpanded) {
        Text("Hitchhiking out").font(.title3.bold())
    } content: {
        Text("Take tram no. 8 to the last stop and walk to the petrol station.")
    }
    .padding()
    .background(Theme.background)
}
