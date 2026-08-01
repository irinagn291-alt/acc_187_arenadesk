import SwiftUI

@MainActor
final class FloorViewModel: ObservableObject {
    @Published var zones: [ZoneSummary] = []
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func reload() async {
        zones = (try? await environment.zones.fetchSummaries()) ?? []
    }
}

struct FloorView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<FloorViewModel>()

    var body: some View {
        Group {
            if let viewModel = holder.value {
                FloorContent(viewModel: viewModel)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = FloorViewModel(environment: environment)
            }
        }
    }
}

struct FloorContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: FloorViewModel

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if viewModel.zones.isEmpty {
                NothingHereView(
                    image: .emptyZones,
                    title: "No zones",
                    detail: "Add a zone during onboarding or from the floor editor to start tracking seats."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.spaceS) {
                        FloorBanner(
                            image: .floorBanner,
                            caption: "Zones and seat readiness",
                            height: 150
                        )
                        ForEach(viewModel.zones) { summary in
                            NavigationLink {
                                ZoneDetailView(zoneID: summary.zone.id)
                            } label: {
                                zoneRow(summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.spaceM)
                    .padding(.bottom, Theme.consoleBottomClearance)
                }
            }
        }
        .consoleRootChrome(title: "Floor", subtitle: "Zones and seat readiness")
        .task { await viewModel.reload() }
        .refreshable { await viewModel.reload() }
    }

    private func zoneRow(_ summary: ZoneSummary) -> some View {
        ConsolePanel {
            HStack(spacing: Theme.spaceS) {
                summary.zone.kind.badgeImage.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.zone.name)
                        .font(Theme.headlineFont())
                        .foregroundStyle(palette.text)
                    Text(summary.zone.kind.displayName)
                        .font(Theme.captionFont())
                        .foregroundStyle(palette.secondaryText)
                    if let occupancy = summary.occupancy {
                        MetricStrip(fraction: occupancy / 100, color: palette.primary)
                    }
                }
                Spacer(minLength: 0)
                ReadinessDial(title: "Ready", value: summary.readiness, size: 64)
            }
        }
    }
}
