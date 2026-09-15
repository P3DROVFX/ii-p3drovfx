pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Synchronous, warning-free existence check. preload makes the probe read
    // (stat) immediately when the path is assigned; printErrors: false keeps a
    // missing target from logging a declaration like Image/FileView would do.
    FileView {
        id: existenceProbe
        preload: true
        printErrors: false
    }

    /**
     * @param {string} path file system path to test
     * @returns {boolean} true if the path exists and can be read
     */
    function fileExists(path) {
        if (typeof path !== "string" || path.length === 0) return false;
        existenceProbe.path = path;
        return existenceProbe.loaded;
    }

    /**
     * Trims the File protocol off the input string
     * @param {string} str
     * @returns {string}
     */
    function trimFileProtocol(str) {
        let s = str;
        if (typeof s !== "string") s = str.toString(); // Convert to string if it's an url or whatever
        if (s.startsWith("file://")) {
            s = s.slice(7);
            if (s.startsWith("localhost/")) {
                s = s.slice(9);
            }
        } else if (s.startsWith("file:/")) {
            s = s.slice(5);
        } else if (s.startsWith("file:")) {
            s = s.slice(5);
        }
        return s;
    }


    /**
     * Extracts the file name from a file path
     * @param {string} str
     * @returns {string}
     */
    function fileNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        return trimmed.split(/[\\/]/).pop();
    }

    /**
     * Extracts the folder name from a directory path
     * @param {string} str
     * @returns {string}
     */
    function folderNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        // Remove trailing slash if present
        const noTrailing = trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
        if (!noTrailing) return "";
        return noTrailing.split(/[\\/]/).pop();
    }

    /**
     * Removes the file extension from a file path or name
     * @param {string} str
     * @returns {string}
     */
    function trimFileExt(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const lastDot = trimmed.lastIndexOf(".");
        if (lastDot > -1 && lastDot > trimmed.lastIndexOf("/")) {
            return trimmed.slice(0, lastDot);
        }
        return trimmed;
    }

    /**
     * Returns the parent directory of a given file path
     * @param {string} str
     * @returns {string}
     */
    function parentDirectory(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str).replace(/\/+$/, "");
        if (trimmed === "" || trimmed === "/") return "/";
        const parts = trimmed.split("/");
        if (parts.length <= 1) return "/";
        parts.pop();
        const joined = parts.join("/");
        return joined === "" ? "/" : joined;
    }
}
