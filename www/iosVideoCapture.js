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
            options.ratio = 3/4;
        }
        var params = {
            elementId: elementId,
            options: options
        };
        exec(successCallback, errorCallback, 'iOSVideoCapture', 'startPreview', [params]);
    },
    
    /**
     * Start recording a video with specified options
     * @param {Object} options - Recording options
     * @param {number} [options.maxDuration=12] - Maximum duration in seconds
     * @param {string} [options.targetFileName] - Desired filename for the recorded video (without extension)
     * @param {Function} successCallback - Callback function to be called when video recording starts
     * @param {Function} errorCallback - Error callback
     */
    startRecording: function(options, successCallback, errorCallback) {
        // Handle backwards compatibility with older API which took maxDuration directly
        var params = {};
        if (typeof options === 'number') {
            params.maxDuration = options || 12;
        } else if (typeof options === 'object') {
            params = options;
            // Set default maxDuration if not provided
            if (typeof params.maxDuration === 'undefined') {
                params.maxDuration = 12;
            }
        } else {
            params.maxDuration = 12;
        }
        
        exec(successCallback, errorCallback, 'iOSVideoCapture', 'startRecording', [params]);
    },
    
    /**
     * Stop recording and get the recorded video file
     * @param {Function} successCallback - Callback function to be called with the recorded MediaFile
     * @param {Function} errorCallback - Error callback
     */
    stopRecording: function(successCallback, errorCallback) {
        exec(function(mediaFile) {
            successCallback(mediaFile);
        }, errorCallback, 'iOSVideoCapture', 'stopRecording', []);
    },
    
    /**
     * Stop the camera preview and release resources
     * @param {Function} successCallback - Success callback
     * @param {Function} errorCallback - Error callback 
     */
    stopPreview: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'iOSVideoCapture', 'stopPreview', []);
    },
    
    /**
     * Set the flash/torch mode for the camera
     * @param {string} mode - Flash mode ('off', 'on', or 'auto')
     * @param {Function} successCallback - Success callback
     * @param {Function} errorCallback - Error callback
     */
    setFlashMode: function(mode, successCallback, errorCallback) {
        // Validate mode parameter
        const validModes = ['off', 'on', 'auto'];
        if (typeof mode !== 'string' || !validModes.includes(mode.toLowerCase())) {
            if (errorCallback) {
                errorCallback("Invalid flash mode. Must be 'off', 'on', or 'auto'");
            }
            return;
        }
        
        exec(successCallback, errorCallback, 'iOSVideoCapture', 'setFlashMode', [mode.toLowerCase()]);
    }
};

module.exports = iOSVideoCapture;
