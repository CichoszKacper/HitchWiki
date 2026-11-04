//
//  HomeView.swift
//  HitchWiki
//
//  The home screen: the country the user is in, the closest cities, and the pages opened
//  recently. Typing in the search field swaps all that for the matching pages.
//  Tapping the Home tab always comes back here: search closed, pages popped, scrolled to the top.
//  Every text is in Localizable.xcstrings (English + Polish).
//

import SwiftUI
import UIKit

struct HomeView: View {
    /// Changes every time the Home tab is tapped (RootTabView): go back to the start of the screen.
    var returnToStartTrigger = 0

    @State private var viewModel = HomeViewModel()
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var router = Router()
    @State private var location = LocationManager()
    @State private var isSearching = false
    @Environment(DatabaseSync.self) private var sync
    @Environment(\.openURL) private var openURL
    @Namespace private var transition

    private var recents: RecentPages { .shared }

    /// Recently viewed pages from the guide in use.
    private var recentPages: [RecentPage] {
        self.recents.pages(in: self.sync.dataLanguage)
    }

    private var showsAllResults: Bool {
        self.isSearching || !self.viewModel.query.isEmpty
    }

    var body: some View {
        NavigationStack(path: self.$router.path) {
            Group {
                if self.showsAllResults {
                    self.searchResults
                } else {
                    self.dashboard
                }
            }
            .navigationTitle("HitchWise")
            // An explicit placement keeps a single search field under the title. Without it, iOS 26
            // can show the field both in the navigation bar and in the bottom toolbar above the tab bar.
            .searchable(text: self.$viewModel.query,
                        isPresented: self.$isSearching,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Type a city or a country...")
            .onChange(of: self.viewModel.query) {
                self.viewModel.search()
            }
            .task {
                self.viewModel.loadData()
            }
            .navigationDestination(for: PageRoute.self) { route in
                if let sourceID = route.sourceID {
                    PageView(title: route.title)
                        .navigationTransition(.zoom(sourceID: sourceID, in: self.transition))
                } else {
                    PageView(title: route.title)
                }
            }
        }
        .environment(self.router)
        // One position is enough for "Near you": stop as soon as it arrives.
        // On first launch wait for the guide language screen, so the location prompt doesn't cover it.
        .onAppear {
            if !LanguageManager.shared.needsGuideLanguageChoice {
                self.location.start()
            }
        }
        .onChange(of: LanguageManager.shared.guideLanguage) {
            self.location.start()
        }
        .onDisappear {
            self.location.stop()
        }
        .onChange(of: self.returnToStartTrigger) {
            self.returnToStart()
        }
        .onChange(of: self.sync.revision) {
            self.viewModel.reload(location: self.location.location)
            self.viewModel.search()
        }
        .onChange(of: self.location.location) { _, newLocation in
            if let newLocation {
                self.viewModel.updateNearby(from: newLocation)
                self.location.stop()
            }
        }
    }

    /// Closes the search (and the keyboard), leaves any open page and scrolls back to the top.
    private func returnToStart() {
        withAnimation(Theme.spring) {
            self.isSearching = false
            self.viewModel.query = ""
            self.router.popToRoot()
            self.scrollPosition.scrollTo(edge: .top)
        }
        // The search field can keep the keyboard up for a moment after isSearching turns false.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if let country = self.viewModel.country {
                    self.countryCard(country)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                self.nearbySection
                    .staggeredAppear(index: 1)

                self.recentSection
                    .staggeredAppear(index: 2)
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(Theme.spring, value: self.viewModel.country)
            .animation(Theme.spring, value: self.viewModel.hasLoadedNearby)
            .animation(Theme.spring, value: self.recentPages)
        }
        .scrollPosition(self.$scrollPosition)
        .background(Theme.background)
    }

    private func countryCard(_ country: CountryOverview) -> some View {
        let sourceID = "country-\(country.title)"
        return NavigationLink(value: PageRoute(title: country.title, sourceID: sourceID)) {
            CountryCard(country: country)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .matchedTransitionSource(id: sourceID, in: self.transition) { source in
            source.clipShape(.rect(cornerRadius: Theme.cornerRadius + 4, style: .continuous))
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    @ViewBuilder
    private var nearbySection: some View {
        if self.location.isDenied {
            LocationPromptCard(isDenied: true) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    self.openURL(url)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        } else if !self.viewModel.hasLoadedNearby {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader("Near you", systemImage: "location.fill")
                NearbyPlacesPlaceholder()
            }
            .transition(.opacity)
        } else if !self.viewModel.nearby.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader("Near you", systemImage: "location.fill")
                NearbyPlacesRow(places: self.viewModel.nearby, transition: self.transition)
            }
            .transition(.opacity)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader("Recently viewed", systemImage: "clock.fill") {
                if !self.recentPages.isEmpty {
                    Button("Clear") {
                        self.recents.removeAll(in: self.sync.dataLanguage)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            Group {
                if self.recentPages.isEmpty {
                    RecentPagesEmptyCard()
                } else {
                    RecentPagesList(pages: Array(self.recentPages.prefix(5)), transition: self.transition) { page in
                        self.recents.remove(page)
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    // MARK: - Search

    private var searchResults: some View {
        List {
            if !self.viewModel.nearbyMatches.isEmpty {
                Section("Near you") {
                    ForEach(self.viewModel.nearbyMatches) { place in
                        let sourceID = "search-\(place.page.title)"
                        NavigationLink(value: PageRoute(title: place.page.title, sourceID: sourceID)) {
                            HStack {
                                Label(place.page.title, systemImage: "location.fill")
                                Spacer()
                                Text(place.distance.formattedDistance)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .matchedTransitionSource(id: sourceID, in: self.transition)
                    }
                }
            }

            Section {
                ForEach(self.viewModel.otherMatches) { page in
                    let sourceID = "search-\(page.title)"
                    NavigationLink(value: PageRoute(title: page.title, sourceID: sourceID)) {
                        Text(page.title)
                    }
                    .matchedTransitionSource(id: sourceID, in: self.transition)
                }
            } header: {
                if !self.viewModel.nearbyMatches.isEmpty {
                    Text("All places")
                }
            }
        }
        .overlay {
            if !self.viewModel.query.isEmpty && self.viewModel.nearbyMatches.isEmpty && self.viewModel.otherMatches.isEmpty {
                ContentUnavailableView.search(text: self.viewModel.query)
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(DatabaseSync())
}
