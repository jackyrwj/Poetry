import SwiftUI
import UIKit

@main
struct PoetryApp: App {
    @StateObject private var musicPlayer = PoemMusicPlayer()

    init() {
        StoreManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(musicPlayer)
                .onAppear {
                    _ = StoreManager.shared
                }
        }
    }
}

private struct RootContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage(SeasonalAppearance.firstWelcomeRequiredKey) private var seasonalWelcomeRequired = false
    @State private var showsOnboardingPaywall = false

    var body: some View {
        ZStack {
            if hasSeenOnboarding {
                MainAppView()
            } else {
                OnboardingView {
                    ClassicPoemFavorites.seedStarterPoemIfNeeded()
                    // Only a new reader is required to choose how their first
                    // seasonal paper should behave. Existing readers see the
                    // seasonal note as a normal, dismissible welcome.
                    seasonalWelcomeRequired = true
                    withAnimation(.easeOut(duration: 0.4)) {
                        hasSeenOnboarding = true
                    }

                    // Refresh entitlements before deciding whether to present. A
                    // returning member can otherwise see the paywall briefly while
                    // StoreKit is still resolving their existing purchase.
                    Task { @MainActor in
                        await StoreManager.shared.refreshPurchaseStatus()
                        guard !StoreManager.shared.isPremium else { return }
                        showsOnboardingPaywall = true
                    }
                }
            }
        }
        .sheet(isPresented: $showsOnboardingPaywall) {
            PaywallView {
                showsOnboardingPaywall = false
            }
        }
    }
}

private struct MainAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var scriptRawValue = PoemScript.simplified.rawValue
    @AppStorage(PoemBackground.storageKey) private var backgroundRawValue = PoemBackground.defaultBackground.rawValue
    @AppStorage(SeasonalAppearance.lastPresentedSeasonKey) private var lastPresentedSeason = ""
    @AppStorage(SeasonalAppearance.firstWelcomeRequiredKey) private var seasonalWelcomeRequired = false
    @ObservedObject private var store = StoreManager.shared
    @State private var selectedSection = AppSection.classics
    @State private var composePath = NavigationPath()
    /// Set by a tap on the 每日一首 widget; the Read tab opens that poem.
    @State private var pendingPoemID: String?
    /// Set by the 秋日诗会 App Store event deep link.
    @State private var opensAutumnGathering = false
    @State private var seasonalWelcome: SeasonalAppearance.SolarTerm?

    private var typeface: PoemTypeface {
        PoemTypeface(rawValue: typefaceRawValue) ?? .kaiti
    }

    private var script: PoemScript {
        PoemScript(rawValue: scriptRawValue) ?? .simplified
    }

    var body: some View {
        TabView(selection: $selectedSection) {
            ClassicPoetryView(pendingPoemID: $pendingPoemID, opensAutumnGathering: $opensAutumnGathering)
                .environment(\.writeAutumnPoem, AppLanguage.isEnglish ? nil : openComposer)
                .tag(AppSection.classics)
                .tabItem {
                    Label(AppLanguage.copy("赏诗", "Read").poemScript(script), systemImage: "book.pages")
                }

            PoetGalleryView()
                .tag(AppSection.poets)
                .tabItem {
                    Label(AppLanguage.copy("诗人", "Poets").poemScript(script), systemImage: "person.2")
                }

            if AppLanguage.isEnglish {
                SavedClassicPoemsView()
                    .tag(AppSection.saved)
                    .tabItem {
                        Label("Saved", systemImage: "bookmark")
                    }
            } else {
                // 藏詩 lives inside 成詩: every saved poem comes from composing,
                // so the archive is pushed onto the composer's own stack.
                NavigationStack(path: $composePath) {
                    PoemComposerView(
                        isActive: selectedSection == .compose && composePath.isEmpty,
                        onOpenArchive: openArchive
                    )
                    .navigationBarHidden(true)
                    .navigationDestination(for: ComposeRoute.self) { route in
                        switch route {
                        case .archive:
                            PoemArchiveView()
                        }
                    }
                }
                .tag(AppSection.compose)
                .tabItem {
                    Label("成詩".poemScript(script), systemImage: "text.book.closed")
                }
            }

            ProfileView()
                .tag(AppSection.profile)
                .tabItem {
                    Label(
                        AppLanguage.copy("我的", "Settings").poemScript(script),
                        systemImage: AppLanguage.isEnglish ? "gearshape" : "person.crop.circle"
                    )
                }
        }
        .tint(Color(red: 0.77, green: 0.02, blue: 0.06))
        .environment(\.poemTypeface, typeface)
        .environment(\.poemScript, script)
        .onOpenURL { url in
            if AutumnGathering.matches(url) {
                selectedSection = .classics
                opensAutumnGathering = true
                return
            }
            guard let id = DailyPoemWidgetStore.poemID(from: url) else { return }
            selectedSection = .classics
            pendingPoemID = id
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            WidgetGuide.recordActiveDay()
            DailyPoemWidgetSync.sync()
            refreshSeasonalAppearance()
        }
        .onChange(of: selectedSection) { oldSection, _ in
            // Leaving 成詩 drops the pushed 藏诗 pages, so returning to the
            // tab always lands on the composer its label promises.
            if oldSection == .compose {
                composePath = NavigationPath()
            }
        }
        .onChange(of: typefaceRawValue) { _, _ in DailyPoemWidgetSync.sync() }
        .onChange(of: scriptRawValue) { _, _ in DailyPoemWidgetSync.sync() }
        .overlay {
            if let solarTerm = seasonalWelcome {
                SeasonalWelcomeView(
                    solarTerm: solarTerm,
                    isRequired: seasonalWelcomeRequired,
                    onViewPapers: {
                        selectedSection = .profile
                        dismissSeasonalWelcome()
                    },
                    onDismiss: dismissSeasonalWelcome
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: seasonalWelcome != nil)
    }

    private func openComposer() {
        composePath = NavigationPath()
        selectedSection = .compose
    }

    private func openArchive() {
        var path = NavigationPath()
        path.append(ComposeRoute.archive)
        composePath = path
    }

    private func refreshSeasonalAppearance() {
        let solarTerm = SeasonalAppearance.current
        if let background = PoemBackground(rawValue: backgroundRawValue),
           !SeasonalAppearance.hasAccess(to: background, isPremium: store.isPremium) {
            // A manually retained seasonal paper stays until its season ends;
            // then a free reader returns to the default paper on next launch.
            backgroundRawValue = PoemBackground.defaultBackground.rawValue
        }

        guard seasonalWelcome == nil,
              lastPresentedSeason != solarTerm.rawValue else { return }
        seasonalWelcome = solarTerm
    }

    private func dismissSeasonalWelcome() {
        guard let solarTerm = seasonalWelcome else { return }
        lastPresentedSeason = solarTerm.rawValue
        seasonalWelcomeRequired = false
        seasonalWelcome = nil
    }
}

private struct SeasonalWelcomeView: View {
    private let seasonalCinnabar = Color(red: 0.77, green: 0.02, blue: 0.06)
    private let seasonalInk = Color(red: 0.08, green: 0.075, blue: 0.07)
    private let seasonalMutedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let solarTerm: SeasonalAppearance.SolarTerm
    let isRequired: Bool
    let onViewPapers: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            GeometryReader { proxy in
                let width = min(proxy.size.width - 48, 350)
                let height = min(proxy.size.height - 120, 468)
                VStack(spacing: 0) {
                    Image(solarTerm.background.rawValue)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: min(205, height * 0.44))
                        .clipped()
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center) {
                            Text(solarTerm.name.poemScript(script))
                                .font(typeface.tinySealFont)
                                .tracking(1.6)
                                .foregroundStyle(seasonalCinnabar)

                            Text(AppLanguage.copy("节气限免", "SOLAR-TERM FREE").poemScript(script))
                                .font(.system(size: 9, weight: .semibold, design: .serif))
                                .tracking(0.8)
                                .foregroundStyle(seasonalMutedInk)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(seasonalCinnabar.opacity(0.08), in: Capsule())

                            Spacer()

                            if !isRequired {
                                Button(action: onDismiss) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(seasonalMutedInk)
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(AppLanguage.copy("关闭", "Close"))
                            }
                        }

                        Text(AppLanguage.copy("\(solarTerm.name)纸面已发放", "\(solarTerm.name) paper is here").poemScript(script))
                            .font(typeface.font(size: 29))
                            .foregroundStyle(seasonalInk)
                            .padding(.top, 10)

                        Text(solarTerm.inscription.poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(seasonalInk.opacity(0.78))
                            .padding(.top, 6)

                        Text(solarTerm.detail.poemScript(script))
                            .font(typeface.tinySealFont)
                            .foregroundStyle(seasonalMutedInk)
                            .padding(.top, 7)

                        Spacer(minLength: 12)

                        Button(action: onViewPapers) {
                            Text(AppLanguage.copy("查看纸面", "View papers").poemScript(script))
                                .font(typeface.smallFont)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(seasonalCinnabar, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .background(Color(red: 0.985, green: 0.968, blue: 0.925))
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.68), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

private enum AppSection: Hashable {
    case classics
    case poets
    case saved
    case compose
    case profile
}

enum ComposeRoute: Hashable {
    case archive
}

/// Follows the localization iOS picked for the bundle, so the in-app copy always
/// matches the home screen name. Chinese variants resolve to zh-Hans / zh-Hant;
/// every other language falls back to English. The underlying poems remain in
/// Chinese so that their original form is intact.
enum AppLanguage {
    static let isEnglish: Bool =
        Bundle.main.preferredLocalizations.first?.lowercased().hasPrefix("en") == true

    static func copy(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}
