# Validation

## Environment

- Xcode 27.2, iOS Simulator SDK 27.2.
- iPhone 17 Pro simulator, iOS 27.0, running in the background.
- Deployment target: **iOS 26.0**; Swift 6 with complete strict-concurrency checking.
- Debug app and both test targets built successfully. Release simulator build also passed.
- No Swift compiler errors or warnings. Xcode emits its routine App Intents metadata-extraction warning because the app has no App Intents dependency.
- Project property-list syntax and `git diff --check` pass.

The available runtime is iOS 27.0. iOS 26 API availability is checked by compilation with a 26.0 deployment target; a separate iOS 26 runtime and a physical device have not been tested.

## Automated coverage

**10 unit tests and 12 UI tests pass across the main run and focused reruns.** The route/options suite was rerun after fixing the switch tap target and keeping Apply visible at accessibility text sizes. Focused options and live-routing checks were repeated after the final layout and address-query refinements.

Unit coverage includes:

- All six loops return to the selected coordinate, sum every leg's distance and time, and advance later departure estimates.
- Every loop and optional stop combination contains exactly one stop and passes road preferences to all five driving legs, including the return.
- Actual `MKDirections.Request` objects receive the correct highway and toll preferences for both toggle states.
- Each scenic style offers distinct alternatives; Surprise me includes all three styles.
- Retrying a failed alternative preserves completed routes; a new request clears cached choices.
- Failed return legs never publish partial round trips, coincident waypoints skip zero-length requests, and unsupported starts fail before network work.
- Cancelled and stale completions are discarded.

UI coverage includes:

- Home defaults, duration selection, handoff, and preserving preferences after returning.
- Starting-point selection/cancellation, live public-place search, and location permission denial recovery.
- Primary action reachability at the largest accessibility text size on home and route preview; Apply remains reachable in the options sheet.
- Swiping selects another card and its matching itinerary; pagination can select the previous route again.
- Ride style selection, optional coffee stops, highway toggle persistence, Apply, and Cancel.
- Per-card errors, successful alternatives, retry, and leaving during loading.
- Three alternatives for Surprise me.
- Live MapKit directions for all six catalog loops, plus a coffee-stop route with Avoid highways enabled.

The live search and directions checks require Apple's services. Other preview UI tests use a debug-only fixture planner. The Release binary excludes the fixture planner and its environment flag. No simulated route is used in the published route screenshot. The view and walk stop combinations have unit coverage; this delivery's live stop smoke test covers coffee.

## Visual verification

- Inspected simulator captures of the home screen, native options sheet, all six live routes, and the largest-text options/preview layouts.
- Confirmed native glass cards, visible selected state, card peeking and pagination, road polylines, real estimates, Apple Maps attribution, and the itinerary action.
- Inspected live address-search results for the road catalog. Normalized the downtown intersection queries so Lamar and the Capitol district resolve to their named intersections; Scenic Drive uses a road waypoint.
- Choice grids become one column at accessibility sizes; panels and the options form scroll. Stop cards use a shared scaled minimum height.
- Toolbar controls retain the native system appearance. Cards and buttons use `.glass` and `.glassProminent`; content panels use `.regularMaterial`.
- Included [home](docs/home-screen.png), [live route preview](docs/route-preview.png), and [options sheet](docs/ride-options.png) screenshots with the generic Austin starting point. Image metadata is stripped and pixel content is preserved.

## Scope and privacy

Routes use a small curated catalog of public Austin roads and destinations. MapKit chooses connecting roads and estimates driving time. Duration remains a target, stop time is extra, and routes may retrace roads. Road avoidance is a preference rather than a guarantee. Vehicle connectivity, booking, in-ride guidance, opening-hours checks, and duration optimization are not included.

Live device GPS acquisition remains untested. Map tiles, directions, estimates, and Liquid Glass appearance can vary with connectivity, OS version, traffic, and accessibility settings.

Personal addresses, identity metadata, credentials, signing files, local paths, logs, and raw test results are excluded from the repository. Only the approved GitHub handle and noreply commit attribution are retained. Public screenshots use the generic city starting point, not a device location.
