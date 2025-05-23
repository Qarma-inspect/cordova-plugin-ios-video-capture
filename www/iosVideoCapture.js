/**
 * iOS Video Capture Plugin
 * A Cordova plugin for iOS video capture using modern Swift and AVFoundation
 */

var exec = require('cordova/exec');

var iOSVideoCapture = {
    /**
     * Start recording a video with specified maximum duration
     * @param {number} maxDuration - Maximum duration in seconds
     * @param {Function} successCallback - Callback function to be called when video recording is successful
     * @param {Function} errorCallback - Callback function to be called when video recording fails
     */
    startRecord: function(maxDuration, successCallback, errorCallback) {
        var win = function(mediaFile) {
            successCallback(mediaFile);
        };
        exec(win, errorCallback, 'iOSVideoCapture', 'startRecord', [{maxDuration: maxDuration}]);
    }
};

module.exports = iOSVideoCapture;
