import AVFoundation
import UIKit
import CoreMedia
import MobileCoreServices

@objc(CDViOSVideoCapture)
class CDViOSVideoCapture: CDVPlugin, AVCaptureFileOutputRecordingDelegate {
    // Capture components
    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var recordingCommand: CDVInvokedUrlCommand?
    private var previewView: UIView?
    
    // UI Elements
    private var timerLabel: UILabel?
    private var stopButton: UIButton?
    
    // Recording timer
    private var recordingTimer: Timer?
    private var elapsedTime: TimeInterval = 0
    
    override func pluginInitialize() {
        super.pluginInitialize()
    }
    
    @objc func startRecord(_ command: CDVInvokedUrlCommand) {
        self.recordingCommand = command
        
        // Extract maxDuration parameter
        var maxDuration: Double = 60 // Default to 60 seconds if not specified
        if command.arguments.count > 0 {
            if let durationArg = command.arguments[0] as? [String: Any], 
               let duration = durationArg["maxDuration"] as? Double {
                maxDuration = duration
            } else if let duration = command.arguments[0] as? Double {
                // For backward compatibility
                maxDuration = duration
            }
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
            
            // Add timer label
            setupTimerLabel(in: previewView)
            
            // Add stop button
            setupStopButton(in: previewView)
        }
        
        // Start the session
        captureSession.startRunning()
    }
    
    private func setupTimerLabel(in view: UIView) {
        timerLabel = UILabel()
        guard let timerLabel = timerLabel else { return }
        
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.text = "00:00"
        timerLabel.textColor = .white
        timerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        timerLabel.textAlignment = .center
        timerLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
        timerLabel.layer.cornerRadius = 8
        timerLabel.layer.masksToBounds = true
        
        view.addSubview(timerLabel)
        
        NSLayoutConstraint.activate([
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.widthAnchor.constraint(equalToConstant: 80),
            timerLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func setupStopButton(in view: UIView) {
        stopButton = UIButton(type: .custom)
        guard let stopButton = stopButton else { return }
        
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Create a square stop icon instead of text
        let iconSize: CGFloat = 20
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
        stopButton.layer.cornerRadius = 30
        stopButton.addTarget(self, action: #selector(stopButtonTapped), for: .touchUpInside)
        
        view.addSubview(stopButton)
        
        NSLayoutConstraint.activate([
            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            stopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 60),
            stopButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    @objc private func stopButtonTapped() {
        if movieFileOutput?.isRecording == true {
            movieFileOutput?.stopRecording()
        }
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
        
        // Reset and start timer
        elapsedTime = 0
        startRecordingTimer()
        
        // Start recording
        movieFileOutput.startRecording(to: fileURL, recordingDelegate: self)
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started
        // Timer is already started in startRecordingVideo
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Clean up the capture session
        cleanupCaptureSession()
        
        // Check if error is related to reaching max duration
        // When maxDuration is reached, AVFoundation still provides a valid recording
        // but also returns an error of AVError.Code -11810 (maxDuration reached)
        
        if let error = error {
            let nsError = error as NSError
            // AVFoundation returns error code 11810 when reaching max duration
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
        // Stop the recording timer
        stopRecordingTimer()
        
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
        timerLabel = nil
        stopButton = nil
    }
    
    private func sendPluginError(_ message: String) {
        if let command = recordingCommand {
            let pluginResult = CDVPluginResult(status: .error, messageAs: message)
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        }
        
        cleanupCaptureSession()
    }
}

// MARK: - Timer Management
extension CDViOSVideoCapture {
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
}
