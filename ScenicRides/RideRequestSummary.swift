import SwiftUI

/// A small, truthful handoff for the home-screen build. Replace this presentation
/// with route discovery when that feature is implemented; it does not book a ride.
struct RideRequestSummary: View {
    @Environment(\.dismiss) private var dismiss
    let request: RideRequest

    var body: some View {
        NavigationStack {
            Form {
                Section("Your round trip") {
                    LabeledContent("Starting point", value: request.startingPlace.name)
                    LabeledContent("Ride length", value: "\(request.duration.rawValue) minutes")
                        .accessibilityIdentifier("selectedRideLength")
                    Label("Returns to your starting point", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ride preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
