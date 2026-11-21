import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch app.phase {
            case .loading:
                ProgressView()
                    .tint(Theme.accent)
            case .signedOut:
                OnboardingView()
            case .ready:
                MainShell()
            }
            if let celebration = app.celebration {
                CelebrationOverlay(title: celebration.title)
                    .transition(.opacity)
                    .task(id: celebration.id) {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        if app.celebration?.id == celebration.id {
                            app.celebration = nil
                        }
                    }
            }
        }
        .preferredColorScheme(.light)
        .tint(Theme.accent)
        .task { await app.bootstrap() }
    }
}

struct MainShell: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch app.tab {
                case .home:
                    HomeView()
                case .budget:
                    BudgetView()
                case .marriage:
                    MarriageView()
                case .family:
                    FamilyBoardView()
                case .calendar:
                    CalendarView()
                case .vacations:
                    VacationsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            FamilyTabBar(tab: $app.tab)
        }
        .background(Theme.bg)
        .overlay(alignment: .top) {
            if let banner = app.banner, app.phase == .ready {
                BannerToast(text: banner) { app.banner = nil }
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.banner)
    }
}

@main
struct FamilyAppApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
        }
    }
}
