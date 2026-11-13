import AVFoundation
import Foundation

extension AetherEngine {

    /// True when AVKit's own audio menu lists every audio track (the master carries the alternates),
    /// so a host needs no track menu of its own on the native route.
    public var nativeAudioRenditionsServed: Bool {
        guard let session = nativeVideoSession, session.servingMasterPlaylist else { return false }
        return !(session.provider?.masterAlternateAudioRenditions.isEmpty ?? true)
    }

    /// Follows AVKit's audio menu: a pick there lands on a URI-less alternate rendition, which AVPlayer
    /// can't play by itself, so the engine switches to that track with its usual reload.
    func observeAudibleSelection() {
        audibleSelectionObservation.map(NotificationCenter.default.removeObserver)
        audibleSelectionObservation = nil
        guard let item = currentAVPlayerItem else { return }
        audibleSelectionObservation = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.followAudibleSelection(of: item) }
        }
    }

    private func followAudibleSelection(of item: AVPlayerItem) async {
        guard let provider = nativeVideoSession?.provider,
              !provider.masterAlternateAudioRenditions.isEmpty,
              let group = try? await item.asset.loadMediaSelectionGroup(for: .audible),
              let option = item.currentMediaSelection.selectedMediaOption(in: group),
              let title = try? await AVMetadataItem.metadataItems(
                  from: option.commonMetadata, filteredByIdentifier: .commonIdentifierTitle
              ).first?.load(.stringValue),
              currentAVPlayerItem === item,
              let index = provider.audioStreamIndex(renditionName: title, active: activeAudioTrackIndex),
              index != activeAudioTrackIndex
        else { return }
        EngineLog.emit("[AetherEngine] AVKit picked audio rendition \"\(title)\": switching to stream \(index)",
                       category: .engine)
        selectAudioTrack(index: index)
    }
}
