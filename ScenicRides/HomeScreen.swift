import MapKit
import SwiftUI

struct HomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var location = LocationService()
    @State private var startingPlace = StartingPlace.austin
    @State private var duration: RideDuration = .sixty
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
            if dynamicTypeSize.isAccessibilitySize {
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
        VStack(alignment: .leading, spacing: 24) {
            Text("Let’s take\nthe scenic way.")
                .font(.largeTitle.bold())
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                Text("Ride length")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Ride length", selection: $duration) {
                    ForEach(RideDuration.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("rideLength")
            }

            Label("Returns to your starting point", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onFindRide(RideRequest(startingPlace: startingPlace, duration: duration))
            } label: {
                HStack(spacing: 10) {
                    Text("Find a scenic ride")
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
            .accessibilityIdentifier("findRide")
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HomeScreen { _ in }
        .preferredColorScheme(.dark)
}
