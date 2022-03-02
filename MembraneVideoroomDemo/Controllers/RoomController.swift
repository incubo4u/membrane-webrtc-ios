import MembraneRTC
import SwiftUI

struct Participant {
    let id: String
    let displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

class ParticipantVideo: Identifiable, ObservableObject {
    let id: String
    let participant: Participant
    let isScreensharing: Bool

    @Published var videoTrack: VideoTrack
    @Published var mirror: Bool

    init(id: String, participant: Participant, videoTrack: VideoTrack, isScreensharing: Bool = false, mirror: Bool = false) {
        self.id = id
        self.participant = participant
        self.videoTrack = videoTrack
        self.isScreensharing = isScreensharing
        self.mirror = mirror
    }
}

class RoomController: ObservableObject {
    weak var room: MembraneRTC?
    
    var localVideoTrack: LocalVideoTrack?
    var localAudioTrack: LocalAudioTrack?
    var localScreencastTrack: LocalBroadcastScreenTrack?

    @Published var errorMessage: String?
    @Published var isMicEnabled: Bool
    @Published var isCameraEnabled: Bool
    @Published var isScreensharingEnabled: Bool

    var primaryVideo: ParticipantVideo?

    var participants: [String: Participant]
    var participantVideos: [ParticipantVideo]
    var localParticipantId: String?
    var localScreensharingVideoId: String?
    var isFrontCamera: Bool = true
    

    init(_ room: MembraneRTC) {
        self.room = room
        participants = [:]
        participantVideos = []

        isMicEnabled = true
        isCameraEnabled = true
        isScreensharingEnabled = false
        
        let localPeer = room.currentPeer()
        let trackMetadata = ["user_id": localPeer.metadata["displayName"] ?? "UNKNOWN"]
        
        let preset = VideoParameters.presetVGA169
        let videoParameters = VideoParameters(dimensions: preset.dimensions.flip(), encoding: preset.encoding)
        
        localVideoTrack = room.createVideoTrack(videoParameters: videoParameters, metadata: trackMetadata)
        localAudioTrack = room.createAudioTrack(metadata: trackMetadata)

        room.add(delegate: self)
        
        

        self.room?.join()
    }

    func enableTrack(_ type: LocalTrackType, enabled: Bool) {
        switch type {
        case .video:
            if let track = localVideoTrack, track.enabled() != enabled {
                track.setEnabled(enabled)
            }

            isCameraEnabled = enabled
        case .audio:
            if let track = localAudioTrack, track.enabled() != enabled {
                track.setEnabled(enabled)
            }

            isMicEnabled = enabled
        default:
            break
        }
    }

    func switchCameraPosition() {
        guard let cameraTrack = localVideoTrack as? LocalCameraVideoTrack else {
            return
        }

        cameraTrack.switchCamera()
        isFrontCamera = !isFrontCamera
        
        guard let id = localParticipantId,
              let localVideo = findParticipantVideo(id: id) else {
                  return
        }
        
        let localIsFrontCamera = isFrontCamera
        // HACK: there is a delay when we set the mirror and the camer actually switches
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            localVideo.mirror = localIsFrontCamera
        }
    }

    func toggleLocalTrack(_ type: LocalTrackType) {
        guard let room = room,
              let localParticipantId = localParticipantId,
              let localParticipant = participants[localParticipantId]
        else {
            return
        }

        switch type {
        case .audio:
            isMicEnabled = !isMicEnabled
            localAudioTrack?.setEnabled(isMicEnabled)

        case .video:
            isCameraEnabled = !isCameraEnabled
            localVideoTrack?.setEnabled(isCameraEnabled)

        case .screensharing:
            // if screensharing is enabled it must be closed by the Broadcast Extension, not by our application
            // the only thing we can do is to display stop recording button, which we already do
            guard isScreensharingEnabled == false else {
                return
            }
            
            let displayName = room.currentPeer().metadata["displayName"] ?? "UNKNOWN"
            
            let preset = VideoParameters.presetScreenShareHD15
            let videoParameters = VideoParameters(dimensions: preset.dimensions.flip(), encoding: preset.encoding)
            
            room.createScreencastTrack(videoParameters: videoParameters, metadata: ["user_id": displayName, "type": "screensharing"], onStart: { [weak self] screencastTrack in
                guard let self = self else {
                    return
                }

                self.localScreensharingVideoId = UUID().uuidString

                let localParticipantScreensharing = ParticipantVideo(
                    id: self.localScreensharingVideoId!,
                    participant: localParticipant,
                    videoTrack: screencastTrack,
                    isScreensharing: true
                )

                self.add(video: localParticipantScreensharing)

                // once the screensharing has started we want to focus it
                self.focus(video: localParticipantScreensharing)
                self.isScreensharingEnabled = true
            }, onStop: { [weak self] in
                guard let self = self,
                      let localScreensharingId = self.localScreensharingVideoId,
                      let video = self.findParticipantVideo(id: localScreensharingId)
                else {
                    return
                }

                self.remove(video: video)
                self.isScreensharingEnabled = false
            })
        }
    }

    func focus(video: ParticipantVideo) {
        DispatchQueue.main.async {
            guard let idx = self.participantVideos.firstIndex(where: { $0.id == video.id }) else {
                return
            }

            self.participantVideos.remove(at: idx)

            // decide where to put current primary video (if one is set)
            if let primary = self.primaryVideo {
                // if either new video or old primary are local videos then we can insert at the beginning
                if video.participant.id == self.localParticipantId || primary.participant.id == self.localParticipantId {
                    self.participantVideos.insert(primary, at: 0)
                } else {
                    let index = self.participantVideos.count > 0 ? 1 : 0
                    self.participantVideos.insert(primary, at: index)
                }
            }

            // set the current primary video
            self.primaryVideo = video

            self.objectWillChange.send()
        }
    }

    // in case of local video being a primary one then sets the new video
    // as a primary and moves local video to regular participant videos
    //
    // otherwise simply appends to participant videos
    func add(video: ParticipantVideo) {
        DispatchQueue.main.async {
            guard self.findParticipantVideo(id: video.id) == nil else {
                print("RoomController tried to add already existing ParticipantVideo")
                return
            }

            if let primaryVideo = self.primaryVideo,
               primaryVideo.participant.id == self.localParticipantId
            {
                self.participantVideos.insert(primaryVideo, at: 0)
                self.primaryVideo = video

                self.objectWillChange.send()

                return
            }

            self.participantVideos.append(video)

            self.objectWillChange.send()
        }
    }

    func remove(video: ParticipantVideo) {
        DispatchQueue.main.async {
            if let primaryVideo = self.primaryVideo,
               primaryVideo.id == video.id
            {
                if self.participantVideos.count > 0 {
                    self.primaryVideo = self.participantVideos.removeFirst()
                } else {
                    self.primaryVideo = nil
                }

                self.objectWillChange.send()

                return
            }

            guard let idx = self.participantVideos.firstIndex(where: { $0.id == video.id }) else {
                return
            }

            self.participantVideos.remove(at: idx)

            self.objectWillChange.send()
        }
    }

    func findParticipantVideo(id: String) -> ParticipantVideo? {
        if let primaryVideo = primaryVideo,
           primaryVideo.id == id
        {
            return primaryVideo
        }

        return participantVideos.first(where: { $0.id == id })
    }
}

extension RoomController: MembraneRTCDelegate {
    func onConnected() {}

    func onJoinSuccess(peerID: String, peersInRoom: [Peer]) {
        localParticipantId = peerID

        let localParticipant = Participant(id: peerID, displayName: "Me")

        let participants = peersInRoom.map { peer in
            Participant(id: peer.id, displayName: peer.metadata["displayName"] ?? "")
        }

        DispatchQueue.main.async {
            guard let videoTrack = self.localVideoTrack else {
                fatalError("failed to setup local video")
            }

            self.primaryVideo = ParticipantVideo(id: localParticipant.id, participant: localParticipant, videoTrack: videoTrack, mirror: self.isFrontCamera)
            self.participants[localParticipant.id] = localParticipant
            participants.forEach { participant in self.participants[participant.id] = participant }

            self.objectWillChange.send()
        }
    }

    func onJoinError(metadata _: Any) {
        errorMessage = "Failed to join a room"
    }

    func onTrackReady(ctx: TrackContext) {
        guard let participant = participants[ctx.peer.id],
              let videoTrack = ctx.track as? VideoTrack
        else {
            return
        }

        // there can be a situation where we simply need to replace `videoTrack` for
        // already existing video, happens when dynamically adding new local track
        if let participantVideo = participantVideos.first(where: { $0.id == ctx.trackId }) {
            DispatchQueue.main.async {
                participantVideo.videoTrack = videoTrack
            }

            return
        }

        // track is seen for the first time so initialize the participant's video
        let isScreensharing = ctx.metadata["type"] == "screensharing"
        let video = ParticipantVideo(id: ctx.trackId, participant: participant, videoTrack: videoTrack, isScreensharing: isScreensharing)

        add(video: video)

        if isScreensharing {
            focus(video: video)
        }
    }

    func onTrackAdded(ctx _: TrackContext) {}

    func onTrackRemoved(ctx: TrackContext) {
        if let primaryVideo = primaryVideo,
           primaryVideo.id == ctx.trackId
        {
            remove(video: primaryVideo)

            return
        }

        if let video = participantVideos.first(where: { $0.id == ctx.trackId }) {
            remove(video: video)
        }
    }

    func onTrackUpdated(ctx _: TrackContext) {}

    func onPeerJoined(peer: Peer) {
        participants[peer.id] = Participant(id: peer.id, displayName: peer.metadata["displayName"] ?? "")
    }

    func onPeerLeft(peer: Peer) {
        participants.removeValue(forKey: peer.id)
    }

    func onPeerUpdated(peer _: Peer) {}

    func onError(_ error: MembraneRTCError) {
        DispatchQueue.main.async {
            switch error {
            case let .rtc(message):
                self.errorMessage = message

            case let .transport(message):
                self.errorMessage = message

            case let .unknown(message):
                self.errorMessage = message
            }
        }
    }
}
