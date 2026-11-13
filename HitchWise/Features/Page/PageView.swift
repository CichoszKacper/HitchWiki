//
//  PageView.swift
//  HitchWiki
//
//  One Hitchwiki page: map header, infobox chips, intro and collapsible section cards.
//  Needs a Router in the environment (HomeView provides one) so links can open other pages.
//

import SwiftUI

struct PageView: View {
    @State private var viewModel: PageViewModel
    @State private var showsNavigationBar = false
    @State private var mapSheet: MapSheetRequest?
    @Environment(Router.self) private var router

    init(title: String) {
        self._viewModel = State(initialValue: PageViewModel(title: title))
    }

    var body: some View {
        Group {
            switch self.viewModel.state {
            case .loading:
                PageLoadingView()
                    .transition(.opacity)
            case .missing:
                ContentUnavailableView("Page not found", systemImage: "exclamationmark.magnifyingglass",
                                       description: Text("“\(self.viewModel.title)” isn't in the offline Hitchwiki."))
            case .loaded(let content):
                self.page(content)
                    .transition(.opacity)
            }
        }
        .background(Theme.background)
        .navigationTitle(self.showsNavigationBar ? self.viewModel.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(self.showsNavigationBar ? .visible : .hidden, for: .navigationBar)
        // Links in the text: Hitchwiki pages open in this stack, websites in Safari.
        .opensPageLinks(with: self.router)
        .sheet(item: self.$mapSheet) { request in
            SpotsMapSheet(title: request.content.title, spots: request.content.record.spots,
                          sections: request.content.record.sections, mapFrame: request.content.mapFrame, focus: request.focus)
                .presentationDragIndicator(.visible)
        }
        .task {
            await self.viewModel.load()
        }
    }

    private func page(_ content: PageContent) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeroHeader(title: content.title, subtitle: content.subtitle, symbol: content.headerSymbol,
                                   mapFrame: content.mapFrame, spots: content.record.spots) {
                        self.mapSheet = MapSheetRequest(content: content, focus: nil)
                    }

                    if !content.facts.isEmpty {
                        FactsRow(facts: content.facts)
                            .staggeredAppear(index: 0)
                    }

                    if let intro = content.intro {
                        LinkedText(intro.text, links: intro.links)
                            .font(.title3)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .padding(.horizontal, 20)
                            .staggeredAppear(index: 1)
                    }

                    VStack(spacing: 14) {
                        ForEach(Array(content.cards.enumerated()), id: \.element.id) { index, card in
                            SectionCardView(card: card, content: content, isExpanded: self.binding(for: card)) { spot in
                                self.mapSheet = MapSheetRequest(content: content, focus: spot)
                            }
                            .id(card.id)
                            .staggeredAppear(index: index + 2)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                }
                .padding(.bottom, 40)
            }
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > PageHeroHeader.height - 140
            } action: { _, isPastHeader in
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.showsNavigationBar = isPastHeader
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !content.cards.isEmpty {
                        self.contentsMenu(content, proxy: proxy)
                    }
                    if let url = content.webURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    /// Jumps to a section, opening it first.
    private func contentsMenu(_ content: PageContent, proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(content.cards) { card in
                Button {
                    withAnimation(Theme.spring) {
                        self.viewModel.setExpanded(true, for: card)
                    }
                    Task { @MainActor in
                        // Let the card open before scrolling to it.
                        try? await Task.sleep(for: .milliseconds(80))
                        withAnimation(Theme.spring) {
                            proxy.scrollTo(card.id, anchor: UnitPoint(x: 0.5, y: 0.12))
                        }
                    }
                } label: {
                    Label(card.heading.title, systemImage: card.systemImage)
                }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
        .accessibilityLabel("Contents")
    }

    private func binding(for card: SectionCard) -> Binding<Bool> {
        Binding(
            get: { self.viewModel.isExpanded(card) },
            set: { self.viewModel.setExpanded($0, for: card) }
        )
    }
}

/// What the map sheet should show.
struct MapSheetRequest: Identifiable {
    let id = UUID()
    let content: PageContent
    /// Spot to zoom to, or nil for all spots.
    let focus: PageSpot?
}

#Preview {
    NavigationStack {
        PageView(title: "Kraków")
    }
    .environment(Router())
}
