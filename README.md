# Scenic Rides

A native iPhone app for choosing and previewing a scenic Austin round trip. Built with SwiftUI, MapKit, Core Location, and SF Symbols. Minimum deployment target: **iOS 26.0**. No third-party packages or map API keys are required.

<p>
  <img src="docs/home-screen.png" alt="Dark Austin home screen with multiple scenery selections and native glass controls" width="250">
  <img src="docs/route-preview.png" alt="Live MapKit round trip with swipeable route cards" width="250">
  <img src="docs/ride-options.png" alt="Native options sheet with stop time and road preferences" width="250">
</p>

## Open and run

1. Open `ScenicRides.xcodeproj` in Xcode 26 or later.
2. Select the **ScenicRides** scheme and an iPhone simulator running iOS 26 or later.
3. Run. For a physical device, choose your development team in Signing & Capabilities and change the bundle identifier if needed.

The project includes a shared scheme and has no package-resolution step. Build products are intentionally excluded.

## Choose a ride

The home screen combines a live dark Apple map with three simple choices:

- **Time for the whole trip:** 30, 60, or 90 minutes, including driving, the return leg, and any planned stop.
- **What would you like to see?** Select one or more of Water, Hills, Greenery, and City. Selected choices have a checkmark and accessibility selection state. At least one choice is required.
- **More options:** Just drive or include a Coffee, A view, or A short walk stop. Set **Time at stop** to 10, 15, 20, or 30 minutes; the default is 15 minutes. This time is part of the budget.

The optional destinations are Mozart’s Coffee Roasters, Mount Bonnell, and Butler Park. A stop can also contribute scenery to the outing: for example, Mount Bonnell adds water, hills, and greenery. These are curated tags describing portions of the trip, not a guarantee of uninterrupted views.

All rides return to the selected starting coordinate. **Avoid highways** and **Avoid tolls** are passed to every MapKit driving request, including the return. Highways are allowed and tolls avoided by default. Apple applies these preferences where possible.

**Apply** saves the options draft for this session. Cancel or dismissing the sheet discards unapplied edits. The Apply action stays above the sheet's safe area while its content scrolls.

Starting-point search and **Use my location** remain available. Location permission is requested only after choosing that action; denial leaves manual search available. Austin is a generic city-level default, not a device-location claim. Starting points are supported within 40 km of central Austin.

Native Liquid Glass styles are used for choices, cards, and buttons. Content panels use native material, system typography, and dark appearance. Accessibility text sizes switch choice grids to one column, with scrolling map panels and options. Animations respect Reduce Motion.

## Routes that fit the budget

**Find my ride** checks a bounded shortlist of complete MapKit round trips and offers up to three matching routes. A recommendation must include every selected scenery category and satisfy:

```text
all driving legs + planned stop time <= selected time budget
```

The planner calculates the return leg and advances the departure time after each leg. When it reaches the optional stop, it adds the planned stop duration before calculating the next leg. A failed leg never leaves a partial trip presented as complete.

Cards show **total time**, a **driving + stop** breakdown, distance, matched scenery, and remaining budget. The first card is the closest fit to the available time among the checked routes that meet all preferences. Swipe a card, tap it, or use pagination to update the selected map and itinerary. **View route** repeats the time breakdown and distinguishes Drive through waypoints from the timed stop.

If no checked route fits, the app explains the shortest completed estimate and offers **Adjust my ride**. It never silently removes a stop or scenery preference, truncates the return leg, or substitutes the requested budget for the real estimate. If the stop consumes the whole budget, the app asks for a shorter stop or more time before making directions requests.

A route can leave substantial spare time. **Best fit** means the closest matching route in this shortlist, not a globally optimal route or a promise to fill every minute. Traffic, parking, access, and the time actually spent at a stop can change the outing; cards identify the totals as estimates. Opening hours and access are not checked automatically.

## Austin catalog and ranking

The catalog includes 12 public-road loops, from compact riverfront and downtown trips to longer routes through Westlake, the Mount Bonnell area, Bull Creek, and City Park Road. Combined loops include river, hill, park, and city scenery.

The app first filters by all requested scenery, including the selected stop's tags. Approximate city-center planning hints select at most four candidates near the requested driving allowance, plus a compact matching fallback when needed (at most five candidates total). The hints are never displayed as ETAs or used to approve budget fit. Live MapKit totals determine which candidates qualify and their final order. Travel times depend on the chosen start and current road conditions, so a matching route outside the shortlist may exist.

Map requests run sequentially. Completed candidates remain cached within a preview, including completed routes that exceed the budget; retries repeat only failed candidates. Partial failures leave successful matches available. Cancelled or stale responses cannot replace the current request. A new request clears the candidate cache.

MapKit chooses the connecting roads, which can retrace portions of the trip. This is a curated-catalog planner, not an exhaustive search of the road network.

## Data and scope

Preferences and routes stay in memory. Map display, place searches, and directions use Apple's MapKit services; there is no application backend or analytics integration. Screenshots use the generic Austin starting point and public destinations. Personal addresses, location histories, credentials, signing files, and local build/test artifacts stay out of this repository.

`HomeScreen(onFindRide:)` passes a typed `RideRequest` with the start, total budget, scenery set, planned departure, and options. `ScenicRidesApp` presents `RoutePreviewScreen`, which obtains complete routes through `MapKitRoutePlanner`.

Vehicle connectivity, booking, fares, in-ride guidance, and language-model integration are **not implemented**. Viewing a route does not start navigation or book a vehicle.

## Structure

- `HomeScreen.swift`: map and ride controls.
- `RidePreferences.swift`: request, scenery, time-budget, stop-duration, and road-preference types.
- `RideOptionsSheet.swift`: draft options, Apply/Cancel, and shared glass choice buttons.
- `StartingPlacePicker.swift` and `LocationService.swift`: native search and foreground location requests.
- `AustinRoutes.swift`: 12 public route definitions and optional stop destinations.
- `RoutePlanner.swift`: MapKit resolution/directions, cancellation, and budget filtering, ranking, and preview state.
- `RoutePreviewScreen.swift`: route carousel, synchronized map, loading/retry states, and itinerary.
- `ScenicRidesTests`: round-trip integrity, preferences, alternatives, and cancellation coverage.
- `ScenicRidesUITests`: home, options, swiping, accessibility text sizes, and live Apple service checks.

## Validation

Run **Product → Test** or:

```sh
xcodebuild -project ScenicRides.xcodeproj -scheme ScenicRides \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' test
```

If the developer directory points to Command Line Tools, select the installed Xcode in Settings → Locations or set `DEVELOPER_DIR` for the command. This project does not change the machine's selected Xcode.

Build and simulator results are recorded in [VALIDATION.md](VALIDATION.md). The live place-search test and `RoutePreviewTests/testLiveBudgetsAndMixedSceneryWithStops` require connectivity to Apple. Other preview UI tests use a debug-only injected planner for deterministic loading, success, and failure/retry states. Release builds exclude that planner. The published route screenshot comes from live MapKit directions. Test logs and raw result bundles remain local.

## References

- [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui) and [directions](https://developer.apple.com/documentation/mapkit/mkdirections)
- [MapKit highway preferences](https://developer.apple.com/documentation/mapkit/mkdirections/request/highwaypreference) and [toll preferences](https://developer.apple.com/documentation/mapkit/mkdirections/request/tollpreference)
- [Native view-aligned scrolling](https://developer.apple.com/documentation/swiftui/scrolltargetbehavior/viewaligned)
- [Liquid Glass materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [prominent glass buttons](https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle)
- [Location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
- [City of Austin park directory](https://www.austintexas.gov/parks/locations/park-directory), [Mozart’s FAQ](https://mozartscoffee.com/pages/frequently-asked-questions), and [Mount Bonnell guide](https://www.austintexas.org/austin-insider-blog/blog/post/mount-bonnell-for-beginners/)

MapKit resolves the public map locations at runtime. Place access and service estimates can change.
