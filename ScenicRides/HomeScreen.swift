import MapKit
import SwiftUI

struct HomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var location = LocationService()
    @State private var startingPlace = StartingPlace.austin
    @State private var duration: RideDuration = .sixty
    @State private var scenery: Set<Scenery> = [.water]
    @State private var options = RideOptions()
    @State private var isChoosingOptions = false
    @State private var camera: MapCameraPosition = .region(StartingPlace.austinMapRegion)
    @State private var isChoosingLocation = false

    /// The next flow receives real selections without coupling this screen to a vehicle provider.
    let onFindRide: (RideRequest) -> Void

    var body: some View {
        GeometryReader { geometry in
            Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
                if location.currentPlace != nil {
                    UserAnnotation()
                }
            }
            .mapStyle(.standard(
                elevation: .realistic,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            ))
            .mapControls { MapCompass() }
            .accessibilityLabel("Map of the starting area")
            .safeAreaInset(edge: .top, alignment: .leading, spacing: 0) {
                locationButton
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            // Insets keep Apple's attribution and map controls clear of the panel.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ridePanel(availableHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $isChoosingOptions) {
            RideOptionsSheet(options: options) { options = $0 }
        }
        .sheet(isPresented: $isChoosingLocation) {
            StartingPlacePicker(location: location, selection: startingPlace) { place in
                startingPlace = place
                let position: MapCameraPosition = place == .austin
                    ? .region(StartingPlace.austinMapRegion)
                    : .region(MKCoordinateRegion(
                        center: place.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
                    ))
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) {
                    camera = position
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func ridePanel(availableHeight: CGFloat) -> some View {
        Group {
            if dynamicTypeSize >= .xxLarge || availableHeight < 700 {
                ScrollView { rideControls }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: availableHeight * 0.76)
            } else {
                rideControls
            }
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var locationButton: some View {
        Button {
            isChoosingLocation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .accessibilityHidden(true)
                Text(startingPlace.name)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.headline)
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .foregroundStyle(.primary)
        .accessibilityLabel("Starting point, \(startingPlace.name)")
        .accessibilityHint("Choose a starting location")
        .accessibilityIdentifier("startingPoint")
    }

    private var rideControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Take the scenic way.")
                .font(.title.bold())
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                Text("Time for the whole trip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Time budget, including stops", selection: $duration) {
                    ForEach(RideDuration.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("rideLength")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("What would you like to see?")
                    Spacer()
                    Text("Pick a few").font(.caption)
                }
                .font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                    ForEach(Scenery.allCases) { choice in
                        RideChoiceButton(title: choice.name, symbol: choice.symbol, selected: scenery.contains(choice)) {
                            if scenery.contains(choice) { scenery.remove(choice) } else { scenery.insert(choice) }
                        }
                        .accessibilityHint("Add or remove this scenery")
                        .accessibilityIdentifier("scenery-\(choice.rawValue)")
                    }
                }
                if scenery.isEmpty {
                    Text("Choose at least one kind of scenery.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Button { isChoosingOptions = true } label: {
                HStack {
                    Text(options.summary)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("optionsSummary")
                    Spacer(minLength: 8)
                    Label("More options", systemImage: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 34)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .accessibilityIdentifier("rideOptions")

            Button {
                onFindRide(RideRequest(startingPlace: startingPlace, duration: duration, scenery: scenery, options: options))
            } label: {
                HStack(spacing: 10) {
                    Text("Find my ride")
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 42)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(.blue)
            .disabled(scenery.isEmpty)
            .accessibilityIdentifier("findRide")

            Text("Returns to your starting point")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HomeScreen { _ in }
        .preferredColorScheme(.dark)
}
