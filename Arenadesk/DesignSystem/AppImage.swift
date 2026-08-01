import SwiftUI

enum AppImage: String {
    case onboardingVenue = "onboarding-venue"
    case onboardingFloor = "onboarding-floor"
    case onboardingChecklists = "onboarding-checklists"
    case tournamentsBanner = "tournaments-banner"
    case dashboardBanner = "dashboard-banner"
    case floorBanner = "floor-banner"
    case emptyZones = "empty-zones"
    case emptyTournaments = "empty-tournaments"
    case emptyIncidents = "empty-incidents"
    case emptyDocuments = "empty-documents"
    case emptyBackups = "empty-backups"
    case zoneStandard = "zone-standard"
    case zoneVip = "zone-vip"
    case zoneConsole = "zone-console"
    case zoneStreaming = "zone-streaming"
    case zoneTournament = "zone-tournament"
    case zoneLounge = "zone-lounge"

    var image: Image { Image(rawValue) }
}

extension ZoneKind {
    var badgeImage: AppImage {
        switch self {
        case .standard: .zoneStandard
        case .vip: .zoneVip
        case .console: .zoneConsole
        case .streaming: .zoneStreaming
        case .tournament: .zoneTournament
        case .lounge: .zoneLounge
        }
    }
}
