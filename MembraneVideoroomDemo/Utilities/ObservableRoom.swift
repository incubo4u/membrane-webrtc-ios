import Foundation
import WebRTC
import SwiftUI

struct Participant {
    let id: String
    let displayName: String
    
    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

struct ParticipantVideo: Identifiable {
    let id: String
    let participant: Participant
    // TODO: this videotrack could be wrapped to limit imports of webrtc package
    // FIXME: this can change dynamically so it must be 'var' and be an observable object instead of simple struct...
    var videoTrack: RTCVideoTrack
    let isScreensharing: Bool
    let mirror: Bool
    
    init(id: String, participant: Participant, videoTrack: RTCVideoTrack, isScreensharing: Bool = false, mirror: Bool = false) {
        self.id = id
        self.participant = participant
        self.videoTrack = videoTrack
        self.isScreensharing = isScreensharing
        self.mirror = mirror
    }
}

class ObservableRoom: ObservableObject {
    weak var room: MembraneRTC?
    
    @Published var errorMessage: String?
    @Published var isMicEnabled: Bool
    @Published var isCameraEnabled: Bool
    @Published var isScreensharingEnabled: Bool
    
    var primaryVideo: ParticipantVideo?
    
    var participants: [String: Participant]
    var participantVideos: Array<ParticipantVideo>
    var localParticipantId: String?
    var localScreensharingVideoId: String?
    
    
    init(_ room: MembraneRTC) {
        self.room = room
        self.participants = [:]
        self.participantVideos = []
        
        self.isMicEnabled = true
        self.isCameraEnabled = true
        self.isScreensharingEnabled = false
        
        room.add(delegate: self)
        
        self.room?.join()
    }
    
    // TODO: this should not belong here...
    public enum LocalTrackType {
        case audio, video, screensharing
    }
    
    func toggleLocalTrack(_ type: LocalTrackType) {
        guard let room = self.room,
              let localParticipantId = self.localParticipantId,
            let localParticipant = self.participants[localParticipantId] else {
            return
        }
        
        switch type {
        case .audio:
            room.localAudioTrack?.toggle()
            self.isMicEnabled = !self.isMicEnabled
            
        case .video:
            room.localVideoTrack?.toggle()
            self.isCameraEnabled = !self.isCameraEnabled
            
        case .screensharing:
            // if screensharing is enabled it must be closed by the Broadcast Extension, not by our application
            // the only thing we can do is to display stop recording button, which we already do
            guard self.isScreensharingEnabled == false else {
                return
                
            }
            
            room.startBroadcastScreensharing(onStart: { [weak self, weak room] in
                guard let self = self,
                      let room = room,
                      let screensharingTrack = room.localScreensharingVideoTrack else {
                          
                    return
                }
                
                self.localScreensharingVideoId = screensharingTrack.rtcTrack().trackId
                
                // FIXME: somehow broadcast screensharing does not gets displayed properly, instead
                // a frozen, blank frame gets rendered
                let localParticipantScreensharing = ParticipantVideo(
                    id: self.localScreensharingVideoId!,
                    participant: localParticipant,
                    videoTrack: screensharingTrack.rtcTrack() as! RTCVideoTrack,
                    isScreensharing: true
                )
                
                self.add(video: localParticipantScreensharing)
                
                // once the screensharing has started we want to focus it
                self.focus(video: localParticipantScreensharing)
                self.isScreensharingEnabled = true
            }, onStop: { [weak self] in
                guard let self = self,
                    let localScreensharingId = self.localScreensharingVideoId,
                      let video = self.findParticipantVideo(id: localScreensharingId) else {
                    return
                }
                
                self.remove(video: video)
                self.isScreensharingEnabled = false
            })
        }
    }
    
    func focus(video: ParticipantVideo) {
        DispatchQueue.main.async {
            guard let idx = self.participantVideos.firstIndex(where: { $0.id == video.id}) else {
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
                sdkLogger.error("ObservableRoom tried to add already existing ParticipantVideo")
                return
            }
            
            if let primaryVideo = self.primaryVideo,
               primaryVideo.participant.id == self.localParticipantId {
                
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
               primaryVideo.id == video.id {
                
                if self.participantVideos.count > 0 {
                    self.primaryVideo = self.participantVideos.removeFirst()
                } else {
                    self.primaryVideo = nil
                }
                
                self.objectWillChange.send()
                
                return
            }
            
            guard let idx = self.participantVideos.firstIndex(where: { $0.id == video.id}) else {
                return
            }
            
            self.participantVideos.remove(at: idx)
            
            self.objectWillChange.send()
        }
    }
    
    func findParticipantVideo(id: String) -> ParticipantVideo? {
        if let primaryVideo = self.primaryVideo,
           primaryVideo.id == id {
            return primaryVideo
        }
        
        return self.participantVideos.first(where: { $0.id == id })
    }
}

extension ObservableRoom: MembraneRTCDelegate {
    func onConnected() {
    }
    
    func onJoinSuccess(peerID: String, peersInRoom: Array<Peer>) {
        guard let room = self.room else {
            return
        }
        
        self.localParticipantId = peerID
        
        let localParticipant = Participant(id: peerID, displayName: "Me")
        
        let participants = peersInRoom.map { peer in
            Participant(id: peer.id, displayName: peer.metadata["displayName"] ?? "")
        }
        
        DispatchQueue.main.async {
            guard let track = room.localVideoTrack?.track else {
                fatalError("failed to setup local video")
            }
            
            self.primaryVideo = ParticipantVideo(id: track.trackId, participant: localParticipant, videoTrack: track, mirror: true)
            self.participants[localParticipant.id] = localParticipant
            participants.forEach { participant in self.participants[participant.id] = participant }
            
            self.objectWillChange.send()
        }
    }
    
    func onJoinError(metadata: Any) {
        self.errorMessage = "Failed to join a room"
    }
    
    func onTrackReady(ctx: TrackContext) {
        guard let participant = self.participants[ctx.peer.id],
            let videoTrack = ctx.track as? RTCVideoTrack else {
            return
        }
        
        // there can be a situation where we simply need to replace `videoTrack` for
        // already existing video, happens when dynamically adding new local track
        // TODO: Consider making each participant an observable object so that we don't have to refresh anything else
        // TODO: refactor me here mate
        if let idx = self.participantVideos.firstIndex(where: { $0.id == ctx.trackId }) {
            guard let videoTrack = ctx.track as? RTCVideoTrack else {
                return
            }
            
            var participantVideo = self.participantVideos[idx]
            participantVideo.videoTrack = videoTrack
            self.participantVideos[idx] = participantVideo
            
            // signal that participant video track has been changed
            // TODO: this needs to be signalling the track change
            // this is just a temporary fix
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
            
            return
        }
        
        // track is seen for the first time so initialize the participant's video
        let isScreensharing = ctx.metadata["type"] == "screensharing"
        let video = ParticipantVideo(id: ctx.trackId, participant: participant, videoTrack: videoTrack, isScreensharing: isScreensharing)
        
        self.add(video: video)
        
        if isScreensharing {
            self.focus(video: video)
        }
    }
    
    func onTrackAdded(ctx: TrackContext) { }
    
    func onTrackRemoved(ctx: TrackContext) {
        if let primaryVideo = self.primaryVideo,
           primaryVideo.id == ctx.trackId {
            self.remove(video: primaryVideo)
            
            return
        }
        
        if let video = self.participantVideos.first(where: { $0.id == ctx.trackId }) {
            self.remove(video: video)
        }
    }
    
    func onTrackUpdated(ctx: TrackContext) { }
    
    func onPeerJoined(peer: Peer) {
        self.participants[peer.id] = Participant(id: peer.id, displayName: peer.metadata["displayName"] ?? "")
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func onPeerLeft(peer: Peer) {
        DispatchQueue.main.async {
            self.participants.removeValue(forKey: peer.id)
            self.objectWillChange.send()
        }
    }
    
    func onPeerUpdated(peer: Peer) { }
    
    func onConnectionError(message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
        }
    }
}
