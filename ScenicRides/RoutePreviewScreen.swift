import MapKit
import SwiftUI

struct RoutePreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: RoutePreviewModel
    @State private var loop: AustinLoop
    @State private var camera: MapCameraPosition = .region(StartingPlace.austinMapRegion)
    @State private var loadID = UUID()
    @State private var showingStops = false
    let request: RideRequest

    init(request: RideRequest, planner: (any RoutePlanning)? = nil) {
        self.request = request
        _loop = State(initialValue: AustinLoop.suggested(for: request.duration))
        _model = State(initialValue: RoutePreviewModel(planner: planner ?? RoutePlannerFactory.make()))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                routeMap
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        routePanel(availableHeight: geometry.size.height)
                    }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Your round trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", systemImage: "chevron.left") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("closeRoutePreview")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Show whole route", systemImage: "arrow.up.left.and.arrow.down.right") { fitRoute() }
                        .labelStyle(.iconOnly)
                        .disabled(model.route == nil)
                        .accessibilityIdentifier("fitRoute")
                }
            }
            .task(id: loadID) {
                await model.load(request, loop: loop)
                if !Task.isCancelled { fitRoute() }
            }
            .sheet(isPresented: $showingStops) {
                if let route = model.route {
                    RouteStopsSheet(route: route)
                        .preferredColorScheme(.dark)
                }
            }
        }
    }

    private var routeMap: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
            if let route = model.route {
                ForEach(route.legs) { leg in
                    MapPolyline(leg.polyline)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                Marker("Start & return", systemImage: "arrow.trianglehead.2.clockwise.rotate.90", coordinate: request.startingPlace.coordinate)
                    .tint(.white)
                ForEach(Array(route.highlights.enumerated()), id: \.element.id) { index, point in
                    Annotation(point.name, coordinate: point.coordinate) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.blue, in: .circle)
                            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                            .accessibilityLabel("Stop \(index + 1), \(point.name)")
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { MapCompass() }
        .accessibilityLabel("Austin round trip map")
        .accessibilityIdentifier("routeMap")
    }

    private func routePanel(availableHeight: CGFloat) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { panelContent }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: availableHeight * 0.72)
            } else {
                panelContent
            }
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch model.state {
            case .loading:
                HStack(spacing: 14) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Finding the scenic way…").font(.headline)
                        Text("Building your Austin round trip.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 16)
                .accessibilityIdentifier("routeLoading")
            case let .ready(route):
                routeDetails(route)
            case let .failed(error):
                failureDetails(error)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routeDetails(_ route: ScenicRoute) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text(route.loop.name)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("routeName")
                Text("About \(route.minutes) min · \(route.distanceLabel)")
                    .font(.title3.weight(.medium))
                    .accessibilityIdentifier("routeEstimate")
                Text("\(request.duration.rawValue) min target · Driving time, before stops")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("routeTarget")
            }

            Text(route.highlights.map(\.name).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Returns to \(request.startingPlace.name)", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("routeReturn")

            VStack(spacing: 12) {
                Button { showingStops = true } label: {
                    Label("View stops", systemImage: "list.number")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.blue)
                .accessibilityIdentifier("viewRouteStops")

                Button("Try another", systemImage: "arrow.clockwise") {
                    loop = loop.next
                    loadID = UUID()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .accessibilityIdentifier("anotherRoute")
            }
        }
    }

    private func failureDetails(_ error: RoutePlanningError) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(error == .outsideAustin ? "Let’s start in Austin" : "The route couldn’t load")
                .font(.title2.bold())
                .accessibilityIdentifier("routeError")
            Text(error == .outsideAustin
                 ? "Choose a starting point in the Austin area to preview a scenic round trip."
                 : "Check your connection and try again. Your starting point and ride length are still here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(error == .outsideAustin ? "Back to starting point" : "Try again") {
                if error == .outsideAustin { dismiss() } else { loadID = UUID() }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityIdentifier("retryRoute")
        }
    }

    private func fitRoute() {
        guard let route = model.route else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) {
            camera = .rect(route.mapRect)
        }
    }
}

private struct RouteStopsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let route: ScenicRoute

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(route.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: index == 0 || index == route.waypoints.count - 1
                                  ? "arrow.trianglehead.2.clockwise.rotate.90" : "\(index).circle.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                if index == 0 || index == route.waypoints.count - 1 {
                                    Text(index == 0 ? "Start" : "Return")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(waypoint.name).font(.headline)
                                if !waypoint.detail.isEmpty {
                                    Text(waypoint.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                if let note = waypoint.note {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("routeStop-\(index)")
                    }
                } header: {
                    Text(route.loop.name)
                } footer: {
                    Text("About \(route.minutes) minutes of driving. Time at stops is extra; access and opening hours may vary.")
                }
            }
            .navigationTitle("Route stops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

enum RoutePlannerFactory {
    @MainActor static func make() -> any RoutePlanning {
        #if DEBUG
        if let scenario = ProcessInfo.processInfo.environment["SCENIC_ROUTE_TEST_SCENARIO"] {
            return PreviewTestRoutePlanner(scenario: scenario)
        }
        #endif
        return MapKitRoutePlanner()
    }
}
