# Validation

Validated November 8–9, 2026.

## Environment and builds

- Xcode 27.2, iOS Simulator SDK 27.2, iPhone 17 Pro simulator running iOS 27.0.
- Deployment target **iOS 26.0**; Swift 6 with complete strict-concurrency checking.
- Debug app, both test targets, and Release simulator build pass.
- The Release bundle declares minimum OS 26.0, includes `AustinCatalog.json`, links Foundation Models, and excludes the fixture planner and `SCENIC_ROUTE_TEST_SCENARIO` flag.
- No Swift compiler warnings. The routine App Intents metadata-extraction warning appears because the app has no App Intents dependency.
- Project property-list syntax and `git diff --check` pass.

The available simulator runtime is iOS 27.0. Compilation checks API availability against the 26.0 deployment target; an iOS 26 runtime and a physical iPhone have not been tested.

## Automated coverage

**26 unit tests and 18 UI tests pass.** The final unit/live-service run and the complete remaining UI run have no unresolved test failures.

Unit coverage includes:

- The bundled 24-route, 15-stop catalog, stable and unique IDs, invalid catalog data, all 15 nonempty scenery combinations, deterministic candidate order, and a compact first-batch option.
- All 24 loops return to the selected coordinate. Stops match the requested kind and geographic limits, contribute their actual scenery, and are inserted along the route. A route without an eligible nearby stop is rejected.
- Every driving leg and the planned stop count toward the budget. The stop advances later departure estimates. Exact-second boundaries, missing scenery, over-budget AI suggestions, and increasing stop durations cannot bypass eligibility checks.
- MapKit receives the selected highway/toll preferences. Failed return legs cannot publish partial trips; coincident points avoid zero-length network requests.
- Five-candidate batches, up to three appended matches, cached matches, exhaustion, stable existing cards, later-batch failures, retries, and finding a fit after an initially empty batch.
- Cancellation during initial or additional loading and stale requests cannot replace current routes. A cancelled More batch can resume.
- Real model integration boundaries with injected generation results: valid reordering, unknown/duplicate/missing/empty IDs, all availability reasons, generation errors, timeout, and cancellation. Successful rankings are reused only within an unchanged request.
- The AI prompt excludes the starting name, address, and exact starting coordinate.

UI coverage includes:

- Home defaults, multi-select scenery, the empty-selection guard, and preferences preserved on return.
- Starting-point selection and cancellation, live public-place search, and location-permission denial recovery.
- Swiping and previous/next controls synchronize the map and itinerary.
- Stop kinds, duration, road options, Apply/Cancel, and the total-time breakdown.
- More routes preserves selection, adds cards, reaches exhaustion, survives a partial failure, and can be dismissed while loading.
- AI and fallback attribution are distinguished on cards and in the itinerary. The deterministic attribution test uses a debug fixture; separate live checks below exercise actual inference.
- Impossible-stop and no-fit states never present over-budget recommendations.
- Home, options, and route-preview actions remain reachable at the largest accessibility text size.

## Live Apple services and local model

All 49 public road-anchor addresses and 15 stop addresses were checked with native MapKit search. Ambiguous road queries were corrected before bundling the catalog. Venue and park sources are linked in [the catalog guide](docs/AUSTIN-CATALOG.md). This verifies address resolution, not current access or every possible road segment.

The live simulator UI test used the production planner, with no fixture environment flag, for:

| Request | Observed selected total | Result |
| --- | --- | --- |
| 30 minutes, Water, Just drive | About 24 minutes | Mueller lakeside; More routes increased the available cards from 3 to 6 and retained the selection. |
| 60 minutes, Water + Hills, 15-minute coffee stop | About 49 minutes | River, hills & skyline with Mozart’s Coffee Roasters; the card reported on-device AI selection. |
| 90 minutes, all four scenery choices, 20-minute walk | About 86 minutes | A little farther west with Pease Park; the card reported on-device AI selection. |

All displayed totals met the selected budget. Stop itineraries included the planned duration and return to the generic Austin starting point. Some alternatives in the 60-minute search failed to load; the successful matching route remained usable with retry and More routes available. Estimates are observations from this run, not fixed catalog durations.

A separate native macOS 27.3 harness compiled the actual production catalog, planner, and stop-ranker sources and used `SystemLanguageModel.default` plus live MapKit. The system reported the model available. Both runs used 90-minute budgets and 20-minute coffee stops:

- Hyde Park ramble: the real model ranked Epoch Coffee — North Loop and Cherrywood Coffeehouse, selecting Epoch North Loop. MapKit estimated about 48 minutes including the stop; the complete return trip fit.
- Barton Hills meander: the real model accepted Radio Coffee & Beer from its eligible shortlist. MapKit estimated about 51 minutes including the stop; the complete return trip fit.

Both native runs asserted actual `.onDeviceAI` attribution and complete round-trip eligibility. These were real Foundation Models calls, not mocked model results. Physical-iPhone inference remains untested.

## Visual checks

Inspected native captures of the options sheet, More routes, all three live budget results, a live stop itinerary, and the largest-text preview. Confirmed native glass controls, readable cards, selected-route outlines, pagination, road polylines, Apple Maps attribution, stop names, AI attribution, and reachable actions.

The [route screenshot](docs/route-preview.png) shows live MapKit directions after More routes. The [AI stop screenshot](docs/ai-stop-preview.png) comes from the live 90-minute UI run. The [options screenshot](docs/ride-options.png) shows the new stop-selection explanation. Screenshots use generic Austin and public destinations, with metadata stripped and pixel content preserved.

## Practical limits and privacy

The model ranks at most four eligible catalog stops. It does not generate road geometry, travel estimates, new route templates, or arbitrary destinations. Time eligibility always uses MapKit plus planned stop time. Scenery and geographic detours remain curated/approximate inputs. Opening hours, parking, closures, vehicle connectivity, booking, and in-ride guidance are not implemented. Live device GPS acquisition remains untested.

Model generation stays on-device. MapKit search and routing use Apple's network services. The app keeps preferences, routes, and rankings in memory and does not log AI prompts or responses. Starting addresses and exact start coordinates are excluded from the AI prompt.

The repository's working files and reachable history were checked for personal identity, private starting addresses, private filesystem paths, credentials, and unapproved email attribution. Only the approved GitHub handle and noreply commit identity are retained. Local harnesses, logs, raw test results, signing files, and device identifiers remain outside the repository.
