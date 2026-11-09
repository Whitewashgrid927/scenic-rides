# Validation

Validated November 8, 2026.

## Environment

- Xcode 27.2, iOS Simulator SDK 27.2.
- iPhone 17 Pro simulator, iOS 27.0, running in the background.
- Deployment target: **iOS 26.0**; Swift 6 with complete strict-concurrency checking.
- Debug app and both test targets built successfully. Release simulator build also passed.
- No Swift compiler warnings. Xcode emits its routine App Intents metadata-extraction warning because the app has no App Intents dependency.
- Project property-list syntax and `git diff --check` pass.

The available runtime is iOS 27.0. iOS 26 API availability is checked by compilation with a 26.0 deployment target; a separate iOS 26 runtime and a physical device have not been tested.

## Automated coverage

**13 unit tests and 14 UI tests pass across the main run and focused reruns.** Focused reruns verified the final loading/no-fit states and corrected test queries for native picker items and combined `LabeledContent` accessibility labels. No test failures remain unresolved.

Unit coverage includes:

- All 15 nonempty scenery combinations across 30-, 60-, and 90-minute budgets, with and without a stop. Shortlists cover every selected category, remain deterministic, include a compact fallback, and contain at most five distinct candidates.
- All 12 loops return to the selected coordinate and sum every driving leg's distance and time.
- All 12 loops with each of the three stop kinds include one timed stop. Stop time contributes to the total and advances the return-leg departure estimate.
- Budget filtering uses exact seconds: a route at the boundary qualifies, while one exceeding it by a fraction of a second does not. Missing scenery disqualifies a route. Matches are ranked by closest total under budget.
- Increasing a stop's duration can remove a previously fitting route without dropping the stop or changing the requested budget.
- No-fit states use actual completed estimates. Empty scenery, a stop consuming the whole budget, and unsupported starts are rejected before network work.
- Actual `MKDirections.Request` objects receive the selected highway/toll preferences and departure time.
- Retry preserves completed candidates, including over-budget results; a new request clears cached choices.
- Failed return legs never publish partial trips. Coincident waypoints skip zero-length requests. Cancelled and stale completions cannot restore old routes or budgets.

UI coverage includes:

- Home defaults, budget selection, handoff, and preserving preferences when returning.
- Multiple scenery selections, visible selected state, and the empty-selection guard.
- Starting-point selection/cancellation, live public-place search, and location-permission denial recovery.
- Swiping and pagination select the matching map and itinerary, including the final return.
- Coffee selection, stop-duration changes, highway toggle persistence, Apply, Cancel, and the total-time breakdown.
- No-fit and impossible-stop states never present over-budget recommendations.
- Failed alternatives can retry without losing the selected successful route. Loading can be dismissed.
- Home, options, and route-preview actions remain reachable at the largest accessibility text size.
- Live MapKit requests for a 30-minute drive, a 60-minute Water + Hills outing with a 15-minute coffee stop, and a 90-minute outing selecting all four scenery categories with a 20-minute walk. Displayed route totals fit the selected budgets, and the stop itineraries return to the selected city starting point.

The observed live best-fit totals were approximately 24, 54, and 88 minutes respectively. They are observations from this run, not fixed route durations. Some alternatives in the 90-minute search failed to load; the completed matching route remained available with a retry action.

The live search and directions checks require Apple's services. Other preview UI tests use a debug-only fixture planner. The Release binary excludes the fixture planner and its environment flag. The published route screenshot uses live MapKit directions. This delivery's live stop checks cover coffee and walking; view stops have unit coverage.

## Visual verification

- Inspected native captures of multiple scenery selection, the stop-time options sheet, all three live budget results, a stop itinerary, and the largest-text options and preview layouts.
- Confirmed selected glass controls, card peeking and pagination, road polylines, total-time estimates, driving/stop breakdowns, Apple Maps attribution, and the itinerary action.
- Checked public address-search results for the new Bull Creek area and City Park Road anchors. Lakewood Drive is represented as a road waypoint; City Park Road resolves at Pearce Road.
- Choice grids become one column at accessibility sizes; panels and the options form scroll. Apply stays above the sheet's safe area.
- Toolbar controls retain the native system appearance. Cards and buttons use `.glass` and `.glassProminent`; content panels use `.regularMaterial`.
- Updated [home](docs/home-screen.png), [live route preview](docs/route-preview.png), and [options sheet](docs/ride-options.png) screenshots. Image metadata is stripped with pixel content preserved.

## Scope and privacy

Routes use 12 curated public-road loops and three optional public destinations. Every recommendation covers the selected scenery tags and fits the total budget using its MapKit driving estimates plus planned stop time. The planner checks at most five candidates and shows up to three matches; it does not exhaustively search Austin's roads or promise to use every minute. A matching route outside the shortlist may exist.

Scenery tags describe portions of the outing, including the chosen stop. MapKit chooses connecting roads, which can retrace portions of the trip. Road avoidance is a preference. Traffic, parking, access, and time actually spent at a stop can change the total. Opening-hours checks, vehicle connectivity, booking, in-ride guidance, and language-model integration are not included.

Live device GPS acquisition remains untested. Map tiles, directions, estimates, and Liquid Glass appearance can vary with connectivity, OS version, traffic, and accessibility settings.

Personal addresses, identity metadata, credentials, signing files, local paths, logs, and raw test results are excluded from the repository. Only the approved GitHub handle and noreply commit attribution are retained. Public screenshots use the generic Austin starting point, not a device location.
