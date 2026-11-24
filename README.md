# Scenic Rides

A native iPhone app for choosing and previewing a scenic Austin round trip. Built with SwiftUI, MapKit, Core Location, Apple's Foundation Models framework, and SF Symbols. Minimum deployment target: **iOS 26.0**. No third-party packages, map API keys, or application backend.

<p>
  <img src="docs/home-screen.png" alt="Dark Austin home screen with multiple scenery selections and native glass controls" width="250">
  <img src="docs/route-preview.png" alt="Live MapKit round trip with swipeable cards and More routes" width="250">
  <img src="docs/ride-options.png" alt="Native options sheet with stop time and road preferences" width="250">
</p>

## Open and run

1. Open `ScenicRides.xcodeproj` in Xcode 26 or later.
2. Select the **ScenicRides** scheme and an iPhone simulator running iOS 26 or later.
3. Run. For a physical device, choose your development team in Signing & Capabilities and change the bundle identifier if needed.

AI stop ranking requires an Apple Intelligence-capable device with Apple Intelligence enabled and the on-device model ready. Other devices use the nearby-stop fallback and identify it in the interface. The shared scheme needs no package-resolution step. Build products are excluded.

## Choose a ride

The home screen combines a live dark Apple map with three choices:

- **Time for the whole trip:** 30, 60, or 90 minutes, including driving, the return leg, and any planned stop.
- **What would you like to see?** Select one or more of Water, Hills, Greenery, and City. At least one choice is required.
- **More options:** Just drive or include a Coffee, A view, or A short walk stop. Set **Time at stop** to 10, 15, 20, or 30 minutes; the default is 15 minutes.

The app chooses the stop. There are 15 public destinations across Austin, including six coffee shops, four view stops, and seven walking stops; some parks support more than one kind. The selected place appears on its route card and itinerary. Access notes help distinguish a quick coffee break from a park or a viewpoint with stairs. Opening hours, parking, and current access are not checked automatically.

All rides return to the selected starting coordinate. **Avoid highways** and **Avoid tolls** are passed to every MapKit driving request. Highways are allowed and tolls avoided by default; Apple applies these preferences where possible. **Apply** saves options for the current session; Cancel or dismissal discards unapplied edits.

Starting-point search and **Use my location** remain available. Location permission is requested only after choosing that action; denial leaves manual search available. Austin is a generic city-level default. Starting points are supported within 40 km of central Austin.

Native Liquid Glass styles are used for controls and cards, with native materials, system typography, and dark appearance. Accessibility text sizes use scrolling panels and single-column choice grids. Animations respect Reduce Motion.

## Routes that fit the budget

**Find my ride** checks up to five candidates from the 24-route Austin catalog and shows up to three matches. A recommendation must cover every selected scenery category and satisfy:

```text
all driving legs + planned stop time <= selected time budget
```

The planner calculates the complete return leg. The planned stop advances the departure estimate for every subsequent leg. Failed legs never produce partial recommendations, and over-budget results are never offered as fitting routes.

Cards show the total estimate, driving/stop breakdown, distance, neighborhood, selected stop, and remaining budget. Swipe, tap a card, or use the previous/next controls to update the map and itinerary. **View route** distinguishes drive-through waypoints from the timed stop.

**More routes** appends up to three additional matches while preserving the current selection and existing cards. It reuses completed results, then checks at most five new candidates per batch when needed. The button becomes **All routes checked** when the matching catalog is exhausted. Failed candidates have a separate retry action; retries preserve successful choices. A no-fit result can still search the remaining catalog or return to **Adjust my ride**.

The first published card is the closest time fit among completed candidates. Later cards also favor different scenic waypoints. Approximate planning hints and distance from the chosen start determine which candidates to check first; they are never displayed as travel estimates. A compact option is included in the first batch when available.

These are curated route templates, not an exhaustive search of Austin's roads. MapKit chooses the connecting roads, which can retrace sections. Scenery tags describe portions of the outing, including its stop, rather than uninterrupted views. Traffic, parking, access, and actual stop time can change the total. A route may leave spare time.

## On-device stop selection

`OnDeviceStopRanker` uses **`SystemLanguageModel.default`** and **`LanguageModelSession`** from Apple's native **Foundation Models** framework. Guided generation returns typed stop IDs. No cloud model, API key, or external AI provider is involved.

1. The app finds public catalog stops of the chosen kind within 3 km of a scenic waypoint. Combined route and stop scenery must cover all selected categories. A geographic detour filter limits the shortlist to at most four candidates.
2. The on-device model ranks these candidates using scenery, the planned stop duration, access notes, and approximate added distance.
3. The app accepts only a complete, unique ordering of the supplied IDs. Unknown, missing, or duplicated IDs cannot become destinations.
4. MapKit resolves the selected place and calculates the full drive. The same exact time-budget check applies to AI-selected stops.

The stop is inserted into the route at the gap with the smallest geographic detour, rather than always after the scenic drive. This geographic estimate is a shortlist heuristic, not a road-distance claim. Place resolution tries at most two ranked candidates; the app does not substitute a distant stop or a different stop kind.

Model unavailability, generation errors, invalid output, and an eight-second inference timeout use a deterministic nearby match. Cards distinguish **Picked with on-device AI** from **Nearby match · AI unavailable**, and the itinerary explains the reason. Cancellation propagates instead of producing a fallback recommendation. Successful AI rankings are reused within an unchanged request; a new request gets a fresh ranking.

See the [live AI-selected stop preview](docs/ai-stop-preview.png). The model ranks stops; route ordering and time eligibility remain app logic backed by MapKit. This version does not generate new route templates or discover arbitrary destinations with the model. The structured choices stay the starting experience.

## Data and scope

Preferences, place caches, rankings, and routes stay in memory. Model prompts contain typed preferences and public catalog facts, without the starting address, exact starting coordinates, location history, or device identifiers. Prompts and responses are not logged. Map display, place searches, and directions still use Apple's network services, including the locations needed for routing.

The repository contains public destinations and generic Austin screenshots. Personal addresses, identity metadata, credentials, signing files, and local build/test artifacts are excluded. Vehicle connectivity, booking, fares, and in-ride guidance are not implemented. Viewing a route does not start navigation or book a vehicle.

## Structure and catalog updates

- `AustinCatalog.json`: 24 route templates, 49 public road anchors, and 15 stops with source links. See [the catalog guide](docs/AUSTIN-CATALOG.md) to add or review entries.
- `AustinCatalog.swift` and `AustinRoutes.swift`: catalog validation, geographic candidates, request fit, and route data.
- `OnDeviceStopRanker.swift`: Apple's local model, guided output validation, availability, and fallback behavior.
- `RoutePlanner.swift`: MapKit resolution/directions, cancellation, time-budget checks, batches, caching, and ranking.
- `HomeScreen.swift`, `RidePreferences.swift`, and `RideOptionsSheet.swift`: typed ride choices and native controls.
- `StartingPlacePicker.swift` and `LocationService.swift`: public-place search and foreground location requests.
- `RoutePreviewScreen.swift`: synchronized map, swipeable cards, More routes, retry states, and itinerary.
- `ScenicRidesTests` and `ScenicRidesUITests`: planner, AI boundary, pagination, UI, and live Apple-service checks.

## Validation

Run **Product → Test** or:

```sh
xcodebuild -project ScenicRides.xcodeproj -scheme ScenicRides \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' test
```

If the developer directory points to Command Line Tools, select the installed Xcode in Settings → Locations or set `DEVELOPER_DIR` for the command. The project does not change the machine's selected Xcode.

See [VALIDATION.md](VALIDATION.md) for actual build, simulator, and on-device model results. Live search and the live budget test require Apple's services. Other preview UI tests use a debug-only fixture planner, including a fixture for the AI attribution label. Release excludes this planner. Published route screenshots use live MapKit directions; raw logs and result bundles remain local.

## References

- [Apple's Foundation Models travel-planner demo](https://developer.apple.com/videos/play/wwdc2025/259/) and [guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui) and [directions](https://developer.apple.com/documentation/mapkit/mkdirections)
- [MapKit highway preferences](https://developer.apple.com/documentation/mapkit/mkdirections/request/highwaypreference) and [toll preferences](https://developer.apple.com/documentation/mapkit/mkdirections/request/tollpreference)
- [Liquid Glass materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [prominent glass buttons](https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle)
- [Location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
