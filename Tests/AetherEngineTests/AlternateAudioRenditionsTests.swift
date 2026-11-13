import Testing
import Foundation
@testable import AetherEngine

/// Every other audio track rides the master as an extra muxed rendition, so AVKit's own audio menu lists
/// them all. Picking one there is turned into the engine's usual reload (`selectAudioTrack`).
struct AlternateAudioRenditionsTests {

    private func provider(language: String?, alternates: [AlternateAudioRendition]) -> VideoSegmentProvider {
        VideoSegmentProvider(
            cache: SegmentCache(forwardWindow: 4, backwardWindow: 4),
            segments: [HLSVideoEngine.Segment(startPts: 0, endPts: 4000, startSeconds: 0, durationSeconds: 4)],
            codecsString: "avc1.64001f,mp4a.40.2", supplementalCodecs: nil,
            resolution: (1920, 1080), videoRange: .sdr, frameRate: 24.0, hdcpLevel: nil,
            sourceBitrate: 5_000_000,
            audioLanguage: language,
            audioChannelCount: 2,
            alternateAudioRenditions: alternates
        )
    }

    private func audioTags(_ master: String) -> [String] {
        master.split(separator: "\n").filter { $0.hasPrefix("#EXT-X-MEDIA:TYPE=AUDIO") }.map(String.init)
    }

    @Test("alternates follow the playing rendition, never auto-selected, without a URI")
    func alternatesListed() {
        let master = HLSLocalServer.buildMasterPlaylistText(provider: provider(
            language: "eng",
            alternates: [AlternateAudioRendition(streamIndex: 2, language: "spa", name: "Spanish", precedesActive: false)]))
        let tags = audioTags(master)
        #expect(tags.count == 2)
        #expect(tags[0].contains("LANGUAGE=\"eng\",DEFAULT=YES,AUTOSELECT=YES"))
        #expect(tags[1] == "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"aud\",NAME=\"Spanish\",LANGUAGE=\"spa\",DEFAULT=NO,AUTOSELECT=NO")
    }

    @Test("renditions keep the source's order, whichever track plays")
    func sourceOrder() {
        let master = HLSLocalServer.buildMasterPlaylistText(provider: provider(
            language: "spa",
            alternates: [AlternateAudioRendition(streamIndex: 1, language: "eng", name: "English", precedesActive: true),
                         AlternateAudioRendition(streamIndex: 3, language: "fra", name: "French", precedesActive: false)]))
        #expect(audioTags(master).map { $0.contains("NAME=\"English\"") ? "eng" : $0.contains("NAME=\"French\"") ? "fra" : "active" }
            == ["eng", "active", "fra"])
    }

    @Test("an untagged source keeps its master without an audio group")
    func untaggedActiveListsNothing() {
        let master = HLSLocalServer.buildMasterPlaylistText(provider: provider(
            language: nil,
            alternates: [AlternateAudioRendition(streamIndex: 2, language: "spa", name: "Spanish", precedesActive: false)]))
        #expect(audioTags(master).isEmpty)
    }

    @Test("names are unique in the group, so same-language tracks stay apart")
    func uniqueNames() {
        let tracks = [
            TrackInfo(id: 1, name: "English", codec: "aac", language: "eng", channels: 6, isDefault: false),
            TrackInfo(id: 2, name: "Commentary", codec: "aac", language: "en", channels: 2, isDefault: false),
            TrackInfo(id: 3, name: "Spanish", codec: "ac3", language: "spa", channels: 6, isDefault: false),
            TrackInfo(id: 4, name: "Track 4", codec: "aac", language: nil, channels: 2, isDefault: false),
        ]
        let list = AlternateAudioRendition.list(tracks: tracks, active: 1, activeName: "English", skipping: [3])
        #expect(list.map(\.streamIndex) == [2, 4])
        #expect(AlternateAudioRendition.list(tracks: tracks, active: 2, activeName: "Commentary", skipping: [])
            .map(\.precedesActive) == [true, false, false])
        #expect(list.map(\.language) == ["eng", nil])
        #expect(list[0].name != "English")
        #expect(Set(list.map(\.name)).count == 2)
        #expect(list[1].name == "Track 4")
    }
}
