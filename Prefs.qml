pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mochi's settings: the "mochi" section of ~/.config/rice/settings.json
// (Settings → Mochi in the rice). Without that file Mochi uses the defaults.
// Changes apply live.
Singleton {
    id: p
    property var m: ({})
    property var theme: ({})
    function get(k, d) { return m[k] === undefined || m[k] === null ? d : m[k] }

    readonly property int size: get("size", 3)                  // pixels per sprite pixel
    readonly property real speed: get("speed", 1.0)             // walking speed
    readonly property int napAfter: get("nap_after", 120)       // seconds without input before sleeping
    readonly property string naps: get("naps", "sometimes")     // random naps: often | sometimes | never
    readonly property bool dance: get("dance", true)            // dance to music
    readonly property bool climb: get("climb", true)            // jump onto windows and the dock
    readonly property bool ask: get("ask", true)                // middle-click opens the ask bar
    readonly property bool ai: get("ai", true)                  // answer other questions with the local AI
    readonly property bool onTop: get("on_top", true)           // above everything (even fullscreen apps)
    readonly property string colour: get("colour", "classic")

    // body colours: [main, shade]
    readonly property var colours: ({
        classic: ["fbeadb", "e6c3a8"], peach: ["ffd3b8", "f0a98a"], mint: ["d4f5e0", "a6dcbc"],
        lavender: ["e6dcff", "c2b2ee"], sky: ["d6ecff", "a9cdf0"], lemon: ["fff3b8", "eed98a"],
        shadow: ["5a5470", "433d58"]
    })
    readonly property var body: {
        if (colour === "theme" && theme.accent) {
            const a = theme.accent.slice(0, 6)
            return [mix(a, "ffffff", 0.55), mix(a, "ffffff", 0.25)]
        }
        return colours[colour] || colours.classic
    }
    function mix(a, b, t) {
        const pa = [0, 2, 4].map(i => parseInt(a.slice(i, i + 2), 16)), pb = [0, 2, 4].map(i => parseInt(b.slice(i, i + 2), 16))
        return pa.map((v, i) => Math.round(v + (pb[i] - v) * t).toString(16).padStart(2, "0")).join("")
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/rice/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { p.m = JSON.parse(text()).mochi || {} } catch (e) {} }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/rice/current/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { p.theme = JSON.parse(text()) } catch (e) {} }
    }
}
