import Foundation

/// Another audio track of the source, declared in the master next to the playing one so AVKit's own audio
/// menu lists every track. The audio is still muxed into the one variant, so the rendition carries no URI
/// and is never auto-selected (`AUTOSELECT=YES` on a second URI-less rendition stalls AVPlayer at start,
/// measured on macOS 27). Picking it in AVKit switches the track through `selectAudioTrack`, which
/// reloads with it as the muxed audio (`AetherEngine.followAudibleSelection`).
struct AlternateAudioRendition: Equatable, Sendable {
    /// FFmpeg AVStream index, the `TrackInfo.id` that `selectAudioTrack(index:)` takes.
    let streamIndex: Int
    /// ISO 639-2/T, like the playing rendition's.
    let language: String?
    /// Unique in the group: AVKit labels the option from LANGUAGE, the engine maps a pick back by NAME.
    let name: String
    /// Comes before the playing track in the source, so the menu keeps the source's order across switches.
    let precedesActive: Bool

    /// The NAME a rendition in that language gets; the playing one uses the same.
    static func name(language: String) -> String {
        Locale.current.localizedString(forIdentifier: language) ?? language
    }

    /// Every audio track but the playing one and the ones the engine can't serve, named apart from
    /// `activeName` and each other.
    static func list(tracks: [TrackInfo], active: Int, activeName: String, skipping: Set<Int>) -> [Self] {
        var used: Set<String> = [activeName]
        let activePosition = tracks.firstIndex { $0.id == active } ?? tracks.endIndex
        return tracks.enumerated().filter { $0.element.id != active && !skipping.contains($0.element.id) }
            .map { position, track in
                let language = AudioLanguageMap.iso639_2T(forSourceLanguage: track.language)
                let base = (language.map(name(language:)) ?? (track.name.isEmpty ? "Track \(track.id)" : track.name))
                    .replacingOccurrences(of: "\"", with: "'")
                var unique = base
                var n = 2
                while used.contains(unique) { unique = "\(base) \(n)"; n += 1 }
                used.insert(unique)
                return Self(streamIndex: track.id, language: language, name: unique,
                            precedesActive: position < activePosition)
            }
    }
}
