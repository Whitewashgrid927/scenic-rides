# Austin catalog

The bundled JSON contains 24 route templates, 49 public road anchors, and 15 public stops. Runtime MapKit requests provide the driving geometry and estimates. Catalog coordinates support geographic ranking and place-resolution checks; they do not define a drivable polyline.

## Route index

| ID | Route | Area | Scenery |
| --- | --- | --- | --- |
| 0 | Lake & skyline | Central Austin | water, greenery, city |
| 1 | Riverside loop | East Austin | water, greenery, city |
| 2 | Hills & river | West Austin | water, hills, greenery |
| 3 | Westlake wander | Westlake | water, hills, greenery |
| 4 | City & skyline | Downtown | city |
| 5 | East Austin loop | East Austin | city |
| 6 | River, hills & skyline | Central & west | water, hills, greenery, city |
| 7 | Austin highlights | Central & west | water, hills, greenery, city |
| 8 | A little farther west | West Austin | water, hills, greenery |
| 9 | The long scenic way | Across Austin | water, hills, greenery, city |
| 10 | A moment by the river | Downtown | water, greenery, city |
| 11 | Around downtown | Downtown | city |
| 12 | Along Shoal Creek | Central Austin | greenery, city |
| 13 | Hyde Park ramble | North central | greenery, city |
| 14 | Mueller lakeside | Mueller | water, greenery, city |
| 15 | Cherrywood shade | East Austin | greenery, city |
| 16 | Walnut Creek wander | North Austin | greenery |
| 17 | Balcones & Gracy Farms | North Austin | greenery, city |
| 18 | Spicewood hills | Northwest Austin | water, hills, greenery |
| 19 | Northwest ridge | Northwest Austin | hills, greenery |
| 20 | Barton Hills meander | South central | hills, greenery, city |
| 21 | South Austin parks | South Austin | greenery, city |
| 22 | Circle C greenways | Southwest Austin | greenery |
| 23 | East riverbend | Southeast Austin | water, greenery, city |

## Stops and sources

Addresses and catalog coordinates were checked with native MapKit search. Official venue or park sources are linked below. Source verification does not guarantee current opening hours, access, or parking.

| Stop | Public address | Kinds | Source |
| --- | --- | --- | --- |
| Mozart’s Coffee Roasters | 3825 Lake Austin Blvd | coffee | [Source](https://mozartscoffee.com/pages/frequently-asked-questions) |
| Epoch Coffee — North Loop | 221 W North Loop Blvd | coffee | [Source](https://epochcoffee.com/) |
| Epoch Coffee — The Village | 2700 W Anderson Ln | coffee | [Source](https://epochcoffee.com/) |
| Epoch Coffee — Far West | 3900 Far West Blvd | coffee | [Source](https://epochcoffee.com/) |
| Cherrywood Coffeehouse | 1400 E 38 1/2 St | coffee | [Source](https://cherrywoodcoffeehouse.com/contact/) |
| Radio Coffee & Beer | 4204 Menchaca Rd | coffee | [Source](https://radiocoffeeandbeer.com/contact-us) |
| Mount Bonnell | 3800 Mount Bonnell Rd | view | [Source](https://www.austintexas.gov/parks/locations/park-directory) |
| Butler Park | 1000 Barton Springs Rd | view, walk | [Source](https://www.austintexas.gov/parks/locations/park-directory) |
| Walsh Boat Landing | 1600 Scenic Dr | view | [Source](https://www.austintexas.gov/parks/locations/walsh-boat-landing) |
| Bull Creek District Park | 6701 Lakewood Dr | view, walk | [Source](https://www.austintexas.gov/parks/locations/park-directory) |
| Mayfield Park | 3805 W 35th St | walk | [Source](https://www.austintexas.gov/parks/locations/park-directory) |
| Pease Park | 1100 Kingsbury St | walk | [Source](https://www.austintexas.gov/parks/locations/park-directory) |
| Walnut Creek Metropolitan Park | 12138 N Lamar Blvd | walk | [Source](https://www.austintexas.gov/parks/locations/park-directory) |
| Dick Nichols District Park | 8011 Beckett Rd | walk | [Source](https://www.austintexas.gov/parks/locations/park-directory) |
| Bartholomew District Park | 5201 Berkman Dr | walk | [Source](https://www.austintexas.gov/parks/locations/park-directory) |

## Add or change a route

1. Add public road anchors with stable IDs, names, addresses, and MapKit-checked coordinates. Use distinct IDs for stops and road anchors. Keep waypoints on publicly accessible roads.
2. Add a route with a unique integer ID, name, area, scenery tags, SF Symbol, planning hint, and ordered anchor IDs. Existing IDs remain stable. Routes must have distinct anchor sets and no repeated anchors.
3. Treat `planningMinutes` as a rough city-center ordering hint only. Actual eligibility always comes from MapKit, including the selected start, stop duration, and return.
4. Add stops with a stable ID, public address, coordinates, supported kinds, scenery, access note, and an HTTPS source URL. A stop must pass the geographic shortlist for a route; merely adding it does not attach it to every outing.
5. Run catalog, planner, and stop-ranking tests. Verify new addresses and actual directions with MapKit, inspect the route in the app, and check that the trip returns to the selected start.

## Validation rules

`AustinCatalog.decode` rejects unsupported versions, duplicate or overlapping IDs, repeated route anchor sets, missing anchors, invalid coordinates, places outside the Austin coverage area, empty scenery/kind sets, nonpositive planning hints, and non-HTTPS stop sources. A missing or invalid bundled catalog produces an empty state instead of invented routes.

The nearby-stop shortlist requires the requested kind, all selected scenery across route plus stop, a stop within 3 km of a scenic anchor, and no more than 5 km of added straight-line distance. At most four candidates enter the local model. These limits control candidate work, while MapKit determines actual roads and time.
