//
//  ScreenRecorder.swift
//  Wyler
//
//  Created by Cesar Vargas on 10.04.20.
//  Modified by Martin Donadieu on 03.12.21.
//  Copyright © 2020 Cesar Vargas. All rights reserved.
//

import Foundation
import ReplayKit
import Photos

enum ScreenRecorderError: Error {
    case notAvailable
    case photoLibraryAccessNotGranted
}

final public class ScreenRecorder {
  private var videoOutputURL: URL?
  private var videoWriter: AVAssetWriter?
  private var videoWriterInput: AVAssetWriterInput?
  private var saveToCameraRoll = false

  public init() {}

  /**
   Starts recording the content of the application screen. It works together with stopRecording

  - Parameter outputURL: The output where the video will be saved. If nil, it saves it in the documents directory.
  - Parameter size: The size of the video. If nil, it will use the app screen size.
  - Parameter saveToCameraRoll: Whether to save it to camera roll. False by default.
  - Parameter errorHandler: Called when an error is found
  */
  public func startRecording(to outputURL: URL? = nil,
                             size: CGSize? = nil,
                             saveToCameraRoll: Bool = false,
                             handler: @escaping (Error?) -> Void) {
    if saveToCameraRoll {
      checkPhotoLibraryAuthorizationStatus()
    }
    do {
        try createVideoWriter(in: outputURL)
        addVideoWriterInput(size: size)
        startCapture(handler: handler)
    } catch let err {
        handler(err)
    }
  }

  private func checkPhotoLibraryAuthorizationStatus() {
    let status = PHPhotoLibrary.authorizationStatus()
    if status == .notDetermined {
      PHPhotoLibrary.requestAuthorization({ _ in })
    }
  }

  private func createVideoWriter(in outputURL: URL? = nil) throws {
    let newVideoOutputURL: URL

    if let passedVideoOutput = outputURL {
      self.videoOutputURL = passedVideoOutput
      newVideoOutputURL = passedVideoOutput
    } else {
      let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
      newVideoOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent("WylerNewVideo.mp4"))
      self.videoOutputURL = newVideoOutputURL
    }

    do {
      try FileManager.default.removeItem(at: newVideoOutputURL)
    } catch {}

    do {
      try videoWriter = AVAssetWriter(outputURL: newVideoOutputURL, fileType: AVFileType.mp4)
    } catch let writerError as NSError {
      videoWriter = nil
      throw writerError
    }
  }

  private func addVideoWriterInput(size: CGSize?) {
    let passingSize: CGSize

    if let passedSize = size {
      passingSize = passedSize
    } else {
      passingSize = UIScreen.main.bounds.size
    }

    let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                        AVVideoWidthKey: passingSize.width,
                                        AVVideoHeightKey: passingSize.height]

    let newVideoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
    self.videoWriterInput = newVideoWriterInput
    videoWriter?.add(newVideoWriterInput)
  }

  private func startCapture(handler: @escaping (Error?) -> Void) {
    guard RPScreenRecorder.shared().isAvailable else {
        return handler(ScreenRecorderError.notAvailable)
    }
    RPScreenRecorder.shared().startCapture(handler: { (sampleBuffer, sampleType, passedError) in
      if let passedError = passedError {
        handler(passedError)
      }

      switch sampleType {
          case .video:
            self.handleSampleBuffer(sampleBuffer: sampleBuffer)
          default:
            break
          }
        handler(nil)
    })
  }

  private func handleSampleBuffer(sampleBuffer: CMSampleBuffer) {
    if self.videoWriter?.status == AVAssetWriter.Status.unknown {
      self.videoWriter?.startWriting()
      self.videoWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    } else if self.videoWriter?.status == AVAssetWriter.Status.writing &&
      self.videoWriterInput?.isReadyForMoreMediaData == true {
      self.videoWriterInput?.append(sampleBuffer)
    }
  }

  /**
   Stops recording the content of the application screen, after calling startRecording

  - Parameter errorHandler: Called when an error is found
  */
  public func stoprecording(handler: @escaping (Error?) -> Void) {
    RPScreenRecorder.shared().stopCapture( handler: { error in
        if let error = error {
            handler(error)
        } else {
            self.videoWriterInput?.markAsFinished()
            self.videoWriter?.finishWriting {
              self.saveVideoToCameraRollAfterAuthorized(handler: handler)
            }
        }
    })
  }

  private func saveVideoToCameraRollAfterAuthorized(handler: @escaping (Error?) -> Void) {
    if PHPhotoLibrary.authorizationStatus() == .authorized {
        self.saveVideoToCameraRoll(handler: handler)
    } else {
        PHPhotoLibrary.requestAuthorization({ (status) in
            if status == .authorized {
                self.saveVideoToCameraRoll(handler: handler)
            } else {
              handler(WylerError.photoLibraryAccessNotGranted)
          }
        })
    }
  }

  private func saveVideoToCameraRoll(handler: @escaping (Error?) -> Void) {
    guard let videoOutputURL = self.videoOutputURL else {
      return handler(nil)
    }

    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoOutputURL)
    }, completionHandler: { _, error in
      if let error = error {
          handler(error)
      } else {
          handler(nil)
      }
    })
  }
}
