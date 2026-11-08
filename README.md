# Scenic Rides

A native iPhone app for choosing and previewing a scenic Austin round trip. Built with SwiftUI, MapKit, Core Location, and SF Symbols. Minimum deployment target: **iOS 26.0**. No third-party packages or map API keys are required for this native MapKit implementation.

<img src="docs/home-screen.png" alt="Scenic Rides running in the iPhone simulator, with a dark Austin map, ride-length picker, and native Liquid Glass controls" width="360">

## Open and run

1. Open `ScenicRides.xcodeproj` in Xcode 26 or later.
2. Select the **ScenicRides** scheme and an iPhone simulator running iOS 26 or later.
3. Run. To use a physical device, choose your development team in Signing & Capabilities and change the bundle identifier if needed.

The project includes a shared scheme and has no package-resolution step. The source and project files are the deliverable; build products are intentionally excluded.

## Home screen

- Live Apple map, starting on Austin with dark appearance, muted map features, and business pins hidden.
- Native Liquid Glass location button and prominent primary action.
- Native segmented picker for 30, 60, or 90 minutes; 60 minutes is initially selected.
- All rides return to their starting point. There is no one-way toggle.
- A starting-point sheet with native place/address search and **Use my location**.
- Location permission is requested only after selecting **Use my location**. Denial leaves place search and the Austin selection available.
- The device-location dot appears only after a real location has been obtained. The Austin default is a city-level selection, not a claim about the device's location.
- System typography, VoiceOver labels, Reduce Motion handling, and a scrolling control panel when large text needs more room.

Apple renders the actual map and Liquid Glass.

## Austin route preview

<img src="docs/route-preview.png" alt="Live MapKit round trip through Red Bud Isle, Mount Bonnell, and Bull Creek, with estimated driving time and native glass controls" width="360">

**Find a scenic ride** opens a full-screen map with a road-following round trip, numbered highlights, estimated driving time and distance, and a compact bottom panel. **View stops** opens the ordered itinerary, including the starting point and return. **Try another** cycles through the three curated loops, and the map toolbar can fit the whole route again after panning.

| Initial duration target | Suggested loop | Highlights |
| --- | --- | --- |
| 30 minutes | Parks & skyline | Auditorium Shores, Zilker Metropolitan Park, Deep Eddy Pool |
| 60 minutes | Hills & river | Red Bud Isle, Mount Bonnell, Bull Creek District Park |
| 90 minutes | Around Lake Austin | Mount Bonnell, Emma Long Metropolitan Park, Red Bud Isle |

The selected duration is a **target**, not a promised route length. MapKit resolves the public places and calculates each driving leg, including the return to the selected starting point. The preview sums the actual distance and travel-time estimates; stops add extra time. Later legs use the preceding legs' estimated arrival times. Route alternatives can be shorter or longer than the target.

Starting points are supported within 40 km of central Austin. A place outside that area gets a clear message and a way back. Loading, retry, cancellation, and large-text layouts are supported. A failed leg never leaves a partial route presented as a complete round trip.

The named highlights anchor each route; MapKit chooses the roads between them. This is not a scenic-road optimizer, and some routes may retrace roads. The stops sheet identifies the walk to Mount Bonnell's overlook and Emma Long's day-pass requirement. Access and opening hours may change.

## Sample data and location

Austin is a city-level demo selection. Screenshots use that sample starting point, not a saved device location. Route anchors and search tests use public attractions.

The app keeps ride preferences and routes in memory. Map display, place searches, and directions use Apple's MapKit services; there is no application backend or analytics integration. Personal addresses, location histories, credentials, signing files, and local build/test artifacts should stay out of this repository.

## Scope of the primary action

`HomeScreen(onFindRide:)` passes a typed `RideRequest` containing the selected starting place and duration. `ScenicRidesApp` presents `RoutePreviewScreen`, which obtains a complete route through `MapKitRoutePlanner`.

Vehicle connectivity, booking, fares, in-ride guidance, and automatic duration optimization are **not implemented**. Viewing stops does not start navigation or book a vehicle.

## Structure

- `HomeScreen.swift`: map composition and home controls.
- `RidePreferences.swift`: duration, starting-place, and request value types.
- `StartingPlacePicker.swift`: native search, selection, and location action.
- `LocationService.swift`: foreground-only location request and permission/error state.
- `AustinRoutes.swift`: public route anchors, route value types, and duration preferences.
- `RoutePlanner.swift`: MapKit place resolution, driving directions, cancellation, and preview state.
- `RoutePreviewScreen.swift`: route map, summary panel, loading/retry states, and stops sheet.
- `ScenicRidesTests/RoutePlannerTests.swift`: return-leg integrity, totals, coincident stops, unsupported starts, retry, and stale/cancelled responses.
- `ScenicRidesUITests`: home-screen regressions, preview interactions, large text, and live Apple service checks.

## Validation

Run the unit and UI tests with **Product → Test** or:

```sh
xcodebuild -project ScenicRides.xcodeproj -scheme ScenicRides \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' test
```

If your selected developer directory points to Command Line Tools, select the installed Xcode in its Settings → Locations or set `DEVELOPER_DIR` for the command. This project does not change the machine's selected Xcode.

Build and simulator results for this delivery are recorded in [VALIDATION.md](VALIDATION.md).

The live place-search test and `RoutePreviewTests/testLiveAustinLoops` require connectivity to Apple's services. Other preview UI tests use a debug-only injected planner for deterministic success, failure/retry, and cancellation states. Release builds exclude that planner. The included route screenshot is captured from live MapKit directions, not a fixture. Test logs and raw result bundles remain local.

## Apple references

- [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [Map styles](https://developer.apple.com/documentation/mapkit/mapstyle)
- [MapKit directions](https://developer.apple.com/documentation/mapkit/mkdirections)
- [Map polylines](https://developer.apple.com/documentation/mapkit/mappolyline)
- [Liquid Glass materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Native prominent glass buttons](https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle)
- [Location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)

## Austin references

Public place names and addresses are based on the [City of Austin park directory](https://www.austintexas.gov/parks/locations/park-directory), [Deep Eddy Pool](https://www.austintexas.gov/parks/locations/deep-eddy-pool), and [Emma Long Metropolitan Park](https://www.austintexas.gov/parks/emma-long-metropolitan-park). The [Mount Bonnell guide](https://www.austintexas.org/austin-insider-blog/blog/post/mount-bonnell-for-beginners/) describes the walk to the overlook. MapKit resolves their current map locations at runtime.
