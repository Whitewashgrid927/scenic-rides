import SwiftUI

struct RideOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: RideOptions
    let onApply: (RideOptions) -> Void

    init(options: RideOptions, onApply: @escaping (RideOptions) -> Void) {
        _draft = State(initialValue: options)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The pace") {
                    Picker("The pace", selection: $draft.pace) {
                        ForEach(RidePace.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("ridePace")
                }
                if draft.pace == .stop {
                    Section("Stop for") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: 10) {
                            ForEach(RideStopKind.allCases) { kind in
                                RideChoiceButton(title: kind.name, symbol: kind.symbol, selected: draft.stopKind == kind, vertical: !dynamicTypeSize.isAccessibilitySize) {
                                    draft.stopKind = kind
                                }
                                .accessibilityIdentifier("stopKind-\(kind.rawValue)")
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    Section {
                        Picker("Time at stop", selection: $draft.stopDuration) {
                            ForEach(StopDuration.allCases) { Text($0.label).tag($0) }
                        }
                        .accessibilityIdentifier("stopTime")
                    } footer: {
                        Text("On-device AI helps choose a nearby stop when available. Stop time and the drive back are included in your budget.")
                    }
                }
                Section {
                    Toggle("Avoid highways", isOn: $draft.roads.avoidHighways)
                        .accessibilityIdentifier("avoidHighways")
                    Toggle("Avoid tolls", isOn: $draft.roads.avoidTolls)
                        .accessibilityIdentifier("avoidTolls")
                } header: {
                    Text("The roads")
                } footer: {
                    Text("Road preferences are applied where possible. Your ride always returns to its starting point.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onApply(draft)
                    dismiss()
                } label: {
                    Text("Apply")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("applyRideOptions")
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Make it yours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelRideOptions")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

struct RideChoiceButton: View {
    @ScaledMetric(relativeTo: .subheadline) private var verticalHeight = 84
    let title: String
    let symbol: String
    let selected: Bool
    var vertical = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if vertical {
                    VStack(spacing: 8) {
                        Image(systemName: symbol).font(.title3)
                        Text(title)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                        Text(title)
                        if selected { Image(systemName: "checkmark.circle.fill").font(.caption) }
                    }
                }
            }
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: vertical ? verticalHeight : 40)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(selected ? .blue : .white)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Color.blue : .clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
