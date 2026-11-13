import Foundation

/// A host's own entry in AVKit's Subtitles menu, next to the file's tracks: something the host fetches
/// when picked (like a downloaded subtitle). See `LoadOptions.subtitleMenuEntries`.
public struct SubtitleMenuEntry: Equatable, Sendable {
    /// The option's name in AVKit's menu. Unique among the entries.
    public var name: String
    /// BCP 47 or ISO 639, like "es" or "pt-BR".
    public var language: String?

    public init(name: String, language: String?) {
        self.name = name
        self.language = language
    }
}

/// One option in AVKit's Subtitles menu, as `followLegibleSelection` reports a pick.
public enum SubtitleMenuPick: Equatable, Sendable {
    /// A subtitle track, by `TrackInfo.id`; the engine has already selected it.
    case track(Int)
    /// A host entry, by its index in `LoadOptions.subtitleMenuEntries`.
    case entry(Int)
}

/// A SUBTITLES rendition the master declares only so AVKit's menu lists it. Its WebVTT is blank: the host
/// draws the cues itself, so AVKit renders nothing and its style choices never fight the host's overlay.
struct SubtitleMenuRendition: Equatable, Sendable {
    let target: SubtitleMenuPick
    /// Unique in the group: AVFoundation collapses same-named options, and a pick maps back by NAME.
    let name: String
    let language: String?

    /// Every text and image track (not in-band closed captions), then each host entry in a language no
    /// track has: AVKit labels an option by its language, so a second same-language option reads the same.
    static func list(tracks: [TrackInfo], entries: [SubtitleMenuEntry]) -> [Self] {
        var used: Set<String> = []
        func unique(_ base: String) -> String {
            var name = base.replacingOccurrences(of: "\"", with: "'")
            let stem = name
            var n = 2
            while used.contains(name) { name = "\(stem) \(n)"; n += 1 }
            used.insert(name)
            return name
        }
        let fromTracks = tracks.filter { !AetherEngine.isEmbeddedClosedCaptionCodec($0.codec) }.map { track in
            let language = track.language.flatMap { Locale.current.localizedString(forIdentifier: $0) }
            let base = switch (language, track.name.isEmpty) {
            case (let language?, true): language
            case (let language?, false) where track.name.localizedCaseInsensitiveContains(language): track.name
            case (let language?, false): "\(language) (\(track.name))"
            case (nil, false): track.name
            case (nil, true): "Track \(track.id)"
            }
            return Self(target: .track(track.id), name: unique(base), language: track.language)
        }
        let listed = tracks.filter { !AetherEngine.isEmbeddedClosedCaptionCodec($0.codec) }.map(\.language)
        return fromTracks + entries.enumerated().filter { _, entry in
            entry.language.map { language in !listed.contains { AetherEngine.languageMatches($0, language) } } ?? true
        }.map { index, entry in
            Self(target: .entry(index), name: unique(entry.name), language: entry.language)
        }
    }
}
