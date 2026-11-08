# Validation

## Environment and build

- Xcode 27.2 (27B48), iOS Simulator SDK 27.2.
- iPhone 17 Pro simulator, iOS 27.0 (24A5390f), running in the background.
- Deployment target and built app `MinimumOSVersion`: **26.0**.
- Swift 6 with complete strict-concurrency checking.
- Simulator build and test builds succeeded. No Swift compilation errors or warnings. Xcode emitted its routine App Intents metadata-extraction warning because this app has no App Intents dependency.
- The project's property-list syntax passed `plutil -lint`.

The installed simulator runtime is iOS 27.0. iOS 26 availability was checked by compilation with a 26.0 deployment target, but a separate iOS 26 runtime and a physical device were not tested.

## Five UI scenarios passed

1. Home defaults to 60 minutes, contains round-trip text and no one-way switch. Selecting 90 minutes passes the selected duration to the summary and preserves it after dismissal.
2. Starting-point picker opens, cancels without changing state, and accepts Austin.
3. Live MapKit search finds Zilker Botanical Garden and updates the starting-point selection.
4. App launch does not request location access. Explicitly selecting Use my location triggers the system permission prompt; denying it shows the fallback message and leaves manual selection usable.
5. At the largest accessibility text size, the controls scroll, the full primary button becomes visible, and tapping it opens the selected-preferences summary.

The main four-scenario run passed. Permission-denial coverage and the stronger large-text scrolling/tap assertion then passed in targeted runs. The final source includes all five tests. Raw test result bundles and local build logs are excluded from this repository.

## Visual checks

- Inspected actual simulator captures at standard and largest accessibility text sizes.
- Corrected the initial status-bar overlap and excessive panel spacing.
- Confirmed Apple Maps tiles and labels loaded over the network.
- Confirmed the Apple Maps attribution remains visible above the bottom panel.
- The bottom panel uses a standard system material; the location button and primary button use native `.glass` and `.glassProminent` styles.
- The final standard-size simulator capture is included at [docs/home-screen.png](docs/home-screen.png).

## Scope limits

This is the working home screen and its location/preference controls. The primary action presents the selected ride preferences through the `onFindRide` callback. Scenic-route discovery, actual route durations, vehicle integration, fares, and booking are not implemented.

Live device GPS acquisition was not tested; permission-denial behavior and live place search were tested. Apple map appearance and Liquid Glass rendering may vary with OS version and accessibility settings.
