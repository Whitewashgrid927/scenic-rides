import SwiftUI

@main
struct ScenicRidesApp: App {
    @State private var selectedRequest: RideRequest?

    var body: some Scene {
        WindowGroup {
            HomeScreen { selectedRequest = $0 }
                .preferredColorScheme(.dark)
                .tint(.blue)
                .sheet(item: $selectedRequest) { request in
                    RideRequestSummary(request: request)
                        .preferredColorScheme(.dark)
                }
        }
    }
}
