//
//  OfflineMapsView.swift
//  HitchWise
//
//  Download country maps to use without a connection. Opened from Settings and from the map.
//  The country around `suggestedCoordinate` (where the map is looking) is offered first.
//

import SwiftUI
import CoreLocation

struct OfflineMapsView: View {
    var suggestedCoordinate: CLLocationCoordinate2D?

    @State private var search = ""
    private var store: OfflineMapStore { .shared }

    var body: some View {
        List {
            switch self.store.catalogState {
            case .unavailable:
                ContentUnavailableView("Country maps are coming soon",
                                       systemImage: "map",
                                       description: Text("You'll be able to download maps of whole countries here and use them without a connection."))
            case .failed where self.store.installed.isEmpty:
                ContentUnavailableView {
                    Label("Couldn't load the list of maps", systemImage: "wifi.slash")
                } description: {
                    Text("Check your internet connection and try again.")
                } actions: {
                    Button("Try again") {
                        Task { await self.store.loadCatalog() }
                    }
                }
            default:
                self.content
            }
        }
        .navigationTitle("Offline maps")
        .searchable(text: self.$search, prompt: Text("Search countries"))
        .task {
            await self.store.loadCatalog()
        }
        .refreshable {
            await self.store.loadCatalog()
        }
    }

    @ViewBuilder
    private var content: some View {
        Section {
            Text("Download the countries you're travelling through. The map, place names, roads and petrol stations then work without a connection; spots and the guide always do.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        let installed = self.store.installedPacks.filter { self.matches($0.info) }
        if !installed.isEmpty {
            Section {
                ForEach(installed, id: \.info.id) { pack in
                    OfflineMapRow(pack: pack.info)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                self.store.delete(pack.info.id)
                            }
                        }
                }
            } header: {
                Text("On this iPhone")
            } footer: {
                Text("Using \(ByteCountFormatter.string(fromByteCount: self.store.installedBytes, countStyle: .file)). Swipe left to delete a map.")
            }
        }

        let suggested = self.suggested.filter { self.matches($0) }
        if !suggested.isEmpty {
            Section("Where you're looking") {
                ForEach(suggested) { pack in
                    OfflineMapRow(pack: pack)
                }
            }
        }

        if self.store.catalogState == .loading && self.store.catalog.isEmpty {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        } else {
            let available = self.store.catalog.filter { self.store.installed[$0.id] == nil && self.matches($0) }
            if !available.isEmpty {
                Section("All countries") {
                    ForEach(available) { pack in
                        OfflineMapRow(pack: pack)
                    }
                }
            }
        }

        Section {
            Link(destination: MapStyle.copyrightURL) {
                Text(MapStyle.attribution)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggested: [MapPackInfo] {
        guard let coordinate = self.suggestedCoordinate else {
            return []
        }
        return self.store.catalog
            .filter { self.store.installed[$0.id] == nil && $0.contains(latitude: coordinate.latitude, longitude: coordinate.longitude) }
            // Bounding boxes overlap near borders: the smallest (most likely) first.
            .sorted { $0.bytes < $1.bytes }
            .prefix(3)
            .map { $0 }
    }

    private func matches(_ pack: MapPackInfo) -> Bool {
        self.search.isEmpty || pack.displayName.localizedStandardContains(self.search) || pack.name.localizedStandardContains(self.search)
    }
}

private struct OfflineMapRow: View {
    let pack: MapPackInfo
    private var store: OfflineMapStore { .shared }

    var body: some View {
        HStack(spacing: 14) {
            Text(self.pack.flag)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.pack.displayName)
                    .foregroundStyle(.primary)
                Text(self.detail)
                    .font(.footnote)
                    .foregroundStyle(self.store.failedDownloads.contains(self.pack.id) ? Color.red : Color.secondary)
            }
            Spacer(minLength: 0)
            self.action
        }
        .accessibilityElement(children: .combine)
    }

    private var size: String {
        ByteCountFormatter.string(fromByteCount: self.pack.bytes, countStyle: .file)
    }

    private var detail: String {
        if self.store.failedDownloads.contains(self.pack.id) {
            return String(localized: "Download failed. Try again.")
        }
        if let progress = self.store.progress[self.pack.id] {
            return String(localized: "Downloading… \(progress.formatted(.percent.precision(.fractionLength(0))))")
        }
        if self.store.isUpdateAvailable(self.pack.id) {
            return String(localized: "Update available · \(self.size)")
        }
        if self.store.installed[self.pack.id] != nil {
            return String(localized: "Downloaded · \(self.size)")
        }
        return self.size
    }

    @ViewBuilder
    private var action: some View {
        if let progress = self.store.progress[self.pack.id] {
            Button {
                self.store.cancelDownload(self.pack.id)
            } label: {
                ZStack {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Stop download"))
        } else if self.store.installed[self.pack.id] == nil || self.store.isUpdateAvailable(self.pack.id) {
            Button {
                self.store.download(self.pack)
            } label: {
                Image(systemName: self.store.installed[self.pack.id] == nil ? "arrow.down.circle.fill" : "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(self.store.installed[self.pack.id] == nil ? Text("Download") : Text("Update"))
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityLabel(Text("Downloaded"))
        }
    }
}

#Preview {
    NavigationStack {
        OfflineMapsView()
    }
}
