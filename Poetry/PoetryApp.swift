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
    @State private var showsSplash = true
    @State private var showsOnboardingPaywall = false

    var body: some View {
        ZStack {
            if showsSplash {
                AppSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                if hasSeenOnboarding {
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
        }
        .sheet(isPresented: $showsOnboardingPaywall) {
            PaywallView {
                showsOnboardingPaywall = false
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                showsSplash = false
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
                PoemComposerView(isActive: selectedSection == .compose)
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

/// The first English release follows the device's preferred language. The
/// underlying poems remain in Chinese so that their original form is intact.
enum AppLanguage {
    static var isEnglish: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("en") == true
    }

    static func copy(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}

private struct AppSplashView: View {
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.93, blue: 0.86)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                AppIconImage()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)

                Text(AppLanguage.copy("织诗", "Woven Verse"))
                    .font(AppLanguage.isEnglish
                        ? .system(size: 28, weight: .medium, design: .serif)
                        : .custom("HuiwenMincho", size: 28))
                    .foregroundStyle(Color(red: 0.18, green: 0.14, blue: 0.10))
                    .tracking(AppLanguage.isEnglish ? 0.5 : 4)
            }
        }
    }
}

private struct AppIconImage: View {
    var body: some View {
        if let image = Self.appIcon {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.60, green: 0.08, blue: 0.06))
                .overlay {
                    Text("诗")
                        .font(.custom("FZXiaoZhuanTi", size: 46))
                        .foregroundStyle(.white)
                }
        }
    }

    private static var appIcon: UIImage? {
        if let image = UIImage(named: "AppIcon") {
            return image
        }

        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else {
            return nil
        }

        return UIImage(named: iconName)
    }
}
