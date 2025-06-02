import AVFoundation
import UIKit
import CoreMedia
import MobileCoreServices

@objc(CDViOSVideoCapture)
class CDViOSVideoCapture: CDVPlugin, AVCaptureFileOutputRecordingDelegate {
    // MARK: - Properties
    
    // Capture components
    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // Commands
    private var previewCommand: CDVInvokedUrlCommand?
    private var recordingCommand: CDVInvokedUrlCommand?
    
    // Preview elements
    private var previewView: UIView?
    private var previewAspectRatio: CGFloat = 3.0/4.0 // Default aspect ratio (9:16 for portrait)
    private var elementId: String?
    
    // Recording state
    private var isRecording: Bool = false
    private var outputFileURL: URL?
    private var maxRecordDuration: Double = 60 // Default to 60 seconds
    private var targetFileName: String? // Custom filename for the recorded video
    
    // Session queue for camera operations
    private let sessionQueue = DispatchQueue(label: "com.cordova.iosVideoCapture.sessionQueue", qos: .userInitiated)
    
    // MARK: - Lifecycle
    
    override func pluginInitialize() {
        super.pluginInitialize()
    }
    
    deinit {
        cleanupCaptureSession()
    }
    
    // MARK: - Plugin API Methods
    
    @objc func startPreview(_ command: CDVInvokedUrlCommand) {
        self.previewCommand = command
        
        // Extract parameters
        guard command.arguments.count > 0,
              let params = command.arguments[0] as? [String: Any],
              let elementId = params["elementId"] as? String else {
            sendPluginError("Missing required elementId parameter", for: command)
            return
        }
        
        self.elementId = elementId
        
        // Extract optional parameters
        if let options = params["options"] as? [String: Any], let ratio = options["ratio"] as? CGFloat {
            self.previewAspectRatio = ratio
        }
        
        // Set up preview on background queue
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Clean up any existing session first
            self.cleanupCaptureSession()
            
            do {
                // Set up the capture session
                try self.setupCaptureSession()
                
                // Set up the preview layer
                DispatchQueue.main.async {
                    self.setupPreviewLayer()
                    
                    // Send success result
                    let pluginResult = CDVPluginResult(status: .ok)
                    self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                }
                
                // Start the session
                self.captureSession?.startRunning()
            } catch {
                DispatchQueue.main.async {
                    self.sendPluginError("Failed to set up camera: \(error.localizedDescription)", for: command)
                }
            }
        }
    }
    
    @objc func startRecording(_ command: CDVInvokedUrlCommand) {
        // Store the command for later use
        self.recordingCommand = command
        
        // Extract parameters
        var maxDuration: Double = 60 // Default to 60 seconds if not specified
        var targetFileName: String? = nil
        
        if command.arguments.count > 0, let params = command.arguments[0] as? [String: Any] {
            // Extract maxDuration if provided
            if let duration = params["maxDuration"] as? Double {
                maxDuration = duration
            }
            
            // Extract targetFileName if provided
            if let fileName = params["targetFileName"] as? String {
                targetFileName = fileName
            }
        }
        
        self.maxRecordDuration = maxDuration
        self.targetFileName = targetFileName
        
        // Check if capture session is set up
        guard captureSession != nil, captureSession!.isRunning else {
            sendPluginError("Camera preview not started. Call startPreview first.", for: command)
            return
        }
        
        // Start recording on session queue
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Start recording
            self.startRecordingVideo()
            
            // Send success callback to indicate recording has started
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: .ok)
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func stopRecording(_ command: CDVInvokedUrlCommand) {
        // Store the command for later use when returning the file
        self.recordingCommand = command
        
        // Check if recording is in progress
        guard isRecording, let movieFileOutput = movieFileOutput else {
            sendPluginError("Not currently recording", for: command)
            return
        }
        
        // Stop recording
        movieFileOutput.stopRecording()
        
        // Note: The result will be sent in the fileOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error: delegate method
    }
    
    @objc func stopPreview(_ command: CDVInvokedUrlCommand) {
        // Clean up resources
        cleanupCaptureSession()
        
        // Return success
        let pluginResult = CDVPluginResult(status: .ok)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    // MARK: - Camera Setup
    
    private func setupCaptureSession() throws {
        // Create capture session
        let session = AVCaptureSession()
        
        // Configure session
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find video device"])
        }
        
        // Configure video device for best quality
        try videoDevice.lockForConfiguration()
        if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
            videoDevice.exposureMode = .continuousAutoExposure
        }
        if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
            videoDevice.focusMode = .continuousAutoFocus
        }
        videoDevice.unlockForConfiguration()
        
        // Create and add video input
        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard session.canAddInput(videoInput) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not add video device input"])
        }
        session.addInput(videoInput)
        self.videoDeviceInput = videoInput
        
        // Add audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not find audio device"])
        }
        
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
        guard session.canAddInput(audioInput) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not add audio device input"])
        }
        session.addInput(audioInput)
        
        // Add movie file output
        let movieOutput = AVCaptureMovieFileOutput()
        guard session.canAddOutput(movieOutput) else {
            throw NSError(domain: "com.cordova.iosVideoCapture", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not add movie file output"])
        }
        session.addOutput(movieOutput)
        
        // Configure video connection
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        
        // Store configured components
        self.movieFileOutput = movieOutput
        self.captureSession = session
        
        // Commit configuration
        session.commitConfiguration()
    }
    
    private func setupPreviewLayer() {
        guard let captureSession = captureSession else { return }
        
        // Create preview view with proper dimensions
        let previewView = UIView(frame: UIScreen.main.bounds)
        guard let webViewAsUIView = self.webView as? UIView, let parentView = webViewAsUIView.superview else { return }
        
        // Add the preview view to the parent
        parentView.addSubview(previewView)
        
        // Initially position as fullscreen
        previewView.frame = parentView.bounds
        
        // Create preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Calculate dimensions based on aspect ratio
        let width = previewView.bounds.width
        let height = width / self.previewAspectRatio
        let yOffset = max(0, (previewView.bounds.height - height) / 2)
        
        // Set the frame
        previewLayer.frame = CGRect(x: 0, y: yOffset, width: width, height: height)
        
        // Set orientation
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        
        previewView.layer.addSublayer(previewLayer)
        
        // Store reference
        self.previewLayer = previewLayer
        self.previewView = previewView
        
        // If we have an elementId, try to position over that element
        if let elementId = self.elementId {
            // First make sure we can access the WKWebView
            guard let wkWebView = self.webView as? WKWebView else {
                NSLog("Could not access WKWebView to position element")
                return
            }
            
            // Simple JavaScript to get element position without complex parsing
            let getPositionJS = "(function() { try { var el = document.getElementById('\(elementId)'); if(!el) return '-1,-1,-1,-1'; var r = el.getBoundingClientRect(); return r.left + ',' + r.top + ',' + r.width + ',' + r.height; } catch(e) { return '-1,-1,-1,-1'; } })()"
            
            // Use WKWebView's evaluateJavaScript method instead
            wkWebView.evaluateJavaScript(getPositionJS) { [weak self] (result, error) in
                // Handle any JavaScript evaluation errors
                if let error = error {
                    NSLog("JavaScript evaluation error: \(error.localizedDescription)")
                    return
                }
                
                // Make sure we have self and a string result
                guard let self = self, let positionString = result as? String else { return }
                
                // Parse the result string which should be in format "x,y,width,height"
                let components = positionString.split(separator: ",").map(String.init)
                if components.count == 4,
                   let x = Double(components[0]),
                   let y = Double(components[1]),
                   let width = Double(components[2]),
                   let height = Double(components[3]),
                   x >= 0, y >= 0, width > 0, height > 0 {

                    // Valid element frame; proceed
                    DispatchQueue.main.async {
                        let elementFrame = CGRect(x: x, y: y, width: width, height: height)
                        self.previewView?.frame = webViewAsUIView.convert(elementFrame, to: parentView)

                        if let previewView = self.previewView, let previewLayer = self.previewLayer {
                            previewLayer.frame = previewView.bounds
                        }
                    }
                } else {
                    NSLog("Could not find valid position for element ID: \(elementId), using fullscreen")
                }

            }
        }
    }
    
    // MARK: - Recording Video
    
    private func startRecordingVideo() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure session is running
            guard let captureSession = self.captureSession,
                  captureSession.isRunning,
                  let movieFileOutput = self.movieFileOutput else {
                DispatchQueue.main.async {
                    self.sendPluginError("Camera session not ready")
                }
                return
            }
            
            // Make sure we're not already recording
            if movieFileOutput.isRecording {
                DispatchQueue.main.async {
                    self.sendPluginError("Already recording")
                }
                return
            }
            
            // Fix for error -11803: Add a small delay to ensure the session is fully running
//            Thread.sleep(forTimeInterval: 0.5)
            
            // Create temp file for recording
            let tempDir = NSTemporaryDirectory()
            
            // Use custom filename if provided, otherwise use timestamp-based filename
            let tempFileName: String
            if let targetName = self.targetFileName, !targetName.isEmpty {
                // Sanitize the filename to ensure it's valid
                let sanitizedName = targetName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
                tempFileName = "\(sanitizedName).mp4"
            } else {
                tempFileName = "video_\(Int(Date().timeIntervalSince1970)).mp4"
            }
            
            let tempFilePath = (tempDir as NSString).appendingPathComponent(tempFileName)
            let fileURL = URL(fileURLWithPath: tempFilePath)
            
            // Make sure the directory exists
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: tempDir) {
                do {
                    try fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
                } catch {
                    DispatchQueue.main.async {
                        self.sendPluginError("Failed to create temp directory")
                    }
                    return
                }
            }
            
            // Fix for error -11803: Apply changes in a locked configuration block
            captureSession.beginConfiguration()
            
            // Set max duration
            let maxDurationSeconds = CMTime(seconds: self.maxRecordDuration, preferredTimescale: 600)
            movieFileOutput.maxRecordedDuration = maxDurationSeconds
            
            // Ensure connections are properly configured
            if let videoConnection = movieFileOutput.connection(with: .video) {
                if videoConnection.isVideoOrientationSupported {
                    videoConnection.videoOrientation = .portrait
                }
                if videoConnection.isVideoStabilizationSupported {
                    videoConnection.preferredVideoStabilizationMode = .auto
                }
            }
            
            captureSession.commitConfiguration()
            
            // Store the output file URL
            self.outputFileURL = fileURL
            
            // Set recording flag
            self.isRecording = true
            
            // Fix for error -11803: Use runAsynchronouslyOnSessionQueue to ensure proper thread handling
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                NSLog("Starting video recording to: \(fileURL.path)")
                
                // Wait for a slight delay to ensure everything is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self, self.isRecording else { return }
                    movieFileOutput.startRecording(to: fileURL, recordingDelegate: self)
                }
            }
        }
    }
    
    // MARK: - Video Processing
    
    private func processRecordedVideo(at fileURL: URL) {
        // Get video dimensions
        var videoWidth: CGFloat = 0
        var videoHeight: CGFloat = 0
        
        let asset = AVAsset(url: fileURL)
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            let size = videoTrack.naturalSize
            videoWidth = size.width
            videoHeight = size.height
        }
        
        // Get file size
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = fileAttributes?[.size] as? NSNumber ?? 0
        
        // Create MediaFile object
        let mediaFile: [String: Any] = [
            "fullPath": fileURL.path,
            "localURL": fileURL.absoluteString,
            "name": fileURL.lastPathComponent,
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
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        NSLog("Recording started successfully")
    }
    
    // Required method for iOS 11+ to determine if audio should be recorded
    @available(iOS 11.0, *)
    func fileOutputShouldProvideSampleBuffer(_ output: AVCaptureFileOutput, forMediaType mediaType: AVMediaType, connection: AVCaptureConnection) -> Bool {
        // Return true for both video and audio
        return true
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Update recording state
        isRecording = false
        
        // Handle any errors
        if let error = error {
            let nsError = error as NSError
            NSLog("Recording error: \(nsError.domain) code: \(nsError.code) - \(error.localizedDescription)")
            
            // Error code -11810 is for max duration reached, which is normal
            if nsError.code != -11810 {
                // Only report error if no file was created
                if !FileManager.default.fileExists(atPath: outputFileURL.path) {
                    sendPluginError("Recording failed: \(error.localizedDescription)")
                    return
                }
            }
        }
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            sendPluginError("Recording failed: Output file not found")
            return
        }
        
        // Fire a JavaScript event with the file path when recording finishes
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Prepare the JavaScript to fire a document event
            let filePath = outputFileURL.path
            let jsEvent = "cordova.fireDocumentEvent('videoRecorderUpdate', {filePath: '" + filePath + "'}, true);"
            
            // Execute the JavaScript
            if let webView = self.webView as? WKWebView {
                webView.evaluateJavaScript(jsEvent, completionHandler: { (result, error) in
                    if let error = error {
                        NSLog("Error firing JS event: \(error.localizedDescription)")
                    }
                })
            } else {
                // Fallback to Cordova's command delegate
                self.commandDelegate?.evalJs(jsEvent)
            }
        }
        
        // Process the recorded video
        processRecordedVideo(at: outputFileURL)
    }
    
    // MARK: - Utilities
    
    private func cleanupCaptureSession() {
        // Stop recording if in progress
        if let movieFileOutput = movieFileOutput, movieFileOutput.isRecording {
            movieFileOutput.stopRecording()
        }
        
        // Stop capture session
        if let captureSession = captureSession, captureSession.isRunning {
            sessionQueue.async {
                captureSession.stopRunning()
            }
        }
        
        // Remove preview layer and view
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.previewLayer?.removeFromSuperlayer()
            self.previewView?.removeFromSuperview()
        }
    }
    
    private func sendPluginError(_ message: String, for command: CDVInvokedUrlCommand? = nil) {
        var cmd = command
        if cmd == nil {
            cmd = recordingCommand ?? previewCommand
        }
        
        if let cmd = cmd {
            let pluginResult = CDVPluginResult(status: .error, messageAs: message)
            self.commandDelegate.send(pluginResult, callbackId: cmd.callbackId)
        }
    }
    
    override func onReset() {
        cleanupCaptureSession()
    }
    
    override func onAppTerminate() {
        cleanupCaptureSession()
    }
}