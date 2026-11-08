import SwiftUI

@main
struct ScenicRidesApp: App {
    @State private var selectedRequest: RideRequest?

    var body: some Scene {
        WindowGroup {
            HomeScreen { selectedRequest = $0 }
                .preferredColorScheme(.dark)
                .tint(.blue)
                .fullScreenCover(item: $selectedRequest) { request in
                    RoutePreviewScreen(request: request)
                        .preferredColorScheme(.dark)
                }
        }
    }
}
