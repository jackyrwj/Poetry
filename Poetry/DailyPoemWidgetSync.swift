import UIKit
import WidgetKit

/// Keeps the 每日一首 widget's copy of the daily cycle in step with the
/// reader's script and typeface. Cheap to call: it only writes (and reloads
/// the widget) when something actually changed.
enum DailyPoemWidgetSync {
    @MainActor static func sync() {
        let script = currentScript
        let typeface = PoemTypeface(rawValue: UserDefaults.standard.string(forKey: PoemTypeface.storageKey) ?? "") ?? .kaiti
        // Seal script is decorative; a home screen poem needs to be readable.
        let font = (typeface == .xiaozhuan ? PoemTypeface.kaiti : typeface).widgetFont

        let payload = DailyPoemWidgetStore.Payload(
            cycle: DailyPoemPicker.dailyPoems.map { widgetPoem(from: $0, script: script) },
            fontFile: font.file,
            fontName: font.name,
            isEnglish: AppLanguage.isEnglish
        )

        var changed = DailyPoemWidgetStore.write(payload)
        changed = writeFavorites(script: script) || changed
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: DailyPoemWidgetStore.widgetKind)
        }
        exportImagesIfNeeded()
    }

    /// Called whenever the saved poems change, so the widget's poem picker
    /// (and any widget pinned to a poem that was just removed) stays current.
    @MainActor static func syncFavorites() {
        if writeFavorites(script: currentScript) {
            WidgetCenter.shared.reloadTimelines(ofKind: DailyPoemWidgetStore.widgetKind)
        }
        exportImagesIfNeeded()
    }

    private static var currentScript: PoemScript {
        PoemScript(rawValue: UserDefaults.standard.string(forKey: PoemScript.storageKey) ?? "") ?? .simplified
    }

    private static func writeFavorites(script: PoemScript) -> Bool {
        let poems = ClassicPoemFavorites.loadPoems()
            .sorted { ClassicPoemFavorites.mark(for: $0.id).savedAt > ClassicPoemFavorites.mark(for: $1.id).savedAt }
            .map { widgetPoem(from: $0, script: script) }
        return DailyPoemWidgetStore.writeFavorites(poems)
    }

    private static func widgetPoem(from poem: ClassicPoem, script: PoemScript) -> DailyPoemWidgetStore.Poem {
        DailyPoemWidgetStore.Poem(
            id: poem.id,
            title: poem.title.poemScript(script),
            author: poem.author.poemScript(script),
            dynasty: poem.dynasty.poemScript(script),
            lines: poem.lines.map { $0.poemScript(script) },
            englishTitle: poem.englishTitle,
            englishAuthor: AppLanguage.isEnglish ? poem.localizedAuthor : nil,
            background: poem.sceneryBackground.imageName,
            landscapeBackground: poem.sceneryBackground.landscapeImageName,
            avatar: ClassicPoetLibrary.find(name: poem.author)?.avatarAsset
        )
    }

    /// Every painting (a saved poem may use any of them) plus the portraits
    /// of the poets that can appear; existing files are skipped.
    @MainActor private static func exportImagesIfNeeded() {
        let paintings = PoemBackground.allCases.flatMap { [$0.imageName, $0.landscapeImageName] }
        let portraits = ClassicPoetLibrary.featured.map(\.avatarAsset)
        let imageNames = Set((paintings + portraits).compactMap { $0 })
        guard !isExportingImages else { return }
        isExportingImages = true
        Task.detached(priority: .utility) {
            let exported = exportImages(named: imageNames)
            await MainActor.run {
                isExportingImages = false
                if exported { WidgetCenter.shared.reloadTimelines(ofKind: DailyPoemWidgetStore.widgetKind) }
            }
        }
    }

    @MainActor private static var isExportingImages = false

    /// Widgets can't read the app's asset catalog, so each painting and portrait
    /// is copied once into the App Group, scaled down to what a widget needs
    /// (widgets have a tight memory budget). Returns whether anything was written.
    nonisolated private static func exportImages(named names: Set<String>) -> Bool {
        guard let directory = DailyPoemWidgetStore.imagesDirectory else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var exported = false
        for name in names {
            guard let url = DailyPoemWidgetStore.imageURL(named: name),
                  !FileManager.default.fileExists(atPath: url.path),
                  let image = UIImage(named: name) else { continue }
            let isPortrait = name.hasPrefix("poet_")
            let scaled = downscaled(image, maxPixels: isPortrait ? 240 : 900, opaque: !isPortrait)
            let data = isPortrait ? scaled.pngData() : scaled.jpegData(compressionQuality: 0.8)
            if let data, (try? data.write(to: url, options: .atomic)) != nil {
                exported = true
            }
        }
        return exported
    }

    nonisolated private static func downscaled(_ image: UIImage, maxPixels: CGFloat, opaque: Bool) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, maxPixels / max(pixelSize.width, pixelSize.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let size = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension PoemTypeface {
    var widgetFont: (file: String, name: String) {
        switch self {
        case .kaiti, .xiaozhuan: ("HuiwenMincho.otf", "Huiwen-mincho")
        case .wenyue: ("WenYueGuTiFangSongTC.otf", "WenYue_GuTiFangSong_F")
        case .wenkai: ("LXGWWenKaiLite-Regular.ttf", "LXGWWenKaiLite-Regular")
        case .songti: ("SourceHanSerifCN-ExtraLight.otf", "SourceHanSerifCN-ExtraLight")
        case .mashan: ("MaShanZheng-Regular.ttf", "MaShanZheng-Regular")
        }
    }
}
