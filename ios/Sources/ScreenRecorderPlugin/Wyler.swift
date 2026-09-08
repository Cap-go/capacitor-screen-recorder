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
    private var isFinalizing = false
    private var captureSessionID: UInt64 = 0
    private var delegateSessionID: UInt64 = 0
    private var recordingEstablishedSessionID: UInt64 = 0
    private var pendingRestartDrain = false
    private let stateLock = NSLock()

    private struct FinalizationSnapshot {
        let outputURL: URL?
        let writer: AVAssetWriter?
        let videoInput: AVAssetWriterInput?
        let micInput: AVAssetWriterInput?
        let appInput: AVAssetWriterInput?
        let hasVideoContent: Bool
        let saveToCameraRoll: Bool
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func isActiveCaptureSession(_ sessionID: UInt64) -> Bool {
        return withStateLock {
            sessionID == captureSessionID && isRecording && !isFinalizing
        }
    }

    private func isActiveDelegateSession() -> Bool {
        return withStateLock {
            !pendingRestartDrain &&
                delegateSessionID != 0 &&
                delegateSessionID == captureSessionID &&
                isRecording &&
                !isFinalizing &&
                !stopRequested
        }
    }

    private func markFinalizationComplete() {
        withStateLock {
            isFinalizing = false
            pendingRestartDrain = true
            recordingEstablishedSessionID = 0
        }
    }

    private func invalidateDelegateSession() {
        withStateLock {
            delegateSessionID = 0
        }
        recorder.delegate = nil
    }

    private func nextCaptureSessionID() -> UInt64 {
        return withStateLock {
            captureSessionID += 1
            return captureSessionID
        }
    }

    public func startRecording(to outputURL: URL? = nil,
                               size: CGSize? = nil,
                               saveToCameraRoll: Bool = false,
                               recordAudio: Bool = false,
                               videoFormat: VideoContainerFormat = .mp4,
                               handler: @escaping (Error?) -> Void) {
        if withStateLock({ pendingRestartDrain }) {
            invalidateDelegateSession()
            recorder.stopCapture(handler: { [weak self] _ in
                guard let self = self else { return }
                withStateLock {
                    pendingRestartDrain = false
                }
                self.startRecording(
                    to: outputURL,
                    size: size,
                    saveToCameraRoll: saveToCameraRoll,
                    recordAudio: recordAudio,
                    videoFormat: videoFormat,
                    handler: handler
                )
            })
            return
        }
        // Reject before any writer/session state is touched: a second start
        // while the first is still pending must not disturb the first capture.
        let rejectError: Error? = withStateLock {
            guard pendingStartHandler == nil, !isFinalizing else {
                return ScreenRecorderError.captureAlreadyPending
            }
            stopRequested = false
            self.saveToCameraRoll = saveToCameraRoll
            self.recordAudio = recordAudio
            self.videoFormat = videoFormat
            resetWriterState()
            return nil
        }
        if let rejectError {
            return handler(rejectError)
        }
        recorder.delegate = self

        recorder.isMicrophoneEnabled = recordAudio

        do {
            if recordAudio {
                try configureAudioSession()
            }
            try withStateLock {
                try createVideoWriter(in: outputURL)
                addVideoWriterInput(size: size)
                if recordAudio {
                    self.micAudioWriterInput = createAndAddAudioInput()
                    self.appAudioWriterInput = createAndAddAudioInput()
                }
            }
            startCapture(handler: handler)
        } catch let err {
            withStateLock {
                isRecording = false
                pendingStartHandler = nil
                captureSessionID += 1
            }
            handler(err)
        }
    }

    private func resetWriterState() {
        videoWriter = nil
        videoWriterInput = nil
        micAudioWriterInput = nil
        appAudioWriterInput = nil
        videoWritingStarted = false
        recordingEstablishedSessionID = 0
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
        let sessionID = nextCaptureSessionID()
        withStateLock {
            isRecording = true
            // The start is settled exactly once — by the first sample, a capture
            // failure, the delegate, or stoprecording() — whichever comes first,
            // so the plugin's start promise never hangs and never settles twice.
            pendingStartHandler = handler
        }
        recorder.stopCapture(handler: { [weak self] _ in
            guard let self = self else { return }
            self.invalidateDelegateSession()
            withStateLock {
                pendingRestartDrain = false
            }
            guard self.isActiveCaptureSession(sessionID) else { return }
            withStateLock {
                delegateSessionID = sessionID
            }
            self.recorder.delegate = self
            self.recorder.startCapture(handler: { [weak self] (sampleBuffer, sampleType, passedError) in
                guard let self = self else { return }
                guard self.isActiveCaptureSession(sessionID) else { return }
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
                    if self.handleSampleBuffer(sampleBuffer: sampleBuffer) {
                        self.settlePendingStart(nil)
                    } else {
                        let error: Error? = self.withStateLock {
                            guard let writer = videoWriter, writer.status == .failed else {
                                return nil
                            }
                            return writer.error ?? ScreenRecorderError.captureInterrupted
                        }
                        if let error = error {
                            if !self.settlePendingStart(error) {
                                self.handleRecordingEndedExternally(error: error)
                            }
                        }
                    }
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
        })
    }

    /// Settles the pending start exactly once. Returns true when this call
    /// settled it. A failure also clears `isRecording`, because the capture
    /// never produced output; once settled, end-of-capture reporting belongs
    /// to the delegate / stoprecording().
    @discardableResult
    private func settlePendingStart(_ error: Error?) -> Bool {
        let startHandler: ((Error?) -> Void)? = withStateLock {
            guard let handler = pendingStartHandler else {
                return nil
            }
            pendingStartHandler = nil
            if error != nil {
                isRecording = false
            }
            return handler
        }
        guard let startHandler else {
            return false
        }
        startHandler(error)
        return true
    }

    @discardableResult
    private func handleSampleBuffer(sampleBuffer: CMSampleBuffer) -> Bool {
        return withStateLock {
            guard let writer = videoWriter else { return false }
            if writer.status == AVAssetWriter.Status.unknown {
                writer.startWriting()
                if writer.status == .failed {
                    return false
                }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                if writer.status == .failed {
                    return false
                }
            }
            guard writer.status == AVAssetWriter.Status.writing else {
                return false
            }
            videoWritingStarted = true
            recordingEstablishedSessionID = captureSessionID
            if videoWriterInput?.isReadyForMoreMediaData == true {
                videoWriterInput?.append(sampleBuffer)
            }
            return true
        }
    }

    private func add(sample: CMSampleBuffer, to writerInput: AVAssetWriterInput?) {
        withStateLock {
            guard let writerInput = writerInput else { return }
            guard self.videoWriter?.status == .writing else { return }
            if writerInput.isReadyForMoreMediaData {
                writerInput.append(sample)
            }
        }
    }

    public func stoprecording(handler: @escaping (Error?) -> Void) {
        let snapshot: FinalizationSnapshot? = withStateLock { () -> FinalizationSnapshot? in
            guard !isFinalizing else { return nil }
            stopRequested = true
            isFinalizing = true
            captureSessionID += 1
            delegateSessionID = 0
            return FinalizationSnapshot(
                outputURL: videoOutputURL,
                writer: videoWriter,
                videoInput: videoWriterInput,
                micInput: micAudioWriterInput,
                appInput: appAudioWriterInput,
                hasVideoContent: videoWritingStarted,
                saveToCameraRoll: saveToCameraRoll
            )
        }
        guard let snapshot else {
            handler(nil)
            return
        }
        invalidateDelegateSession()
        recorder.stopCapture(handler: { error in
            if let error = error {
                self.settlePendingStart(error)
                self.finishWriterAndDeliver(snapshot: snapshot, handler: { _ in
                    handler(error)
                })
                return
            }

            withStateLock {
                isRecording = false
            }
            // stop() may arrive before the first sample: settle the pending
            // start so the caller's start promise does not hang.
            self.settlePendingStart(ScreenRecorderError.captureInterrupted)
            self.finishWriterAndDeliver(snapshot: snapshot, handler: handler)
        })
    }

    private func finishWriterAndDeliver(
        snapshot: FinalizationSnapshot,
        handler: @escaping (Error?) -> Void
    ) {
        let writer = snapshot.writer
        let videoInput = snapshot.videoInput
        let micInput = snapshot.micInput
        let appInput = snapshot.appInput

        videoInput?.markAsFinished()
        micInput?.markAsFinished()
        appInput?.markAsFinished()

        guard let writer = writer else {
            self.markFinalizationComplete()
            handler(nil)
            return
        }

        if writer.status == .writing {
            writer.finishWriting {
                if let finishError = writer.error {
                    self.markFinalizationComplete()
                    handler(finishError)
                    return
                }
                self.deliverOutput(
                    url: snapshot.outputURL,
                    hasVideoContent: snapshot.hasVideoContent,
                    saveToCameraRoll: snapshot.saveToCameraRoll,
                    handler: { error in
                        self.markFinalizationComplete()
                        handler(error)
                    }
                )
            }
        } else if writer.status == .failed {
            self.markFinalizationComplete()
            handler(writer.error)
        } else {
            self.deliverOutput(
                url: snapshot.outputURL,
                hasVideoContent: snapshot.hasVideoContent,
                saveToCameraRoll: snapshot.saveToCameraRoll,
                handler: { error in
                    self.markFinalizationComplete()
                    handler(error)
                }
            )
        }
    }

    private func deliverOutput(
        url: URL?,
        hasVideoContent: Bool,
        saveToCameraRoll: Bool,
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
        let snapshot: FinalizationSnapshot? = withStateLock {
            guard isRecording, !stopRequested else { return nil }
            isRecording = false
            isFinalizing = true
            captureSessionID += 1
            delegateSessionID = 0
            return FinalizationSnapshot(
                outputURL: videoOutputURL,
                writer: videoWriter,
                videoInput: videoWriterInput,
                micInput: micAudioWriterInput,
                appInput: appAudioWriterInput,
                hasVideoContent: videoWritingStarted,
                saveToCameraRoll: saveToCameraRoll
            )
        }
        guard let snapshot else { return }
        invalidateDelegateSession()
        finishWriterAndDeliver(snapshot: snapshot, handler: { finishError in
            let url = snapshot.hasVideoContent ? snapshot.outputURL : nil
            self.onExternalStop?(url, error ?? finishError)
        })
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
        guard isActiveDelegateSession() else { return }
        // A stop before the first sample fails the still-pending start; only
        // a capture that was actually running is an external stop.
        if settlePendingStart(error) {
            invalidateDelegateSession()
            return
        }
        let shouldFinalize = withStateLock {
            recordingEstablishedSessionID != 0 &&
                recordingEstablishedSessionID == captureSessionID
        }
        guard shouldFinalize else {
            invalidateDelegateSession()
            return
        }
        handleRecordingEndedExternally(error: error)
        invalidateDelegateSession()
    }
}
