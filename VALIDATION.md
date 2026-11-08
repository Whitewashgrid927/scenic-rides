# Validation

## Environment

- Xcode 27.2, iOS Simulator SDK 27.2.
- iPhone 17 Pro simulator, iOS 27.0, running in the background.
- Deployment target: **iOS 26.0**; Swift 6 with complete strict-concurrency checking.
- Debug app and both test targets built successfully. Release simulator build also passed.
- No Swift compiler errors or warnings. Xcode emits its routine App Intents metadata-extraction warning because the app has no App Intents dependency.
- Project property-list syntax and `git diff --check` pass.

The available simulator runtime is iOS 27.0. iOS 26 API availability is checked by compilation with a 26.0 deployment target; a separate iOS 26 runtime and a physical device have not been tested.

## Automated coverage

Six unit tests cover:

1. Each duration's loop starts at the selected coordinate and calculates the final return leg. Distance and driving time include all four legs, and later departure estimates incorporate earlier travel times. The actual ETA remains independent of the duration target. Map bounds include all waypoints.
2. A failed return leg leaves no partial route; retry can recover.
3. Starting at a highlight skips its zero-length network request and preserves the complete trip.
4. An unsupported starting point is rejected before any map-service calls.
5. A late response from an older request cannot replace the current route.
6. A cancelled response is discarded.

Ten UI tests cover:

- Home defaults, duration selection, preview handoff, and preserving preferences after returning.
- Starting-point selection and cancellation.
- Live search for a public Austin attraction.
- Explicit location permission and denial recovery, with no permission request on launch.
- Home action reachability at the largest accessibility text size.
- Preview time versus duration target, matching start/return in the stops sheet, and changing loops.
- Error state and retry with preferences preserved.
- Leaving the preview during loading.
- Preview action reachability and opening stops at the largest accessibility text size.
- Live MapKit directions for all three Austin loops, with route estimates and map framing controls available.

Results combine the main test run and targeted reruns for live routing and the largest-text layout. The live test waits for each completed route rather than requiring a transient loading state. All six unit tests and all ten UI scenarios passed across those runs.

The live search and directions checks require Apple's services. Other route UI scenarios use a debug-only fixture planner; the Release build excludes that planner and its environment flag. No simulated route is used in the published route screenshot.

## Visual verification

- Inspected simulator captures of all three live road-following routes, plus the largest-text preview.
- Confirmed route markers, complete map framing, visible Apple Maps attribution, and a legible dark summary panel.
- Bounded the numbered marker badges' text scaling so numbers stay inside their circles at accessibility sizes. The panel continues to scale and scroll.
- Navigation toolbar controls use the native system appearance. Primary and alternate actions use `.glassProminent` and `.glass`; the bottom content panel uses `.regularMaterial`.
- Included [home screenshot](docs/home-screen.png) and [live route screenshot](docs/route-preview.png), using the generic Austin starting point. Image metadata is stripped; pixel content is preserved.

## Scope and privacy

Routes are curated around public Austin attractions; MapKit chooses connecting roads and estimates driving time. Duration is a target, stops add time, and routes may retrace roads. Vehicle connectivity, booking, in-ride guidance, and automatic duration optimization are not included.

Live device GPS acquisition remains untested. Map tiles, directions, estimates, and Liquid Glass appearance can vary with connectivity, OS version, traffic, and accessibility settings.

Personal addresses, identity metadata, credentials, signing files, local build paths, test logs, and raw result bundles are excluded from the repository. Only the approved GitHub handle and noreply commit attribution are retained.
