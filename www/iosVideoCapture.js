/**
 * iOS Video Capture Plugin
 * A Cordova plugin for iOS video capture using modern Swift and AVFoundation
 */

var exec = require('cordova/exec');

var iOSVideoCapture = {
    /**
     * Start camera preview in the specified HTML element
     * @param {string} elementId - ID of the HTML element where the preview should be displayed
     * @param {Object} options - Optional settings for the preview
     * @param {number} [options.ratio=4/3] - Aspect ratio of the camera preview (width/height)
     * @param {Function} successCallback - Success callback
     * @param {Function} errorCallback - Error callback
     */
    startPreview: function(elementId, options, successCallback, errorCallback) {
        options = options || {};
        // Default aspect ratio is 4:3 if not specified
        if (typeof options.ratio === 'undefined') {
            options.ratio = 9/16;
        }
        var params = {
            elementId: elementId,
            options: options
        };
        exec(successCallback, errorCallback, 'iOSVideoCapture', 'startPreview', [params]);
    },
    
    /**
     * Start recording a video with specified maximum duration
     * @param {number} maxDuration - Maximum duration in seconds
     * @param {Function} successCallback - Callback function to be called when video recording starts
     * @param {Function} errorCallback - Error callback
     */
    startRecording: function(maxDuration, successCallback, errorCallback) {
        var params = {
            maxDuration: maxDuration || 12
        };
        exec(successCallback, errorCallback, 'iOSVideoCapture', 'startRecording', [params]);
    },
    
    /**
     * Stop recording and get the recorded video file
     * @param {Function} successCallback - Callback function to be called with the recorded MediaFile
     * @param {Function} errorCallback - Error callback
     */
    stopRecording: function(successCallback, errorCallback) {
        exec(function(mediaFile) {
            successCallback(mediaFile.fullPath);
        }, errorCallback, 'iOSVideoCapture', 'stopRecording', []);
    },
    
    /**
     * Stop the camera preview and release resources
     * @param {Function} successCallback - Success callback
     * @param {Function} errorCallback - Error callback 
     */
    stopPreview: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'iOSVideoCapture', 'stopPreview', []);
    }
};

module.exports = iOSVideoCapture;
