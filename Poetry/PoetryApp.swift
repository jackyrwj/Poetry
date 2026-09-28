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
    @State private var showsOnboardingPaywall = false

    var body: some View {
        ZStack {
            if hasSeenOnboarding {
                MainAppView()
            } else {
                OnboardingView {
                    ClassicPoemFavorites.seedStarterPoemIfNeeded()
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
    @State private var selectedSection = AppSection.classics
    @State private var composePath = NavigationPath()
    /// Set by a tap on the 每日一首 widget; the Read tab opens that poem.
    @State private var pendingPoemID: String?
    /// Set by the 秋日诗会 App Store event deep link.
    @State private var opensAutumnGathering = false

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
                // 藏詩 lives inside AI寫詩: every saved poem comes from composing,
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
                    Label("AI写诗".poemScript(script), systemImage: "wand.and.stars")
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
        }
        .onChange(of: selectedSection) { oldSection, _ in
            // Leaving AI写诗 drops the pushed 藏诗 pages, so returning to the
            // tab always lands on the composer its label promises.
            if oldSection == .compose {
                composePath = NavigationPath()
            }
        }
        .onChange(of: typefaceRawValue) { _, _ in DailyPoemWidgetSync.sync() }
        .onChange(of: scriptRawValue) { _, _ in DailyPoemWidgetSync.sync() }
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
