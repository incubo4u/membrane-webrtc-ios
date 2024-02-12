import WebRTC

// a utility protocol that allows to hide WebRTCMembraneFramework internals from the package's user
// and still alowing the `MembraneRTC` to operate on WebRTCMembraneFramework structures
internal protocol MediaTrackProvider {
    func rtcTrack() -> RTCMediaStreamTrack
}
