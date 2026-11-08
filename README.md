# Scenic Rides

A native iPhone home screen for choosing a scenic round trip. Built with SwiftUI, MapKit, Core Location, and SF Symbols. Minimum deployment target: **iOS 26.0**. No third-party packages or map API keys are required for this native MapKit implementation.

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

Apple renders the actual map and Liquid Glass. The mockup is a visual reference; its illustrated geography and highlights are not embedded in the app.

## Sample data and location

Austin is a city-level demo selection. The screenshot shows that sample map, not a saved device location. The test search uses a public attraction, Zilker Botanical Garden.

The app keeps ride preferences in memory. Maps and place searches use Apple's MapKit services; there is no application backend or analytics integration. Personal addresses, location histories, credentials, signing files, and local build/test artifacts should stay out of this repository.

## Scope of the primary action

`HomeScreen(onFindRide:)` passes a typed `RideRequest` containing the selected starting place and duration. In this home-screen build, `ScenicRidesApp` presents those preferences in a small native summary sheet so the action is testable and the selected state is visible.

Route discovery, duration-matched itineraries, vehicle connectivity, pricing, and booking are **not implemented**. The summary makes no route or booking claim. Replace this presentation with the route-preview flow when that feature is built. No requests are sent to a vehicle provider.

## Structure

- `HomeScreen.swift`: map composition and home controls.
- `RidePreferences.swift`: duration, starting-place, and request value types.
- `StartingPlacePicker.swift`: native search, selection, and location action.
- `LocationService.swift`: foreground-only location request and permission/error state.
- `RideRequestSummary.swift`: the current home-screen action handoff.
- `ScenicRidesUITests/HomeScreenTests.swift`: UI verification of selection, handoff, live place search, location-sheet dismissal, permission denial, and large-text reachability.

## Validation

Run the UI tests with **Product → Test** or:

```sh
xcodebuild -project ScenicRides.xcodeproj -scheme ScenicRides \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' test
```

If your selected developer directory points to Command Line Tools, select the installed Xcode in its Settings → Locations or set `DEVELOPER_DIR` for the command. This project does not change the machine's selected Xcode.

Build and simulator results for this delivery are recorded in [VALIDATION.md](VALIDATION.md).

The live place-search test requires connectivity to Apple's services. The remaining tests exercise local UI and location-permission behavior. Search uses a short debounce and discards cancelled queries so older results cannot replace the latest query.

## Apple references

- [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [Map styles](https://developer.apple.com/documentation/mapkit/mapstyle)
- [Liquid Glass materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Native prominent glass buttons](https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle)
- [Location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
