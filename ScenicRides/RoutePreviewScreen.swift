import MapKit
import SwiftUI

struct RoutePreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: RoutePreviewModel
    @State private var loops: [AustinLoop]
    @State private var selection: AustinLoop?
    @State private var camera: MapCameraPosition = .region(StartingPlace.austinMapRegion)
    @State private var loadID = UUID()
    @State private var detailRoute: ScenicRoute?
    let request: RideRequest

    init(request: RideRequest, planner: (any RoutePlanning)? = nil) {
        self.request = request
        let choices = AustinLoop.suggestions(style: request.style, duration: request.duration)
        _loops = State(initialValue: choices)
        _selection = State(initialValue: choices.first)
        _model = State(initialValue: RoutePreviewModel(planner: planner ?? RoutePlannerFactory.make()))
    }

    private var selectedLoop: AustinLoop { selection ?? loops[0] }
    private var selectedRoute: ScenicRoute? { model.route(for: selectedLoop) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                routeMap
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        routePanel(size: geometry.size)
                    }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Choose your loop")
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
                        .disabled(selectedRoute == nil)
                        .accessibilityIdentifier("fitRoute")
                }
            }
            .task(id: loadID) {
                await model.loadChoices(request, loops: loops, prioritizing: selectedLoop)
            }
            .onChange(of: selectedRoute?.id) { _, _ in fitRoute() }
            .sheet(item: $detailRoute) { route in
                RouteStopsSheet(route: route).preferredColorScheme(.dark)
            }
        }
    }

    private var routeMap: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
            if let route = selectedRoute {
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
                            .accessibilityLabel("\(point.isStop ? "Stop" : "Drive through") \(index + 1), \(point.name)")
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { MapCompass() }
        .accessibilityLabel("Austin round trip map")
        .accessibilityValue(selectedRoute?.loop.name ?? "Loading selected route")
        .accessibilityIdentifier("routeMap")
    }

    private func routePanel(size: CGSize) -> some View {
        Group {
            if dynamicTypeSize >= .xxLarge || size.height < 700 {
                ScrollView { panelContent(width: size.width) }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: size.height * 0.72)
                    .accessibilityIdentifier("routePanelScroll")
            } else {
                panelContent(width: size.width)
            }
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func panelContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A few ways to unwind.")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("\(request.duration.rawValue) min target · \(request.options.summary)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("routeTarget")
            }
            .padding(.horizontal, 24)

            routeCards(width: width)

            HStack(spacing: 0) {
                ForEach(Array(loops.enumerated()), id: \.element) { index, loop in
                    Button { choose(loop) } label: {
                        Circle().fill(selectedLoop == loop ? .blue : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                            .frame(width: 36, height: 30)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Route \(index + 1) of \(loops.count), \(loop.name)")
                    .accessibilityAddTraits(selectedLoop == loop ? .isSelected : [])
                    .accessibilityIdentifier("routePage-\(index)")
                }
            }
            .frame(maxWidth: .infinity)

            Group {
                switch model.state(for: selectedLoop) {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finding the scenic way…").font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("routeLoading")
                case .ready:
                    Label("Returns to \(request.startingPlace.name)", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("routeReturn")
                    Button { detailRoute = selectedRoute } label: {
                        Label("View route", systemImage: "arrow.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("viewRouteStops")
                case let .failed(error):
                    failureDetails(error)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    private func routeCards(width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(loops) { loop in
                    Button { choose(loop) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: loop.style.symbol)
                                .font(.title2).foregroundStyle(.blue)
                            Text(loop.name)
                                .font(.title3.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            cardEstimate(loop)
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(loop.style.name)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.quaternary, in: .capsule)
                        }
                        .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
                        .padding(18)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.roundedRectangle(radius: 24))
                    .tint(.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(selectedLoop == loop ? Color.blue : .clear, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .frame(width: max(220, width - (dynamicTypeSize.isAccessibilitySize ? 48 : 88)))
                    .id(loop)
                    .accessibilityAddTraits(selectedLoop == loop ? .isSelected : [])
                    .accessibilityIdentifier("routeCard-\(loop.rawValue)")
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $selection, anchor: .leading)
        .accessibilityIdentifier("routeCards")
    }

    @ViewBuilder
    private func cardEstimate(_ loop: AustinLoop) -> some View {
        switch model.state(for: loop) {
        case let .ready(route):
            Text("About \(route.minutes) min · \(route.distanceLabel)")
        case .loading:
            Text("Calculating drive…")
        case .failed:
            Text("Route unavailable")
        }
    }

    private func failureDetails(_ error: RoutePlanningError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(error == .outsideAustin ? "Let’s start in Austin" : "This route couldn’t load")
                .font(.headline)
                .accessibilityIdentifier("routeError")
            Text(error == .outsideAustin
                 ? "Choose a starting point in the Austin area."
                 : "Try again or swipe to another route. Your preferences are still here.")
                .font(.subheadline).foregroundStyle(.secondary)
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

    private func choose(_ loop: AustinLoop) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { selection = loop }
    }

    private func fitRoute() {
        guard let route = selectedRoute else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { camera = .rect(route.mapRect) }
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
                                Text(index == 0 ? "Start" : index == route.waypoints.count - 1 ? "Return" : waypoint.isStop ? "\(route.options.stopKind.name) stop" : "Drive through")
                                    .font(.caption).foregroundStyle(.secondary)
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
                    Text(route.options.pace == .stop
                         ? "About \(route.minutes) minutes of driving. Time at your stop is extra; check opening hours and access."
                         : "About \(route.minutes) minutes of driving. Waypoints shape the drive; no stop is scheduled.")
                }
            }
            .navigationTitle("Your route")
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
