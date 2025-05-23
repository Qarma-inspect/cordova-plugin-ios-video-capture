import AVFoundation
import UIKit
import CoreMedia
import MobileCoreServices

@objc(CDViOSVideoCapture)
class CDViOSVideoCapture: CDVPlugin, AVCaptureFileOutputRecordingDelegate {
    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var recordingCommand: CDVInvokedUrlCommand?
    private var previewView: UIView?
    
    override func pluginInitialize() {
        super.pluginInitialize()
    }
    
    @objc func startRecord(_ command: CDVInvokedUrlCommand) {
        self.recordingCommand = command
        
        // Extract maxDuration parameter
        var maxDuration: Double = 60 // Default to 60 seconds if not specified
        if command.arguments.count > 0, let duration = command.arguments[0] as? Double {
            maxDuration = duration
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set up and start recording
            do {
                try self.setupCaptureSession()
                self.setupPreviewLayer()
                self.startRecordingVideo(maxDuration: maxDuration)
            } catch {
                self.sendPluginError("Failed to set up camera: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupCaptureSession() throws {
        // Create capture session
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not create capture session"])
        }
        
        // Configure session for video recording
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find video device"])
        }
        
        videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        
        guard let videoDeviceInput = videoDeviceInput, captureSession.canAddInput(videoDeviceInput) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not add video device input"])
        }
        captureSession.addInput(videoDeviceInput)
        
        // Add audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not find audio device"])
        }
        
        let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
        
        guard captureSession.canAddInput(audioDeviceInput) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not add audio device input"])
        }
        captureSession.addInput(audioDeviceInput)
        
        // Add movie file output
        movieFileOutput = AVCaptureMovieFileOutput()
        
        guard let movieFileOutput = movieFileOutput, captureSession.canAddOutput(movieFileOutput) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not add movie file output"])
        }
        captureSession.addOutput(movieFileOutput)
        
        captureSession.commitConfiguration()
    }
    
    private func setupPreviewLayer() {
        guard let captureSession = captureSession else { return }
        
        // Create preview view
        previewView = UIView(frame: UIScreen.main.bounds)
        if let previewView = previewView, let webView = self.webView, let parentView = webView.superview {
            parentView.addSubview(previewView)
            previewView.frame = parentView.bounds
            
            // Create preview layer
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
            previewLayer?.frame = previewView.bounds
            
            if let previewLayer = previewLayer {
                previewView.layer.addSublayer(previewLayer)
            }
        }
        
        // Start the session
        captureSession.startRunning()
    }
    
    private func startRecordingVideo(maxDuration: Double) {
        guard let movieFileOutput = movieFileOutput else {
            sendPluginError("Movie file output not set up")
            return
        }
        
        // Set maximum duration
        let maxDurationSeconds = CMTime(seconds: maxDuration, preferredTimescale: 1)
        movieFileOutput.maxRecordedDuration = maxDurationSeconds
        
        // Create temp file for recording
        let tempDir = NSTemporaryDirectory()
        let tempFileName = "video_\(Int(Date().timeIntervalSince1970)).mp4"
        let tempFilePath = (tempDir as NSString).appendingPathComponent(tempFileName)
        let fileURL = URL(fileURLWithPath: tempFilePath)
        
        // Start recording
        movieFileOutput.startRecording(to: fileURL, recordingDelegate: self)
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Clean up the capture session
        cleanupCaptureSession()
        
        if let error = error {
            sendPluginError("Recording failed: \(error.localizedDescription)")
            return
        }
        
        // Get video dimensions
        var videoWidth: CGFloat = 0
        var videoHeight: CGFloat = 0
        
        let asset = AVAsset(url: outputFileURL)
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            let size = videoTrack.naturalSize
            videoWidth = size.width
            videoHeight = size.height
        }
        
        // Get file size
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)
        let fileSize = fileAttributes?[.size] as? NSNumber ?? 0
        
        // Create MediaFile object
        let mediaFile: [String: Any] = [
            "fullPath": outputFileURL.path,
            "localURL": outputFileURL.absoluteString,
            "name": outputFileURL.lastPathComponent,
            "size": fileSize.intValue,
            "type": "video/mp4",
            "width": Int(videoWidth),
            "height": Int(videoHeight)
        ]
        
        // Send result back to JavaScript
        if let command = recordingCommand {
            let pluginResult = CDVPluginResult(status: .ok, messageAs: mediaFile)
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    private func cleanupCaptureSession() {
        captureSession?.stopRunning()
        
        // Remove preview layer and view
        previewLayer?.removeFromSuperlayer()
        previewView?.removeFromSuperview()
        
        // Reset all capture objects
        captureSession = nil
        videoDeviceInput = nil
        movieFileOutput = nil
        previewLayer = nil
        previewView = nil
    }
    
    private func sendPluginError(_ message: String) {
        if let command = recordingCommand {
            let pluginResult = CDVPluginResult(status: .error, messageAs: message)
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        }
        
        cleanupCaptureSession()
    }
}
