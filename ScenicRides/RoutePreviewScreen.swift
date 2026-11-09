import MapKit
import SwiftUI

struct RoutePreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: RoutePreviewModel
    @State private var selection: AustinLoop?
    @State private var camera: MapCameraPosition = .region(StartingPlace.austinMapRegion)
    @State private var loadID = UUID()
    @State private var detailRoute: ScenicRoute?
    let request: RideRequest

    init(request: RideRequest, planner: (any RoutePlanning)? = nil) {
        self.request = request
        _model = State(initialValue: RoutePreviewModel(planner: planner ?? RoutePlannerFactory.make()))
    }

    private var selectedRoute: ScenicRoute? { model.routes.first { $0.loop == selection } ?? model.routes.first }
    private var showingRoutes: Bool { !model.routes.isEmpty && (!model.isLoading || selection != nil) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                routeMap.safeAreaInset(edge: .bottom, spacing: 0) { routePanel(size: geometry.size) }
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
                        .disabled(!showingRoutes)
                        .accessibilityIdentifier("fitRoute")
                }
            }
            .task(id: loadID) { await model.loadChoices(request) }
            .onChange(of: model.isLoading) { _, loading in
                if !loading {
                    if !model.routes.contains(where: { $0.loop == selection }) { selection = model.routes.first?.loop }
                    fitRoute()
                }
            }
            .onChange(of: selection) { _, _ in fitRoute() }
            .sheet(item: $detailRoute) { route in
                RouteStopsSheet(route: route, budget: request.duration.rawValue).preferredColorScheme(.dark)
            }
        }
    }

    private var routeMap: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
            if showingRoutes, let route = selectedRoute {
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
        .accessibilityValue(showingRoutes ? selectedRoute?.loop.name ?? "" : "Finding routes")
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
                .fill(.regularMaterial).ignoresSafeArea(edges: .bottom)
        }
    }

    private func panelContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(showingRoutes ? "A little time, well spent." : model.isLoading ? "Finding your kind of ride." : "Your next scenic ride.")
                    .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("\(request.duration.rawValue) min budget · \(request.options.summary)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("routeTarget")
            }
            .padding(.horizontal, 24)

            if showingRoutes {
                routeCards(width: width)
                HStack(spacing: 0) {
                    ForEach(Array(model.routes.enumerated()), id: \.element.loop) { index, route in
                        Button { choose(route.loop) } label: {
                            Circle().fill(selectedRoute?.loop == route.loop ? .blue : Color.secondary.opacity(0.5))
                                .frame(width: 7, height: 7).frame(width: 44, height: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Route \(index + 1) of \(model.routes.count), \(route.loop.name)")
                        .accessibilityAddTraits(selectedRoute?.loop == route.loop ? .isSelected : [])
                        .accessibilityIdentifier("routePage-\(index)")
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 12) {
                    if model.hasFailures {
                        Button(model.isLoading ? "Checking alternatives…" : "Some routes couldn’t load. Retry") { loadID = UUID() }
                            .font(.caption).disabled(model.isLoading)
                            .accessibilityIdentifier("retryRoute")
                    }
                    Label("Returns to \(request.startingPlace.name)", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("routeReturn")
                    Button { detailRoute = selectedRoute } label: {
                        Label("View route", systemImage: "arrow.right")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                    .accessibilityIdentifier("viewRouteStops")
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 24)
            } else if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking scenery, stops and the way back…").font(.subheadline)
                    Text("\(model.checkedCount) of \(model.candidateCount) routes checked")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(24)
                .accessibilityIdentifier("routeLoading")
            } else {
                noRoutes.padding(.horizontal, 24)
            }
        }
        .padding(.top, 24).padding(.bottom, 24)
    }

    private func routeCards(width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(Array(model.routes.enumerated()), id: \.element.loop) { index, route in
                    Button { choose(route.loop) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Image(systemName: route.loop.symbol).font(.title3).foregroundStyle(.blue)
                                Spacer()
                                Text(index == 0 ? "Best fit" : "Another way").font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text(route.loop.name).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                            Text("About \(route.minutes) min total")
                                .font(.headline)
                                .accessibilityIdentifier("routeTotal-\(route.loop.rawValue)")
                            Text("\(route.breakdown) · \(route.distanceLabel)")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(request.sceneryLabel)
                                .font(.caption.weight(.medium)).foregroundStyle(.blue)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(request.duration.rawValue - route.minutes) min to spare · traffic may change")
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 166, alignment: .leading)
                        .padding(18).contentShape(.rect)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 24)).tint(.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(selectedRoute?.loop == route.loop ? Color.blue : .clear, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .frame(width: max(220, width - (dynamicTypeSize.isAccessibilitySize ? 48 : 88)))
                    .id(route.loop)
                    .accessibilityAddTraits(selectedRoute?.loop == route.loop ? .isSelected : [])
                    .accessibilityIdentifier("routeCard-\(route.loop.rawValue)")
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

    private var noRoutes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(emptyTitle).font(.headline).accessibilityIdentifier("routeError")
            Text(emptyMessage).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("routeEmptyMessage")
            Button("Adjust my ride") { dismiss() }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
                .accessibilityIdentifier("adjustRide")
            if model.failure == .unavailable || model.hasFailures {
                Button("Try again") { loadID = UUID() }
                    .buttonStyle(.glass).buttonBorderShape(.capsule)
                    .accessibilityIdentifier("retryRoute")
            }
        }
    }

    private var emptyTitle: String {
        switch model.failure {
        case .outsideAustin: "Let’s start in Austin"
        case .invalidPreferences: "Choose some scenery"
        case .stopExceedsBudget: "Leave some time for the drive"
        case .unavailable: "Routes couldn’t load"
        case nil: "Let’s give this ride more time"
        }
    }

    private var emptyMessage: String {
        switch model.failure {
        case .outsideAustin: "Choose a starting point in the Austin area."
        case .invalidPreferences: "Select at least one kind of scenery to find a ride."
        case .stopExceedsBudget: "Your \(request.options.stopMinutes)-minute stop uses the whole budget. Shorten the stop or allow more time."
        case .unavailable: "Check your connection and try again. Your choices are still here."
        case nil:
            if let minutes = model.shortestMinutes {
                "None of the checked routes fits your \(request.duration.rawValue)-minute budget and scenery choices. The shortest checked takes about \(minutes) minutes including stops. Try more time, fewer scenery choices or a shorter stop.\(model.hasFailures ? " Some alternatives couldn’t load." : "")"
            } else {
                "Try another scenery combination or starting point. Your choices are still here."
            }
        }
    }

    private func choose(_ loop: AustinLoop) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { selection = loop }
    }

    private func fitRoute() {
        guard let route = selectedRoute, showingRoutes else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { camera = .rect(route.mapRect) }
    }
}

private struct RouteStopsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let route: ScenicRoute
    let budget: Int

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Whole trip", value: "About \(route.minutes) min")
                    LabeledContent("Driving, including return", value: "\(route.drivingMinutes) min")
                    LabeledContent("Time at stop", value: "\(route.stopMinutes) min")
                    LabeledContent("Your budget", value: "\(budget) min")
                }
                .accessibilityIdentifier("routeTimeBreakdown")
                Section {
                    ForEach(Array(route.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: index == 0 || index == route.waypoints.count - 1
                                  ? "arrow.trianglehead.2.clockwise.rotate.90" : "\(index).circle.fill")
                                .foregroundStyle(.blue).frame(width: 24).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(index == 0 ? "Start" : index == route.waypoints.count - 1 ? "Return" : waypoint.isStop ? "\(route.options.stopMinutes) min stop" : "Drive through")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(waypoint.name).font(.headline)
                                if !waypoint.detail.isEmpty { Text(waypoint.detail).font(.subheadline).foregroundStyle(.secondary) }
                                if let note = waypoint.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(waypoint.id == "return" ? "routeStop-return" : waypoint.isStop ? "routeStop-optional" : "routeStop-\(index)")
                    }
                } header: {
                    Text(route.loop.name)
                } footer: {
                    Text("Driving estimates may change with traffic.\(route.stopMinutes > 0 ? " Your planned stop time is included; check opening hours and access." : " Waypoints shape the drive; no stop is scheduled.")")
                }
            }
            .navigationTitle("Your route").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

enum RoutePlannerFactory {
    @MainActor static func make() -> any RoutePlanning {
        #if DEBUG
        if let scenario = ProcessInfo.processInfo.environment["SCENIC_ROUTE_TEST_SCENARIO"] { return PreviewTestRoutePlanner(scenario: scenario) }
        #endif
        return MapKitRoutePlanner()
    }
}
