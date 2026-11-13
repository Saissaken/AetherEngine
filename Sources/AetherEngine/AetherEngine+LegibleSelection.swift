import AVFoundation
import Foundation

extension AetherEngine {

    /// True when AVKit's own Subtitles menu lists the subtitle tracks and the host's entries
    /// (`LoadOptions.subtitleMenuEntries`), so a host needs no subtitle button of its own on this route.
    public var subtitleMenuRenditionsServed: Bool {
        guard let session = nativeVideoSession, session.servingMasterPlaylist else { return false }
        return !(session.provider?.masterSubtitleMenuRenditions.isEmpty ?? true)
    }

    /// Shows the host's own choice in AVKit's Subtitles menu: a track, an entry, or Off (nil). Picking
    /// it there again changes nothing, so the menu and the host never disagree.
    public func reflectSubtitleMenu(_ pick: SubtitleMenuPick?) {
        lastSubtitleMenuPick = pick
        guard let provider = nativeVideoSession?.provider, !provider.masterSubtitleMenuRenditions.isEmpty,
              let item = currentAVPlayerItem else { return }
        Task { @MainActor in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            let name = pick.flatMap { pick in provider.masterSubtitleMenuRenditions.first { $0.target == pick }?.name }
            var option: AVMediaSelectionOption?
            if let name {
                for candidate in group.options where await Self.renditionName(of: candidate) == name { option = candidate }
            }
            guard currentAVPlayerItem === item,
                  item.currentMediaSelection.selectedMediaOption(in: group) != option else { return }
            item.select(option, in: group)
        }
    }

    /// Follows AVKit's Subtitles menu: a track turns on in the host's overlay, Off clears it, and an
    /// entry goes to the host on `subtitleMenuPicks`.
    func observeLegibleSelection() {
        legibleSelectionObservation.map(NotificationCenter.default.removeObserver)
        legibleSelectionObservation = nil
        guard let item = currentAVPlayerItem else { return }
        // Only the user's picks count: no automatic selection from the system's caption criteria.
        if nativeVideoSession?.provider?.masterSubtitleMenuRenditions.isEmpty == false {
            currentAVPlayer?.appliesMediaSelectionCriteriaAutomatically = false
        }
        legibleSelectionObservation = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.followLegibleSelection(of: item) }
            }
        }
        // A new item (an audio switch reloads) starts with nothing selected: show the last pick again.
        reflectSubtitleMenu(lastSubtitleMenuPick)
    }

    private func followLegibleSelection(of item: AVPlayerItem) async {
        guard let provider = nativeVideoSession?.provider, !provider.masterSubtitleMenuRenditions.isEmpty,
              let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
        // Also fired by audio picks and by our own reflect: act only on a change.
        let option = item.currentMediaSelection.selectedMediaOption(in: group)
        let pick: SubtitleMenuPick?
        if let option {
            guard let name = await Self.renditionName(of: option),
                  let target = provider.subtitleMenuTarget(renditionName: name) else { return }
            pick = target
        } else {
            pick = nil
        }
        guard currentAVPlayerItem === item, pick != lastSubtitleMenuPick else { return }
        lastSubtitleMenuPick = pick
        EngineLog.emit("[AetherEngine] AVKit subtitle menu pick: \(String(describing: pick))", category: .engine)
        switch pick {
        case .track(let id): if activeSubtitleTrackIndex != id { selectSubtitleTrack(index: id) }
        case nil: if activeSubtitleTrackIndex != nil { clearSubtitle() }
        case .entry: break
        }
        subtitleMenuPicks.send(pick)
    }

    /// An HLS option's NAME, which AVFoundation keeps as its title.
    static func renditionName(of option: AVMediaSelectionOption) async -> String? {
        try? await AVMetadataItem.metadataItems(from: option.commonMetadata, filteredByIdentifier: .commonIdentifierTitle)
            .first?.load(.stringValue)
    }
}
