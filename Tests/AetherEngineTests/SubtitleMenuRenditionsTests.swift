import Testing
import Foundation
@testable import AetherEngine

/// With `LoadOptions.subtitleMenuEntries`, every subtitle track and every host entry rides the master as a
/// SUBTITLES rendition whose WebVTT is blank, so AVKit's own Subtitles menu lists them while the host keeps
/// drawing the cues. A pick there is mapped back to the track or entry (`AetherEngine.followLegibleSelection`).
struct SubtitleMenuRenditionsTests {

    private func provider(_ renditions: [SubtitleMenuRendition]) -> VideoSegmentProvider {
        VideoSegmentProvider(
            cache: SegmentCache(forwardWindow: 4, backwardWindow: 4),
            segments: [HLSVideoEngine.Segment(startPts: 0, endPts: 4000, startSeconds: 0, durationSeconds: 4),
                       HLSVideoEngine.Segment(startPts: 4000, endPts: 6000, startSeconds: 4, durationSeconds: 2)],
            codecsString: "avc1.64001f,mp4a.40.2", supplementalCodecs: nil,
            resolution: (1920, 1080), videoRange: .sdr, frameRate: 24.0, hdcpLevel: nil,
            sourceBitrate: 5_000_000,
            subtitleMenuRenditions: renditions
        )
    }

    private func track(_ id: Int, _ language: String?, name: String = "", codec: String = "subrip") -> TrackInfo {
        TrackInfo(id: id, name: name, codec: codec, language: language, isDefault: false)
    }

    @Test("tracks then entries, unique names, every one blank and never auto-selected")
    func listed() {
        let list = SubtitleMenuRendition.list(
            tracks: [track(3, "eng"), track(4, "eng", name: "SDH", codec: "pgssub"), track(5, nil)],
            entries: [SubtitleMenuEntry(name: "Japanese (OpenSubtitles)", language: "ja")])
        #expect(list.map(\.target) == [.track(3), .track(4), .track(5), .entry(0)])
        #expect(list.map(\.language) == ["eng", "eng", nil, "ja"])
        #expect(Set(list.map(\.name)).count == 4)
        #expect(list[1].name.contains("SDH"))

        let master = HLSLocalServer.buildMasterPlaylistText(provider: provider(list))
        let tags = master.split(separator: "\n").filter { $0.hasPrefix("#EXT-X-MEDIA:TYPE=SUBTITLES") }
        #expect(tags.count == 4)
        #expect(tags.allSatisfy { $0.contains("DEFAULT=NO,AUTOSELECT=NO") })
        #expect(tags[3] == "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"Japanese (OpenSubtitles)\",LANGUAGE=\"ja\",DEFAULT=NO,AUTOSELECT=NO,URI=\"menu_3.m3u8\"")
        #expect(master.contains("SUBTITLES=\"subs\""))
    }

    @Test("closed captions stay out: they have no packets to stand for")
    func skipsClosedCaptions() {
        let list = SubtitleMenuRendition.list(tracks: [track(1, "eng", codec: "eia_608")], entries: [])
        #expect(list.isEmpty)
    }

    @Test("a blank playlist spans the whole program")
    func blankPlaylist() {
        let playlist = HLSLocalServer.buildBlankSubtitlePlaylistText(provider: provider([]))
        #expect(playlist.contains("#EXTINF:6.000"))
        #expect(playlist.contains("menu_blank.vtt"))
        #expect(playlist.contains("#EXT-X-ENDLIST"))
    }

    @Test("an entry in a language a track already has stays out, keeping its index")
    func entryBehindATrack() {
        let list = SubtitleMenuRendition.list(
            tracks: [track(3, "por")],
            entries: [SubtitleMenuEntry(name: "Português", language: "pt-BR"), SubtitleMenuEntry(name: "日本語", language: "ja")])
        #expect(list.map(\.target) == [.track(3), .entry(1)])
    }

    @Test("a name picked in AVKit maps back to its target")
    func target() {
        let p = provider(SubtitleMenuRendition.list(tracks: [track(3, "spa")],
                                                    entries: [SubtitleMenuEntry(name: "French (OpenSubtitles)", language: "fr")]))
        #expect(p.subtitleMenuTarget(renditionName: "French (OpenSubtitles)") == .entry(0))
        #expect(p.subtitleMenuTarget(renditionName: p.masterSubtitleMenuRenditions[0].name) == .track(3))
        #expect(p.subtitleMenuTarget(renditionName: "German") == nil)
    }
}
