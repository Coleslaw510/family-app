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
        .tint(Theme.accent)
        .task { await app.bootstrap() }
    }
}

struct MainShell: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        TabView(selection: $app.tab) {
            HomeView()
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.symbol) }
                .tag(AppTab.home)
            MarriageView()
                .tabItem { Label(AppTab.marriage.title, systemImage: AppTab.marriage.symbol) }
                .tag(AppTab.marriage)
            FamilyBoardView()
                .tabItem { Label(AppTab.family.title, systemImage: AppTab.family.symbol) }
                .tag(AppTab.family)
            FoodTabView()
                .tabItem { Label(AppTab.food.title, systemImage: AppTab.food.symbol) }
                .tag(AppTab.food)
            CalendarView()
                .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.symbol) }
                .tag(AppTab.calendar)
            VacationsView()
                .tabItem { Label(AppTab.vacations.title, systemImage: AppTab.vacations.symbol) }
                .tag(AppTab.vacations)
        }
        .tint(Theme.accent)
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
