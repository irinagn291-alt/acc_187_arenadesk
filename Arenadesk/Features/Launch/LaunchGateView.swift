import SwiftUI

struct LaunchGateView: View {
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                wordmark
                if let error = environment.bootstrapError {
                    blockedPanel(error)
                } else {
                    openingRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spaceL)
        }
    }

    private var wordmark: some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            Text("ARENADESK")
                .font(Theme.titleFont())
                .kerning(4)
                .foregroundStyle(palette.text)
            Rectangle()
                .fill(palette.accent)
                .frame(width: 56, height: 3)
        }
    }

    private var openingRow: some View {
        HStack(spacing: Theme.spaceXS) {
            ProgressView()
                .controlSize(.small)
                .tint(palette.accent)
            Text("Opening the floor")
                .font(Theme.bodyFont())
                .foregroundStyle(palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func blockedPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            Label("The venue database did not open", systemImage: "externaldrive.badge.xmark")
                .font(Theme.headlineFont())
                .foregroundStyle(palette.error)
            Text(message)
                .font(Theme.captionFont())
                .foregroundStyle(palette.secondaryText)
        }
        .padding(Theme.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cornerMedium))
    }
}
