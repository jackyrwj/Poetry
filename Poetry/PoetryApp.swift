import SwiftUI
import UIKit

@main
struct PoetryApp: App {
    var body: some Scene {
        WindowGroup {
            RootContentView()
        }
    }
}

private struct RootContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showsSplash = true
    @State private var spotlightGuide = SpotlightGuide()

    var body: some View {
        ZStack {
            if showsSplash {
                AppSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                if hasSeenOnboarding {
                    PoemComposerView()
                } else {
                    OnboardingView {
                        withAnimation(.easeOut(duration: 0.4)) {
                            hasSeenOnboarding = true
                        }
                    }
                }
            }
        }
        .environment(\.spotlightGuide, spotlightGuide)
        .alert(
            "教程完成",
            isPresented: Binding(
                get: { spotlightGuide.showsCompletionAlert },
                set: { spotlightGuide.showsCompletionAlert = $0 }
            )
        ) {
            Button("知道了", role: .cancel) {
                spotlightGuide.showsCompletionAlert = false
            }
        } message: {
            Text("你已经完成了一次作诗、分享与回看历史的完整流程。")
        }
        .task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                showsSplash = false
            }
        }
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

                Text("织诗")
                    .font(.custom("HuiwenMincho", size: 28))
                    .foregroundStyle(Color(red: 0.18, green: 0.14, blue: 0.10))
                    .tracking(4)
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
