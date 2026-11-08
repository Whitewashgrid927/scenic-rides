import MapKit
import SwiftUI

struct StartingPlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    let location: LocationService
    let selection: StartingPlace
    let onSelect: (StartingPlace) -> Void

    @State private var query = ""
    @State private var results: [StartingPlace] = []
    @State private var isSearching = false
    @State private var searchMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        location.useCurrentLocation()
                    } label: {
                        HStack {
                            Label("Use my location", systemImage: "location.fill")
                            Spacer()
                            if location.isLocating { ProgressView() }
                        }
                    }
                    .disabled(location.isLocating)
                    .accessibilityIdentifier("useMyLocation")

                    Button { choose(.austin) } label: {
                        Label("Austin, TX", systemImage: "building.2")
                    }
                    .accessibilityIdentifier("chooseAustin")
                }

                if let message = location.message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Places") {
                        if isSearching {
                            HStack {
                                ProgressView()
                                Text("Searching places…").foregroundStyle(.secondary)
                            }
                        } else if let searchMessage {
                            Text(searchMessage).foregroundStyle(.secondary)
                        } else {
                            ForEach(results) { place in
                                Button { choose(place) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.name).foregroundStyle(.primary)
                                        Text(place.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Starting point")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search a place or address")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .task(id: query) { await searchPlaces() }
            .onChange(of: location.currentPlace) { _, place in
                if let place { choose(place) }
            }
        }
    }

    private func choose(_ place: StartingPlace) {
        onSelect(place)
        dismiss()
    }

    @MainActor
    private func searchPlaces() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []
        searchMessage = nil
        guard !text.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = MKCoordinateRegion(
                center: selection.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
            )
            request.resultTypes = [.address, .pointOfInterest]
            let response = try await MKLocalSearch(request: request).start()
            try Task.checkCancellation()
            results = response.mapItems.prefix(10).map { item in
                StartingPlace(
                    name: item.name ?? "Selected place",
                    detail: item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) ?? "",
                    coordinate: item.location.coordinate
                )
            }
            if results.isEmpty { searchMessage = "No places found. Try a different name or address." }
            isSearching = false
        } catch {
            // An old query must never replace the latest query's state.
            guard !Task.isCancelled else { return }
            searchMessage = "Places couldn’t load. Check your connection and try again."
            isSearching = false
        }
    }
}
