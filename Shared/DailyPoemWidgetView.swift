import SwiftUI
import UIKit
import WidgetKit

// The 每日一首 widget's views, compiled into the app as well so the widget
// guide previews exactly what lands on the Home Screen.

struct DailyPoemEntry: TimelineEntry {
    let date: Date
    let poem: DailyPoemWidgetStore.Poem
    let fontName: String?
    let isEnglish: Bool
    /// Chosen by the reader from their saved poems, instead of the daily poem.
    var isPinned = false
    var background: UIImage?
    var avatar: UIImage?
}

enum WidgetPalette {
    static let paper = Color(red: 0.97, green: 0.955, blue: 0.92)
    static let ink = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let mutedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    static let cinnabar = Color(red: 0.77, green: 0.02, blue: 0.06)
}

/// The poem's ink painting under a paper wash: on the medium widget it fades
/// in from the right behind the text; elsewhere a veil keeps the verse legible.
struct DailyPoemWidgetBackground: View {
    let entry: DailyPoemEntry
    let family: WidgetFamily

    var body: some View {
        ZStack {
            WidgetPalette.paper
            if let background = entry.background {
                Image(uiImage: background)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.9)
                wash
            }
        }
    }

    @ViewBuilder
    private var wash: some View {
        switch family {
        case .systemMedium:
            LinearGradient(
                stops: [
                    .init(color: WidgetPalette.paper.opacity(0.94), location: 0),
                    .init(color: WidgetPalette.paper.opacity(0.78), location: 0.5),
                    .init(color: WidgetPalette.paper.opacity(0.1), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            LinearGradient(
                stops: [
                    .init(color: WidgetPalette.paper.opacity(0.9), location: 0),
                    .init(color: WidgetPalette.paper.opacity(0.7), location: 0.65),
                    .init(color: WidgetPalette.paper.opacity(0.35), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct DailyPoemWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: DailyPoemEntry
    /// Set by in-app previews, where there is no widget environment.
    var family: WidgetFamily?

    private var resolvedFamily: WidgetFamily { family ?? environmentFamily }
    private var poem: DailyPoemWidgetStore.Poem { entry.poem }

    private var heading: String {
        if entry.isPinned { return entry.isEnglish ? "Saved" : "我的收藏" }
        return entry.isEnglish ? "Poem of the Day" : "每日一首"
    }

    private var title: String {
        poem.englishTitle ?? poem.title
    }

    private var byline: String {
        if let englishAuthor = poem.englishAuthor { return englishAuthor }
        return "\(poem.dynasty) · \(poem.author)"
    }

    /// Lines broken at their caesura (，；) so they fit the narrow widths.
    private var phrases: [String] {
        poem.lines.flatMap { line -> [String] in
            var result: [String] = []
            var current = ""
            for character in line {
                current.append(character)
                if "，；、,".contains(character) {
                    result.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { result.append(current) }
            return result
        }
    }

    private func font(_ size: CGFloat) -> Font {
        if let fontName = entry.fontName {
            return .custom(fontName, size: size)
        }
        return .system(size: size, design: .serif)
    }

    var body: some View {
        Group {
            switch resolvedFamily {
            case .accessoryInline:
                Text(entry.isEnglish ? title : "\(poem.title) · \(poem.author)")
            case .accessoryRectangular:
                rectangular
            case .systemSmall:
                small
            case .systemLarge:
                large
            default:
                medium
            }
        }
        .widgetURL(DailyPoemWidgetStore.poemURL(id: poem.id))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(poem.title)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            ForEach(Array(phrases.prefix(2).enumerated()), id: \.offset) { _, phrase in
                Text(phrase)
                    .font(.system(size: 13, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(heading)
                .font(font(12))
                .foregroundStyle(WidgetPalette.cinnabar)
            Spacer(minLength: 4)
            // A pinned poem doesn't change with the day, so it carries no date.
            if !entry.isPinned {
                Text(entry.date, format: .dateTime.month().day())
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(WidgetPalette.mutedInk)
            }
        }
    }

    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        if let image = entry.avatar {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    private func titleBlock(avatarSize: CGFloat, titleSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            avatar(size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(font(entry.isEnglish ? titleSize - 4 : titleSize))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(entry.isEnglish ? 2 : 1)
                    .minimumScaleFactor(0.65)
                Text(byline)
                    .font(font(11))
                    .foregroundStyle(WidgetPalette.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func verse(_ lines: [String], size: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(font(size))
                    .foregroundStyle(WidgetPalette.ink.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            titleBlock(avatarSize: 30, titleSize: 17)
            Spacer(minLength: 0)
            if !entry.isEnglish {
                verse(Array(phrases.prefix(2)), size: 14, spacing: 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            titleBlock(avatarSize: 36, titleSize: 19)
            Spacer(minLength: 0)
            verse(Array(poem.lines.prefix(2)), size: 15, spacing: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            titleBlock(avatarSize: 44, titleSize: 21)
            Rectangle()
                .fill(WidgetPalette.cinnabar.opacity(0.35))
                .frame(width: 28, height: 1.5)
            let lines = poem.lines.count > 8 ? Array(poem.lines.prefix(8)) + ["……"] : poem.lines
            verse(lines, size: lines.count > 6 ? 15 : 17, spacing: lines.count > 6 ? 6 : 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
