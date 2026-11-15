import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// What Mochi does with what you type: open apps, take screenshots, search the
// web, open sites, change the volume, control music, lock the screen, tell the
// time, do tricks. Anything else goes to the local AI (Ollama).
QtObject {
    id: h
    property var brain
    signal reply(string text, real secs)
    signal thinking(bool on)

    readonly property string home: Quickshell.env("HOME")
    readonly property string model: Quickshell.env("AI_MODEL") || "qwen2.5-coder:3b"
    readonly property string host: Quickshell.env("AI_HOST") || "http://127.0.0.1:11434"

    function run(args) { Quickshell.execDetached(args) }
    function sh(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }
    function say(t, secs) { reply(t, secs || Math.min(12, 3 + t.length / 18)) }

    // best desktop app for a name like "firefox", "files", "music"
    function findApp(q) {
        q = q.toLowerCase().trim()
        const aliases = { "files": "thunar", "file manager": "thunar", "terminal": "kitty", "browser": "firefox",
                          "music": "spotify", "notes": "obsidian", "settings": "rice settings" }
        if (aliases[q]) q = aliases[q]
        let best = null, score = 0
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue
            const name = (e.name || "").toLowerCase(), id = (e.id || "").toLowerCase()
            const extra = ((e.genericName || "") + " " + (e.keywords || []).join(" ")).toLowerCase()
            let s = 0
            if (name === q || id === q) s = 100
            else if (name.startsWith(q) || id.startsWith(q)) s = 80
            else if (name.includes(q) || id.includes(q)) s = 60
            else if (extra.includes(q)) s = 30
            if (s > score) { score = s; best = e }
        }
        return best
    }

    function looksLikeUrl(t) { return /^(https?:\/\/)?[\w-]+(\.[\w-]+)+(\/\S*)?$/i.test(t) }

    // returns what Mochi says right away
    function handle(raw) {
        const text = raw.trim()
        const t = text.toLowerCase().replace(/[.!?]+$/, "").replace(/^(hey mochi,?|mochi,?|please|can you|could you)\s+/i, "")
        let m
        if (!t) return ""

        // tricks
        const tricks = { "dance": "dance", "sleep": "sleep", "nap": "sleep", "jump": "jump", "walk": "walk",
                         "come here": "come", "come": "come", "happy": "happy", "sit": "idle", "stay": "idle" }
        if (tricks[t]) { brain.command(tricks[t]); return t === "dance" ? "♪ ♪" : "ok!" }

        if (t === "help" || t === "what can you do")
            return "Try: open firefox · screenshot · screenshot window · search cats · youtube.com · volume 40 · pause · next · lock · time · dance. Or ask me anything!"

        // screenshots (Mochi's bar closes first, so it's not in the picture)
        if ((m = t.match(/^(take (a )?)?screenshot( of)?( the| this| a| an| my)?\s*(.*)$/)) || (m = t.match(/^(screen ?shot|snap|capture)\s*(.*)$/))) {
            const what = (m[5] !== undefined ? m[5] : m[2] || "").trim()
            const act = /window/.test(what) ? "screenshot-window"
                      : /(screen|everything|whole|full|all)/.test(what) ? "screenshot-screen" : "screenshot"
            sh("sleep 0.35; niri msg action " + act)
            return act === "screenshot" ? "Pick an area! (Space or Enter to save)" : "Snap! Saved to Pictures/Screenshots and copied."
        }

        // web
        if ((m = t.match(/^(search( for| the web for)?|google|look up|find)\s+(.+)$/))) {
            run(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(text.replace(/^\S+(\s+(for|the web for))?\s+/i, ""))])
            return "Searching for " + m[3] + "…"
        }
        if ((m = t.match(/^(open |go to |visit )?(\S+)$/)) && looksLikeUrl(m[2])) {
            const url = /^https?:/.test(m[2]) ? m[2] : "https://" + m[2]
            run(["xdg-open", url])
            return "Opening " + m[2] + "!"
        }

        // volume and music
        if ((m = t.match(/^(set )?(the )?volume( to)?\s+(\d{1,3})%?$/))) {
            sh("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + Math.min(100, parseInt(m[4])) + "%")
            return "Volume " + Math.min(100, parseInt(m[4])) + "%"
        }
        if (/^(volume up|louder|turn it up)$/.test(t)) { sh("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 10%+"); return "Louder!" }
        if (/^(volume down|quieter|turn it down)$/.test(t)) { sh("wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%-"); return "Shh…" }
        if (/^(mute|unmute)$/.test(t)) { sh("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"); return t === "mute" ? "Muted." : "Sound's back!" }
        const p = Mpris.players.values.find(x => x.isPlaying) || Mpris.players.values[0]
        if (/^(pause|play|resume|stop( the)? music|play music|pause music)$/.test(t)) {
            if (!p) return "Nothing's playing."
            p.togglePlaying(); return p.isPlaying ? "Paused." : "♪ Playing!"
        }
        if (/^(next|skip|next song|skip song)$/.test(t)) { if (!p) return "Nothing's playing."; p.next(); return "Next one! ♪" }
        if (/^(previous|back|last song|previous song)$/.test(t)) { if (!p) return "Nothing's playing."; p.previous(); return "Going back ♪" }
        if (/^(what('s| is) (playing|this song)|song)$/.test(t)) {
            if (!p || !p.trackTitle) return "Nothing's playing."
            return "♪ " + p.trackTitle + (p.trackArtist ? " by " + p.trackArtist : "")
        }

        // system
        if (/^(lock|lock( the)? screen)$/.test(t)) { sh("sleep 0.3; loginctl lock-session"); return "Locking! Bye for now." }
        if (/^(what('s| is) the )?time$|^what time is it$/.test(t)) return "It's " + Qt.formatTime(new Date(), "h:mm AP") + "."
        if (/^(what('s| is) the )?(date|day)( today)?$|^what day is it$/.test(t)) return "It's " + Qt.formatDate(new Date(), "dddd, d MMMM") + "."
        if (/^(open )?(rice )?settings$/.test(t)) { run([home + "/.local/bin/rice", "settings"]); return "Opening settings!" }

        // apps: "open firefox", "launch spotify", or just "firefox"
        m = t.match(/^(open|launch|start|run)\s+(.+)$/)
        const name = m ? m[2].replace(/^(the|my)\s+/, "").replace(/\s+app$/, "") : t
        const app = findApp(name)
        if (app && (m || name.split(" ").length <= 2)) {
            app.execute()
            return "Opening " + app.name + "!"
        }
        if (m) return "I couldn't find an app called \"" + name + "\"."

        // anything else: ask the local AI (if that's on in Settings → Mochi)
        if (!Prefs.ai) return "I only know commands. Try: help"
        askAI(text)
        return ""
    }

    // ── the local AI ──
    property string pending: ""
    property bool retried: false
    function askAI(q) {
        pending = q; retried = false
        thinking(true)
        ai.start()
    }
    property Process ai: Process {
        function start() {
            const body = JSON.stringify({
                model: h.model, stream: false, keep_alive: "10m",
                options: { num_predict: 90, temperature: 0.7 },
                system: "You are Mochi, a tiny, cheerful pixel creature who lives on the user's Linux desktop. "
                      + "Answer in one or two short, friendly sentences. Plain text only, no markdown.",
                prompt: h.pending
            })
            command = ["curl", "-s", "--max-time", "90", h.host + "/api/generate", "-d", body]
            running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let out = ""
                try { out = (JSON.parse(text).response || "").trim() } catch (e) { out = "" }
                if (out) { h.thinking(false); h.say(out) }
                else h.failed()
            }
        }
    }
    function failed() {
        if (!retried) {
            // Ollama isn't running yet: start it and try once more
            retried = true
            sh("pgrep -x ollama >/dev/null || (setsid -f ollama serve >/dev/null 2>&1)")
            retryTimer.start()
            return
        }
        thinking(false)
        say("My brain isn't answering… is Ollama installed? (try the ai command)")
    }
    property Timer retryTimer: Timer { interval: 2500; onTriggered: h.ai.start() }
}
