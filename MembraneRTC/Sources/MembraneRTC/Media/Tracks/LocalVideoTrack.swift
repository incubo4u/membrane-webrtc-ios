import WebRTC

/// Utility wrapper around a local `RTCVideoTrack` also managing an instance of `VideoCapturer`
public class LocalVideoTrack: VideoTrack, LocalTrack {
    private let videoSource: RTCVideoSource
    internal var capturer: VideoCapturer?
    private let track: RTCVideoTrack

    public enum Capturer {
        case camera, file
    }

    override internal init() {
        let source = ConnectionManager.createVideoSource()

        videoSource = source
        track = ConnectionManager.createVideoTrack(source: source)

        super.init()

        capturer = createCapturer(videoSource: source)
    }

    public static func create(for capturer: Capturer) -> LocalVideoTrack {
        switch capturer {
        case .camera:
            return LocalCameraVideoTrack()
        case .file:
            return LocalFileVideoTrack()
        }
    }

    internal func createCapturer(videoSource _: RTCVideoSource) -> VideoCapturer {
        fatalError("Basic LocalVideoTrack does not provide a default capturer")
    }

    public func start() {
        capturer?.startCapture()
    }

    public func stop() {
        capturer?.stopCapture()
    }

    public func toggle() {
        track.isEnabled = !track.isEnabled
    }

    public func enabled() -> Bool {
        return track.isEnabled
    }

    override func rtcTrack() -> RTCMediaStreamTrack {
        return track
    }
}

public class LocalCameraVideoTrack: LocalVideoTrack {
    override internal func createCapturer(videoSource: RTCVideoSource) -> VideoCapturer {
        return CameraCapturer(videoSource)
    }

    public func switchCamera() {
        guard let capturer = capturer as? CameraCapturer else {
            return
        }

        capturer.switchCamera()
    }
}

public class LocalFileVideoTrack: LocalVideoTrack {
    override internal func createCapturer(videoSource: RTCVideoSource) -> VideoCapturer {
        return FileCapturer(videoSource)
    }
}
