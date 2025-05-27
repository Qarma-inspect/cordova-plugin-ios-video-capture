import AVFoundation
import UIKit
import CoreMedia
import MobileCoreServices
import WebKit

@objc(CDViOSVideoCapture)
class CDViOSVideoCapture: CDVPlugin, AVCaptureFileOutputRecordingDelegate {
    // Capture components
    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // Commands
    private var previewCommand: CDVInvokedUrlCommand?
    private var recordingCommand: CDVInvokedUrlCommand?
    
    // Preview elements
    private var previewContainerView: UIView?
    private var previewWebElement: WKWebView?
    private var elementRect: CGRect = .zero
    private var previewAspectRatio: CGFloat = 3.0/4.0 // Default aspect ratio is 3:4 (portrait mode)
    
    // UI Elements
    private var timerLabel: UILabel?
    private var stopButton: UIButton?
    
    // Recording state
    private var isRecording: Bool = false
    private var outputFileURL: URL?
    private var maxRecordDuration: Double = 60
    
    // Recording timer
    private var recordingTimer: Timer?
    private var elapsedTime: TimeInterval = 0
    
    override func pluginInitialize() {
        super.pluginInitialize()
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func orientationChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let previewLayer = self.previewLayer, let previewContainerView = self.previewContainerView else { return }
            
            // Recalculate frame based on aspect ratio
            let containerWidth = previewContainerView.bounds.width
            let containerHeight = previewContainerView.bounds.height
            
            // Calculate frame based on aspect ratio
            var previewFrame = previewContainerView.bounds
            let containerRatio = containerWidth / containerHeight
            
            if self.previewAspectRatio > containerRatio {
                // Preview is wider than container, adjust height
                let newHeight = containerWidth / self.previewAspectRatio
                let yOffset = (containerHeight - newHeight) / 2
                previewFrame = CGRect(x: 0, y: yOffset, width: containerWidth, height: newHeight)
            } else {
                // Preview is taller than container, adjust width
                let newWidth = containerHeight * self.previewAspectRatio
                let xOffset = (containerWidth - newWidth) / 2
                previewFrame = CGRect(x: xOffset, y: 0, width: newWidth, height: containerHeight)
            }
            
            // Always maintain portrait orientation for the preview layer
            previewLayer.connection?.videoOrientation = .portrait
            previewLayer.frame = previewFrame
        }
    }
    
    // MARK: - Plugin API Methods
    
    @objc func startPreview(_ command: CDVInvokedUrlCommand) {
        self.previewCommand = command
        
        guard let params = command.arguments[0] as? [String: Any],
              let elementId = params["elementId"] as? String else {
            sendPluginError("Missing required parameters", command: command)
            return
        }
        
        // Extract optional parameters
        if let options = params["options"] as? [String: Any] {
            if let ratio = options["ratio"] as? CGFloat {
                // If a ratio is provided, we assume it's in the format width:height
                // For portrait mode, we want to invert it to ensure height > width
                self.previewAspectRatio = 1.0 / ratio
            }
        }
        
        // We'll use this to start the camera preview
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Set up capture session first
                try self.setupCaptureSession()
                
                // Find the web element by ID and get its rect
                self.findWebElementRect(elementId) { success, rect in
                    if success {
                        self.elementRect = rect
                        self.setupPreviewInElement()
                        
                        let result = CDVPluginResult(status: .ok)
                        self.commandDelegate.send(result, callbackId: command.callbackId)
                    } else {
                        self.sendPluginError("Could not find element with ID: \(elementId)", command: command)
                    }
                }
            } catch {
                self.sendPluginError("Failed to set up camera: \(error.localizedDescription)", command: command)
            }
        }
    }
    
    @objc func startRecording(_ command: CDVInvokedUrlCommand) {
        // Store the command for later use when recording finishes
        self.recordingCommand = command
        
        // Extract maxDuration parameter
        if let params = command.arguments[0] as? [String: Any],
           let maxDuration = params["maxDuration"] as? Double {
            self.maxRecordDuration = maxDuration
        }
        
        guard captureSession != nil, captureSession!.isRunning else {
            sendPluginError("Camera preview not started", command: command)
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if !self.isRecording {
                self.startRecordingVideo()
                
                // Notify JS that recording has started
                let result = CDVPluginResult(status: .ok)
                self.commandDelegate.send(result, callbackId: command.callbackId)
            } else {
                self.sendPluginError("Already recording", command: command)
            }
        }
    }
    
    @objc func stopRecording(_ command: CDVInvokedUrlCommand) {
        // Store the command for when we need to return the file
        self.recordingCommand = command
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.isRecording, let movieFileOutput = self.movieFileOutput {
                movieFileOutput.stopRecording()
            } else {
                self.sendPluginError("Not currently recording", command: command)
            }
        }
    }
    
    @objc func stopPreview(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // If recording is in progress, stop it first
            if self.isRecording, let movieFileOutput = self.movieFileOutput {
                movieFileOutput.stopRecording()
                // Note: We're not returning the recording here since stopPreview is explicitly
                // asking to clean up resources, not to get recording results
            }
            
            // Clean up resources
            self.cleanupPreview()
            
            // Return success
            let result = CDVPluginResult(status: .ok)
            self.commandDelegate.send(result, callbackId: command.callbackId)
        }
    }
    
    // MARK: - Camera Setup
    
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
        
        // Configure video device for best portrait capture
        try videoDevice.lockForConfiguration()
        if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
            videoDevice.exposureMode = .continuousAutoExposure
        }
        if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
            videoDevice.focusMode = .continuousAutoFocus
        }
        videoDevice.unlockForConfiguration()
        
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
        
        // Configure video connection to always use portrait orientation
        if let connection = movieFileOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    // MARK: - Web Element Integration
    
    private func findWebElementRect(_ elementId: String, completion: @escaping (Bool, CGRect) -> Void) {
        // Get reference to the webview
        guard let webView = self.webView as? WKWebView else {
            completion(false, .zero)
            return
        }
        
        self.previewWebElement = webView
        
        // JavaScript to find element and get its position and size
        let js = """
        (function() {
            var element = document.getElementById('\(elementId)');
            if (!element) return null;
            
            var rect = element.getBoundingClientRect();
            return {
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height
            };
        })()
        """
        
        webView.evaluateJavaScript(js) { [weak self] (result, error) in
            guard let self = self, error == nil, let rectDict = result as? [String: Any],
                  let x = rectDict["x"] as? CGFloat,
                  let y = rectDict["y"] as? CGFloat,
                  let width = rectDict["width"] as? CGFloat,
                  let height = rectDict["height"] as? CGFloat else {
                completion(false, .zero)
                return
            }
            
            // Convert coordinates from web view to window coordinates
            let elementRect = CGRect(x: x, y: y, width: width, height: height)
            completion(true, elementRect)
        }
    }
    
    private func setupPreviewInElement() {
        guard let webView = self.previewWebElement,
              let captureSession = self.captureSession else { return }
        
        // Create a container view that will hold our preview
        let containerView = UIView(frame: elementRect)
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.superview?.addSubview(containerView)
        self.previewContainerView = containerView
        
        // Create preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        guard let previewLayer = previewLayer else { return }
        
        // Set preview layer to always use portrait orientation
        previewLayer.connection?.videoOrientation = .portrait
        
        // Apply aspect ratio
        let containerWidth = containerView.bounds.width
        let containerHeight = containerView.bounds.height
        
        // Calculate frame based on aspect ratio
        var previewFrame = containerView.bounds
        let containerRatio = containerWidth / containerHeight
        
        if self.previewAspectRatio > containerRatio {
            // Preview is wider than container, adjust height
            let newHeight = containerWidth / self.previewAspectRatio
            let yOffset = (containerHeight - newHeight) / 2
            previewFrame = CGRect(x: 0, y: yOffset, width: containerWidth, height: newHeight)
        } else {
            // Preview is taller than container, adjust width
            let newWidth = containerHeight * self.previewAspectRatio
            let xOffset = (containerWidth - newWidth) / 2
            previewFrame = CGRect(x: xOffset, y: 0, width: newWidth, height: containerHeight)
        }
        
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = previewFrame
        containerView.layer.addSublayer(previewLayer)
        
        // Add timer label and stop button
        setupTimerLabel(in: containerView)
        setupStopButton(in: containerView)
        
        // Start the preview
        captureSession.startRunning()
    }
    
    // MARK: - UI Elements
    
    private func setupTimerLabel(in view: UIView) {
        timerLabel = UILabel()
        guard let timerLabel = timerLabel else { return }
        
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.text = "00:00"
        timerLabel.textColor = .white
        timerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        timerLabel.textAlignment = .center
        timerLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
        timerLabel.layer.cornerRadius = 8
        timerLabel.layer.masksToBounds = true
        timerLabel.isHidden = true  // Initially hidden, shown when recording starts
        
        view.addSubview(timerLabel)
        
        NSLayoutConstraint.activate([
            timerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.widthAnchor.constraint(equalToConstant: 70),
            timerLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    private func setupStopButton(in view: UIView) {
        // Create stop button (initially hidden)
        stopButton = UIButton(type: .custom)
        guard let stopButton = stopButton else { return }
        
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Create a square stop icon
        let iconSize: CGFloat = 15
        let iconView = UIView(frame: CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
        iconView.backgroundColor = .white
        iconView.layer.cornerRadius = 2
        
        // Center the icon in the button
        stopButton.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: stopButton.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize)
        ])
        
        stopButton.backgroundColor = UIColor.red
        stopButton.layer.cornerRadius = 25
        stopButton.addTarget(self, action: #selector(stopButtonTapped), for: .touchUpInside)
        stopButton.isHidden = true  // Initially hidden
        
        view.addSubview(stopButton)
        
        NSLayoutConstraint.activate([
            stopButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            stopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 50),
            stopButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    

    
    @objc private func stopButtonTapped() {
        // Call stopRecording programmatically
        let command = CDVInvokedUrlCommand(arguments: [], callbackId: "internal", className: "", methodName: "")
        if let command = command {
            self.stopRecording(command)
        }
    }
    
    // MARK: - Recording
    
    private func startRecordingVideo() {
        guard let movieFileOutput = movieFileOutput else {
            sendPluginError("Movie file output not set up")
            return
        }
        
        // Set maximum duration
        let maxDurationSeconds = CMTime(seconds: maxRecordDuration, preferredTimescale: 1)
        movieFileOutput.maxRecordedDuration = maxDurationSeconds
        
        // Create temp file for recording
        let tempDir = NSTemporaryDirectory()
        let tempFileName = "video_\(Int(Date().timeIntervalSince1970)).mp4"
        let tempFilePath = (tempDir as NSString).appendingPathComponent(tempFileName)
        let fileURL = URL(fileURLWithPath: tempFilePath)
        self.outputFileURL = fileURL
        
        // UI updates - show timer and stop button
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopButton?.isHidden = false
            self.timerLabel?.isHidden = false
            
            // Reset and start timer
            self.elapsedTime = 0
            self.startRecordingTimer()
        }
        
        // Set recording flag
        isRecording = true
        
        // Start recording
        movieFileOutput.startRecording(to: fileURL, recordingDelegate: self)
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started - handled in startRecordingVideo
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Recording finished
        isRecording = false
        
        // Stop the timer
        stopRecordingTimer()
        
        // UI updates - hide stop button and timer
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopButton?.isHidden = true
            self.timerLabel?.isHidden = true
        }
        
        // Check if error is related to reaching max duration
        if let error = error {
            let nsError = error as NSError
            // AVFoundation returns error code -11810 when reaching max duration
            // We'll still process the file in this case
            if nsError.code != -11810 {
                sendPluginError("Recording failed: \(error.localizedDescription)")
                return
            }
        }
        
        // Only process if we have a valid file
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            sendPluginError("Recording failed: Output file not found")
            return
        }
        
        // Process the recorded video
        processRecordedVideo(at: outputFileURL)
    }
    
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
    
    // MARK: - Timer Management
    
    private func startRecordingTimer() {
        // Stop any existing timer
        stopRecordingTimer()
        
        // Create and start a new timer
        recordingTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateTimer), userInfo: nil, repeats: true)
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    @objc private func updateTimer() {
        elapsedTime += 0.1
        
        // Format time as MM:SS
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let timeString = String(format: "%02d:%02d", minutes, seconds)
        
        // Update timer label on main thread
        DispatchQueue.main.async { [weak self] in
            self?.timerLabel?.text = timeString
        }
    }
    
    // MARK: - Utilities
    
    private func sendPluginError(_ message: String, command: CDVInvokedUrlCommand? = nil) {
        let pluginResult = CDVPluginResult(status: .error, messageAs: message)
        if let command = command ?? recordingCommand {
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    override func onReset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cleanupPreview()
        }
    }
    
    private func cleanupPreview() {
        // Stop recording if in progress
        if self.isRecording, let movieFileOutput = self.movieFileOutput {
            movieFileOutput.stopRecording()
            self.isRecording = false
        }
        
        // Stop timer
        self.stopRecordingTimer()
        
        // Stop capture session
        self.captureSession?.stopRunning()
        
        // Clean up UI
        self.previewLayer?.removeFromSuperlayer()
        self.previewContainerView?.removeFromSuperview()
        
        // Reset all references
        self.previewLayer = nil
        self.previewContainerView = nil
        self.captureSession = nil
        self.videoDeviceInput = nil
        self.movieFileOutput = nil
        self.stopButton = nil
        self.timerLabel = nil
        self.previewWebElement = nil
        self.recordingCommand = nil
        self.previewCommand = nil
    }
}