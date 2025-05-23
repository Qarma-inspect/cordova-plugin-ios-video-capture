# cordova-plugin-ios-video-capture

A Cordova plugin for iOS video recording using modern Swift and AVFoundation.

## Features

- Built with modern Swift and AVFoundation
- Simple API for video recording
- Configurable maximum recording duration
- Returns detailed metadata about the recorded video file

## Installation

```bash
cordova plugin add cordova-plugin-ios-video-capture
```

## Requirements

- Cordova iOS 6.0.0 or higher
- iOS 11.0 or higher
- Swift 5

## Usage

```javascript
// Start video recording with a maximum duration of 30 seconds
cordova.plugins.iOSVideoCapture.startRecord(30)
  .then(function(mediaFile) {
    console.log('Video recorded successfully');
    console.log('File path: ' + mediaFile.fullPath);
    console.log('File size: ' + mediaFile.size);
    console.log('Video dimensions: ' + mediaFile.width + 'x' + mediaFile.height);
    
    // You can use the mediaFile object to display or process the video
    var videoElement = document.createElement('video');
    videoElement.src = mediaFile.localURL;
    videoElement.controls = true;
    document.body.appendChild(videoElement);
  })
  .catch(function(error) {
    console.error('Error recording video: ' + error);
  });
```

## API

### startRecord(maxDuration)

Starts video recording with the specified maximum duration.

#### Parameters

- `maxDuration` (Number): Maximum recording duration in seconds.

#### Returns

Promise that resolves with a MediaFile object or rejects with an error message.

#### MediaFile Object

```typescript
interface MediaFile {
    fullPath: string,   // Full path to the recorded video file
    localURL: string,   // URL that can be used to access the file
    name: string,       // Name of the file
    size: number,       // Size of the file in bytes
    type: string,       // MIME type (e.g., "video/mp4")
    height: number,     // Height of the video in pixels
    width: number       // Width of the video in pixels
}
```

## Permissions

This plugin requires camera and microphone permissions on iOS. The following usage descriptions are automatically added to your app's Info.plist:

- NSCameraUsageDescription: "This app requires access to your camera for video recording."
- NSMicrophoneUsageDescription: "This app requires access to your microphone for video recording."

You may want to customize these messages in your app's config.xml file.

## License

MIT
