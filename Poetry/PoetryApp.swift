import SwiftUI
import UIKit

@main
struct PoetryApp: App {
    @StateObject private var musicPlayer = PoemMusicPlayer()

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
            // The onboarding pages demo composing, sealing and sharing, which only
            // exist in the Chinese app, so English readers go straight to reading.
            if hasSeenOnboarding || AppLanguage.isEnglish {
                MainAppView()
            } else {
                OnboardingView {
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
    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var scriptRawValue = PoemScript.simplified.rawValue
    @State private var selectedSection = AppSection.classics

    private var typeface: PoemTypeface {
        PoemTypeface(rawValue: typefaceRawValue) ?? .kaiti
    }

    private var script: PoemScript {
        PoemScript(rawValue: scriptRawValue) ?? .simplified
    }

    var body: some View {
        TabView(selection: $selectedSection) {
            ClassicPoetryView()
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
                PoemComposerView(
                    isActive: selectedSection == .compose,
                    onOpenArchive: { selectedSection = .archive }
                )
                    .tag(AppSection.compose)
                    .tabItem {
                        Label("织诗".poemScript(script), systemImage: "wand.and.stars")
                    }

                PoemArchiveTabView()
                    .tag(AppSection.archive)
                    .tabItem {
                        Label("藏诗".poemScript(script), systemImage: "books.vertical")
                    }
            }
        }
        .tint(Color(red: 0.77, green: 0.02, blue: 0.06))
        .environment(\.poemTypeface, typeface)
        .environment(\.poemScript, script)
    }
}

private enum AppSection: Hashable {
    case classics
    case poets
    case saved
    case compose
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
