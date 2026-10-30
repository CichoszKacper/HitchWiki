//
//  HomeView.swift
//  HitchWiki
//
//  Plain home screen: the title, a search field, the places nearest to the user,
//  and while searching the matching pages. The redesign of this screen comes later.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var router = Router()
    @State private var location = LocationManager()
    @State private var isSearching = false
    @Namespace private var transition

    private var showsAllResults: Bool {
        self.isSearching || !self.viewModel.query.isEmpty
    }

    var body: some View {
        NavigationStack(path: self.$router.path) {
            List {
                if !self.viewModel.nearbyMatches.isEmpty {
                    Section("Near you") {
                        ForEach(self.viewModel.nearbyMatches) { place in
                            NavigationLink(value: PageRoute(title: place.page.title, zoomsFromSource: true)) {
                                HStack {
                                    Label(place.page.title, systemImage: "location.fill")
                                    Spacer()
                                    Text(place.distance.formattedDistance)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .matchedTransitionSource(id: place.page.title, in: self.transition)
                        }
                    }
                }

                if self.showsAllResults {
                    Section {
                        ForEach(self.viewModel.otherMatches) { page in
                            NavigationLink(value: PageRoute(title: page.title, zoomsFromSource: true)) {
                                Text(page.title)
                            }
                            .matchedTransitionSource(id: page.title, in: self.transition)
                        }
                    } header: {
                        if !self.viewModel.nearbyMatches.isEmpty {
                            Text("All places")
                        }
                    }
                } else {
                    Section {
                        Text("Search for a city or a country")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if self.showsAllResults && !self.viewModel.query.isEmpty
                    && self.viewModel.nearbyMatches.isEmpty && self.viewModel.otherMatches.isEmpty {
                    ContentUnavailableView.search(text: self.viewModel.query)
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
        // One position is enough for "Near you": stop as soon as it arrives.
        .onAppear {
            self.location.start()
        }
        .onDisappear {
            self.location.stop()
        }
        .onChange(of: self.location.location) { _, newLocation in
            if let newLocation {
                self.viewModel.updateNearby(from: newLocation)
                self.location.stop()
            }
        }
    }
}

#Preview {
    HomeView()
}
