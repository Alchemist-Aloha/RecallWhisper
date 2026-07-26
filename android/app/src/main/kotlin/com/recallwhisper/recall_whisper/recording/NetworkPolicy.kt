package com.recallwhisper.recall_whisper.recording

object NetworkPolicy {
    fun requireAllowedUrl(url: String, allowHttp: Boolean): String {
        require(url.startsWith("https://") || allowHttp && url.startsWith("http://")) {
            "HTTPS is required. Enable “Allow insecure HTTP” in Settings for a trusted development network."
        }
        return url
    }
}
