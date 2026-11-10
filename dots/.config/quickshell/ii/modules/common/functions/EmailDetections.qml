pragma Singleton
import Quickshell
import "EmailDetections.js" as JS

Singleton {
    function detectAll(bodyRaw, subject) {
        return JS.detectAll(bodyRaw, subject);
    }
}
