//
//  HomeView.swift
//  HitchWiki
//
//  Plain port of the old main menu: a title, a search field and the matching pages.
//  The redesign of this screen comes later.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var router = Router()
    @State private var isSearching = false
    @Namespace private var transition

    var body: some View {
        NavigationStack(path: self.$router.path) {
            Group {
                if self.isSearching || !self.viewModel.query.isEmpty {
                    self.results
                } else {
                    self.welcome
                }
            }
            .navigationTitle("HitchWiki")
            .searchable(text: self.$viewModel.query, isPresented: self.$isSearching, prompt: "Type a city or a country...")
            .onChange(of: self.viewModel.query) {
                self.viewModel.search()
            }
            .task {
                self.viewModel.loadData()
            }
            .navigationDestination(for: PageRoute.self) { route in
                if route.zoomsFromSource {
                    PageView(title: route.title)
                        .navigationTransition(.zoom(sourceID: route.title, in: self.transition))
                } else {
                    PageView(title: route.title)
                }
            }
        }
        .environment(self.router)
    }

    private var results: some View {
        List(self.viewModel.filteredPages) { page in
            NavigationLink(value: PageRoute(title: page.title, zoomsFromSource: true)) {
                Text(page.title)
            }
            .matchedTransitionSource(id: page.title, in: self.transition)
        }
        .overlay {
            if self.viewModel.filteredPages.isEmpty && !self.viewModel.query.isEmpty {
                ContentUnavailableView.search(text: self.viewModel.query)
            }
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("HitchWiki", systemImage: "hand.thumbsup.fill")
        } description: {
            Text("Search for a city or a country")
        }
    }
}

#Preview {
    HomeView()
}
