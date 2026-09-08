//
//  ScreenRecorder.swift
//  Wyler
//
//  Created by Cesar Vargas on 10.04.20.
//  Copyright © 2020 Cesar Vargas. All rights reserved.
//

import AVFoundation
import Foundation
import Photos
import ReplayKit
import UIKit

public enum ScreenRecorderError: Error {
    case notAvailable
    case photoLibraryAccessNotGranted
    case captureAlreadyPending
    case captureInterrupted
}

public enum VideoContainerFormat {
    case mp4
    case mov

    var fileType: AVFileType {
        switch self {
        case .mp4:
            return .mp4
        case .mov:
            return .mov
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4:
            return "mp4"
        case .mov:
            return "mov"
        }
    }

    static func from(_ value: String?) -> VideoContainerFormat {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mov", "video/quicktime", "quicktime":
            return .mov
        default:
            return .mp4
        }
    }
}

public final class ScreenRecorder: NSObject {
    private var videoOutputURL: URL?
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var micAudioWriterInput: AVAssetWriterInput?
    private var appAudioWriterInput: AVAssetWriterInput?
    private var saveToCameraRoll = false
    private var recordAudio = false
    private var videoFormat: VideoContainerFormat = .mp4
    let recorder = RPScreenRecorder.shared()
    /// Notified when the recording ends without `stoprecording()` being
    /// involved — the system stopped the capture (interruption, error).
    public var onExternalStop: ((URL?, Error?) -> Void)?
    private var isRecording = false
    private var stopRequested = false
    private var pendingStartHandler: ((Error?) -> Void)?
    private var videoWritingStarted = false

    public func startRecording(to outputURL: URL? = nil,
                               size: CGSize? = nil,
                               saveToCameraRoll: Bool = false,
                               recordAudio: Bool = false,
                               videoFormat: VideoContainerFormat = .mp4,
                               handler: @escaping (Error?) -> Void) {
        // Reject before any writer/session state is touched: a second start
        // while the first is still pending must not disturb the first capture.
        guard pendingStartHandler == nil else {
            return handler(ScreenRecorderError.captureAlreadyPending)
        }
        self.saveToCameraRoll = saveToCameraRoll
        self.recordAudio = recordAudio
        self.videoFormat = videoFormat
        resetWriterState()
        stopRequested = false
        recorder.delegate = self

        recorder.isMicrophoneEnabled = recordAudio

        do {
            if recordAudio {
                try configureAudioSession()
            }
            try createVideoWriter(in: outputURL)
            addVideoWriterInput(size: size)
            if recordAudio {
                self.micAudioWriterInput = createAndAddAudioInput()
                self.appAudioWriterInput = createAndAddAudioInput()
            }
            startCapture(handler: handler)
        } catch let err {
            handler(err)
        }
    }

    private func resetWriterState() {
        videoWriter = nil
        videoWriterInput = nil
        micAudioWriterInput = nil
        appAudioWriterInput = nil
        videoWritingStarted = false
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
    }

    private func createVideoWriter(in outputURL: URL? = nil) throws {
        let newVideoOutputURL: URL

        if let passedVideoOutput = outputURL {
            self.videoOutputURL = passedVideoOutput
            newVideoOutputURL = passedVideoOutput
        } else {
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
            let fileName = "WylerNewVideo.\(videoFormat.fileExtension)"
            newVideoOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent(fileName))
            self.videoOutputURL = newVideoOutputURL
        }

        do {
            try FileManager.default.removeItem(at: newVideoOutputURL)
        } catch {}

        do {
            try videoWriter = AVAssetWriter(outputURL: newVideoOutputURL, fileType: videoFormat.fileType)
        } catch let writerError as NSError {
            videoWriter = nil
            throw writerError
        }
    }

    private func addVideoWriterInput(size: CGSize?) {
        let passingSize: CGSize = size ?? UIScreen.main.bounds.size

        let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                            AVVideoWidthKey: passingSize.width,
                                            AVVideoHeightKey: passingSize.height]

        let newVideoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        self.videoWriterInput = newVideoWriterInput
        newVideoWriterInput.expectsMediaDataInRealTime = true
        videoWriter?.add(newVideoWriterInput)
    }

    private func createAndAddAudioInput() -> AVAssetWriterInput {
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        audioInput.expectsMediaDataInRealTime = true
        videoWriter?.add(audioInput)
        return audioInput
    }

    private func startCapture(handler: @escaping (Error?) -> Void) {
        guard recorder.isAvailable else {
            return handler(ScreenRecorderError.notAvailable)
        }
        isRecording = true
        // The start is settled exactly once — by the first sample, a capture
        // failure, the delegate, or stoprecording() — whichever comes first,
        // so the plugin's start promise never hangs and never settles twice.
        pendingStartHandler = handler
        recorder.startCapture(handler: { [weak self] (sampleBuffer, sampleType, passedError) in
            guard let self = self else { return }
            if let passedError = passedError {
                // Fails a still-pending start; once the start is settled the
                // delegate owns the end-of-capture reporting.
                if !self.settlePendingStart(passedError) {
                    self.handleRecordingEndedExternally(error: passedError)
                }
                return
            }

            switch sampleType {
            case .video:
                self.handleSampleBuffer(sampleBuffer: sampleBuffer)
                self.settlePendingStart(nil)
            case .audioApp:
                if self.recordAudio {
                    self.add(sample: sampleBuffer, to: self.appAudioWriterInput)
                }
            case .audioMic:
                if self.recordAudio {
                    self.add(sample: sampleBuffer, to: self.micAudioWriterInput)
                }
            default:
                break
            }
        })
    }

    /// Settles the pending start exactly once. Returns true when this call
    /// settled it. A failure also clears `isRecording`, because the capture
    /// never produced output; once settled, end-of-capture reporting belongs
    /// to the delegate / stoprecording().
    @discardableResult
    private func settlePendingStart(_ error: Error?) -> Bool {
        guard let startHandler = pendingStartHandler else {
            return false
        }
        pendingStartHandler = nil
        if error != nil {
            isRecording = false
        }
        startHandler(error)
        return true
    }

    private func handleSampleBuffer(sampleBuffer: CMSampleBuffer) {
        if self.videoWriter?.status == AVAssetWriter.Status.unknown {
            self.videoWriter?.startWriting()
            self.videoWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        if self.videoWriter?.status == AVAssetWriter.Status.writing {
            videoWritingStarted = true
            if self.videoWriterInput?.isReadyForMoreMediaData == true {
                self.videoWriterInput?.append(sampleBuffer)
            }
        }
    }

    private func add(sample: CMSampleBuffer, to writerInput: AVAssetWriterInput?) {
        guard let writerInput = writerInput else { return }
        guard self.videoWriter?.status == .writing else { return }
        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sample)
        }
    }

    public func stoprecording(handler: @escaping (Error?) -> Void) {
        stopRequested = true
        let outputURL = videoOutputURL
        let hadVideoContent = videoWritingStarted
        recorder.stopCapture(handler: { error in
            if let error = error {
                self.settlePendingStart(error)
                handler(error)
                return
            }

            self.isRecording = false
            // stop() may arrive before the first sample: settle the pending
            // start so the caller's start promise does not hang.
            self.settlePendingStart(ScreenRecorderError.captureInterrupted)
            self.finishWriterAndDeliver(
                outputURL: outputURL,
                hasVideoContent: hadVideoContent,
                handler: handler
            )
        })
    }

    private func finishWriterAndDeliver(
        outputURL: URL?,
        hasVideoContent: Bool,
        handler: @escaping (Error?) -> Void
    ) {
        videoWriterInput?.markAsFinished()
        micAudioWriterInput?.markAsFinished()
        appAudioWriterInput?.markAsFinished()

        guard let writer = videoWriter else {
            handler(nil)
            return
        }

        if writer.status == .writing {
            writer.finishWriting {
                if let finishError = writer.error {
                    handler(finishError)
                    return
                }
                self.deliverOutput(url: outputURL, hasVideoContent: hasVideoContent, handler: handler)
            }
        } else if writer.status == .failed {
            handler(writer.error)
        } else {
            self.deliverOutput(url: outputURL, hasVideoContent: hasVideoContent, handler: handler)
        }
    }

    private func deliverOutput(
        url: URL?,
        hasVideoContent: Bool,
        handler: @escaping (Error?) -> Void
    ) {
        guard hasVideoContent else {
            handler(nil)
            return
        }
        if saveToCameraRoll {
            saveVideoToCameraRollAfterAuthorized(url: url, handler: handler)
        } else {
            handler(nil)
        }
    }

    private func handleRecordingEndedExternally(error: Error?) {
        guard isRecording, !stopRequested else { return }
        isRecording = false
        // Capture the session's output URL: finishWriting is asynchronous and
        // a new startRecording() would otherwise republish the next
        // recording's URL (and save its file to the camera roll).
        let outputURL = videoOutputURL
        let hadVideoContent = videoWritingStarted
        finishWriterAndDeliver(
            outputURL: outputURL,
            hasVideoContent: hadVideoContent,
            handler: { finishError in
                let url = hadVideoContent ? outputURL : nil
                self.onExternalStop?(url, error ?? finishError)
            }
        )
    }

    private func saveVideoToCameraRollAfterAuthorized(url: URL?, handler: @escaping (Error?) -> Void) {
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            self.saveVideoToCameraRoll(url: url, handler: handler)
        } else {
            PHPhotoLibrary.requestAuthorization({ (status) in
                if status == .authorized {
                    self.saveVideoToCameraRoll(url: url, handler: handler)
                } else {
                    handler(ScreenRecorderError.photoLibraryAccessNotGranted)
                }
            })
        }
    }

    private func saveVideoToCameraRoll(url: URL?, handler: @escaping (Error?) -> Void) {
        guard let url = url else {
            return handler(nil)
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completionHandler: { _, error in
            if let error = error {
                handler(error)
            } else {
                handler(nil)
            }
        })
    }
}

extension ScreenRecorder: RPScreenRecorderDelegate {
    public func screenRecorder(
        _: RPScreenRecorder,
        didStopRecordingWithError error: Error,
        previewViewController _: RPPreviewViewController?
    ) {
        // A stop before the first sample fails the still-pending start; only
        // a capture that was actually running is an external stop.
        if !settlePendingStart(error) {
            handleRecordingEndedExternally(error: error)
        }
    }
}
