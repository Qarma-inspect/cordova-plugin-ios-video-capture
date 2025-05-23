/**
 * iOS Video Capture Plugin
 * A Cordova plugin for iOS video capture using modern Swift and AVFoundation
 */

var exec = require('cordova/exec');

var iOSVideoCapture = {
    /**
     * Start recording a video with specified maximum duration
     * @param {number} maxDuration - Maximum duration in seconds
     * @returns {Promise<MediaFile>} - Promise resolving to a MediaFile object or rejecting with an error
     */
    startRecord: function(maxDuration) {
        return new Promise(function(resolve, reject) {
            exec(
                function(mediaFile) {
                    resolve(mediaFile);
                },
                function(error) {
                    reject(error);
                },
                'iOSVideoCapture',
                'startRecord',
                [maxDuration]
            );
        });
    }
};

module.exports = iOSVideoCapture;
