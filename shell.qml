// Mochi, a desktop pet for niri.  Run:  qs -p ~/Projects/desktop-pet
//
// Mochi walks along the bottom of the screen and on top of floating windows,
// jumps up onto them, rides along when a window moves, falls when it closes,
// sleeps when you're away, dances when music plays, and can be picked up and
// thrown. Only Mochi itself takes clicks; the rest of the screen is untouched.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import "sprites.js" as Sprites

ShellRoot {
    id: shell

    PanelWindow {
        id: win
        screen: Quickshell.screens[0]
        // in front of everything by default (also the dock); Settings → Mochi can tuck it under fullscreen apps
        WlrLayershell.layer: Prefs.onTop ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.namespace: "desktop-pet"
        // only takes the keyboard while the ask bar is open (middle-click Mochi)
        WlrLayershell.keyboardFocus: askBar.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore   // the whole screen: the floor is the real bottom edge
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        mask: Region {
            item: pet
            Region { item: askBar.open ? askBar : null }
            Region { item: speech.visible ? speech : null }
        }

        Item {
            id: stage
            anchors.fill: parent

            // ------------------------------------------------ the brain ----
            QtObject {
                id: brain
                readonly property real gravity: 1400
                readonly property real walkSpeed: 46 * Prefs.speed
                readonly property real halfW: Prefs.size * 7

                property real x: stage.width / 2
                property real y: stage.height
                property real vx: 0
                property real vy: 0
                property int facing: 1
                property string state: "fall"
                property real left: 0          // seconds left in this state
                property real t: 0             // animation clock
                property var surfId: null
                property bool edgeDecided: false
                property var jumpTarget: null
                property string bubble: ""

                property var surfaces: []      // [{id, x1, x2, y}], floor included
                property bool idleNap: false   // asleep because the user is away
                property real awakeUntil: -1   // commands keep Mochi up for a while

                property bool listening: false  // the ask bar is open or Mochi is thinking
                property var dockSurf: null     // the rice dock, if it's showing (from rice-dock.json)

                function sleepy() { return idle.isIdle && t > awakeUntil && !listening }

                // pet command: walk | jump | dance | sleep | happy | idle | come
                function command(what) {
                    awakeUntil = t + 30
                    idleNap = false
                    if (state === "drag") return "busy"
                    const grounded = surface(surfId) !== null && state !== "jump" && state !== "fall"
                    if (!grounded && what !== "come") return "in the air"
                    switch (what) {
                    case "walk": enter("walk", rand(3, 6)); break
                    case "dance": enter("dance", rand(4, 8)); break
                    case "sleep": enter("sleep", rand(8, 16)); break
                    case "happy": enter("happy", 1.4); break
                    case "idle": enter("idle", 3); break
                    case "jump": {
                        const tgt = pickJump()
                        if (!tgt) return "nothing to jump on (only floating windows count)"
                        jumpTarget = tgt; enter("crouch", 0.3); break
                    }
                    case "come":
                        // drop in from the top, near the middle of the screen
                        surfId = null; x = stage.width / 2; y = 60; vx = 0; vy = 0
                        enter("fall"); break
                    default: return "unknown: " + what
                    }
                    return state
                }

                function floor() { return { id: "floor", x1: 0, x2: stage.width, y: stage.height } }

                function surface(id) {
                    if (id === null) return null
                    for (const s of surfaces) if (s.id === id) return s
                    return null
                }

                function enter(st, secs) {
                    state = st
                    left = secs === undefined ? 0 : secs
                    edgeDecided = false
                    bubble = st === "sleep" ? "z" : st === "happy" ? "♥" : st === "dance" ? "♪" : ""
                }

                function rand(a, b) { return a + Math.random() * (b - a) }

                function decide() {
                    if (listening) { enter("idle", 1); bubble = "?"; return }
                    if (sleepy()) { idleNap = true; enter("sleep"); return }
                    const r = Math.random()
                    const target = pickJump()
                    if (Prefs.dance && music.playing && r < 0.35) { enter("dance", rand(4, 8)); return }
                    if (Prefs.climb && target && r < 0.55) { jumpTarget = target; enter("crouch", 0.3); return }
                    if (r < 0.80) {
                        if (Math.random() < 0.5) facing = -facing
                        enter("walk", rand(2, 6)); return
                    }
                    const napAt = Prefs.naps === "often" ? 0.85 : Prefs.naps === "never" ? 1.01 : 0.95
                    if (r < napAt) { enter("idle", rand(2, 5)); return }
                    enter("sleep", rand(8, 16))
                }

                // a floating window top within reach, above where Mochi stands
                function pickJump() {
                    const options = surfaces.filter(s => s.id !== surfId && s.y < y - 30 && y - s.y < 450
                                                     && s.x2 - s.x1 > 80)
                    if (!options.length) return null
                    const s = options[Math.floor(Math.random() * options.length)]
                    const tx = Math.max(s.x1 + 30, Math.min(s.x2 - 30, x + rand(-300, 300)))
                    if (Math.abs(tx - x) > 600) return null
                    return { id: s.id, x: tx, y: s.y }
                }

                function launch() {
                    const tgt = jumpTarget
                    jumpTarget = null
                    if (!tgt) { enter("idle", 1); return }
                    const h = (y - tgt.y) + 50
                    vy = -Math.sqrt(2 * gravity * h)
                    const t = (-vy + Math.sqrt(vy * vy + 2 * gravity * (tgt.y - y))) / gravity
                    vx = (tgt.x - x) / t
                    facing = vx >= 0 ? 1 : -1
                    surfId = null
                    enter("jump")
                }

                function fall() { surfId = null; vy = Math.max(vy, 0); enter("fall") }

                function air(dt) {
                    const py = y
                    vy += gravity * dt
                    let nx = x + vx * dt
                    let ny = y + vy * dt
                    if (nx < halfW || nx > stage.width - halfW) {
                        vx = -vx * 0.5
                        nx = Math.max(halfW, Math.min(stage.width - halfW, nx))
                    }
                    if (ny < 40) { ny = 40; vy = Math.abs(vy) * 0.3 }
                    if (ny >= stage.height) {
                        // never fall through the bottom of the screen, even if dropped below it
                        x = nx; y = stage.height; surfId = "floor"; vx = 0; vy = 0
                        enter("land", 0.18)
                        return
                    }
                    if (vy > 0) {
                        // land on the first surface crossed on the way down
                        let best = null
                        for (const s of surfaces) {
                            if (py <= s.y + 0.5 && ny >= s.y && nx >= s.x1 && nx <= s.x2)
                                if (!best || s.y < best.y) best = s
                        }
                        if (best) {
                            x = nx; y = best.y; surfId = best.id
                            vx = 0; vy = 0
                            enter("land", 0.18)
                            return
                        }
                    }
                    x = nx; y = ny
                }

                function tick(dt) {
                    t += dt
                    left -= dt
                    if (state === "drag") return
                    if (state === "jump" || state === "fall") { air(dt); return }

                    const s = surface(surfId)
                    if (!s || x < s.x1 - 2 || x > s.x2 + 2) { fall(); return }
                    y = s.y

                    // naps end on a timer; sleeping because you're away ends when you come back
                    if (state === "sleep" && (idleNap ? !sleepy() : left <= 0)) {
                        idleNap = false; enter("wake", 0.8); return
                    }
                    if (sleepy() && ["sleep", "happy", "wake", "crouch"].indexOf(state) < 0) {
                        idleNap = true; enter("sleep"); return
                    }

                    if (state === "walk") {
                        const nx = x + facing * walkSpeed * dt
                        if (nx < halfW || nx > stage.width - halfW) facing = -facing
                        else if (s.id !== "floor" && (nx < s.x1 + 6 || nx > s.x2 - 6)) {
                            // at a window edge: usually turn back, sometimes hop off
                            if (!edgeDecided) {
                                edgeDecided = true
                                if (Math.random() < 0.6) { facing = -facing; return }
                            }
                            x = nx
                            if (x < s.x1 || x > s.x2) { vx = facing * 60; fall() }
                            return
                        } else {
                            edgeDecided = false
                            x = nx
                        }
                    }
                    if (state === "crouch" && left <= 0) { launch(); return }
                    if (left <= 0 && state !== "crouch") decide()
                }

                // called whenever niri reports new window positions
                function updateSurfaces(list) {
                    const old = surface(surfId)
                    if (dockSurf) list.push(dockSurf)
                    list.push(floor())
                    surfaces = list
                    if (old && old.id !== "floor") {
                        const now = surface(old.id)
                        if (!now) { if (state !== "drag" && state !== "jump") fall() }
                        else { x += now.x1 - old.x1; y = now.y }
                    }
                }

                // visible frame for the current state
                function frame() {
                    const step = Math.floor(t * 6) % 2 ? "stepA" : "stepB"
                    const blink = (t % 3.2) < 0.14
                    switch (state) {
                    case "walk": return Sprites.frame({ feet: step, eyes: blink ? "blink" : "open" })
                    case "jump": return Sprites.frame({ feet: "air", eyes: "happy", mouth: "open" })
                    case "fall": return Sprites.frame({ feet: "air", eyes: "wide", mouth: "o" })
                    case "drag": return Sprites.frame({ feet: "air", eyes: "wide", mouth: "open" })
                    case "land":
                    case "crouch": return Sprites.frame({ squash: true, eyes: "happy" })
                    case "sleep": return Sprites.frame({ squash: Math.floor(t * 0.8) % 2 === 0, feet: "tuck",
                                                         eyes: "closed", mouth: "flat" })
                    case "wake": return Sprites.frame({ eyes: "blink", mouth: "o" })
                    case "happy": return Sprites.frame({ eyes: "happy", mouth: "open", feet: step })
                    case "dance": return Sprites.frame({ eyes: "happy", mouth: Math.floor(t * 4) % 2 ? "open" : "smile",
                                                         feet: step })
                    default: return Sprites.frame({ eyes: blink ? "blink" : "open" })
                    }
                }
            }

            Timer {
                interval: 33; running: true; repeat: true
                onTriggered: brain.tick(interval / 1000)
            }

            // qs -p ~/Projects/desktop-pet ipc call pet act dance
            // qs -p ~/Projects/desktop-pet ipc call pet status
            IpcHandler {
                target: "pet"
                function act(what: string): string { return brain.command(what) }
                // mochi ask "open firefox"  /  mochi talk (opens the ask bar)
                function ask(text: string): string { const r = helper.handle(text); if (r) speech.show(r, 0); return r || "(thinking…)" }
                function talk(): void { askBar.open ? askBar.closeBar() : askBar.openBar() }
                function status(): string {
                    return brain.state + " at " + Math.round(brain.x) + "," + Math.round(brain.y)
                         + " on " + brain.surfId + " (" + (brain.surfaces.length - 1) + " floating windows)"
                }
            }

            // ---------------------------------------------- the world ----
            IdleMonitor { id: idle; timeout: Prefs.napAfter; respectInhibitors: true }

            // the rice dock publishes where its glass pill is; Mochi can stand on it
            FileView {
                path: Quickshell.env("XDG_RUNTIME_DIR") + "/rice-dock.json"
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: {
                    try {
                        const d = JSON.parse(text())
                        brain.dockSurf = d.visible ? { id: "dock", x1: d.x1, x2: d.x2, y: d.y } : null
                    } catch (e) { brain.dockSurf = null }
                }
                onLoadFailed: brain.dockSurf = null
            }

            QtObject {
                id: music
                readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
            }

            Process {
                id: niri
                command: ["sh", "-c", "niri msg --json workspaces && echo ---SPLIT--- && niri msg --json windows"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const parts = text.split("---SPLIT---")
                            const ws = JSON.parse(parts[0])
                            const wins = JSON.parse(parts[1])
                            const active = ws.find(w => w.is_active && w.output === win.screen.name)
                            const list = []
                            for (const w of wins) {
                                const l = w.layout
                                if (!active || w.workspace_id !== active.id || !w.is_floating) continue
                                if (!l || !l.tile_pos_in_workspace_view) continue
                                const x1 = l.tile_pos_in_workspace_view[0] + l.window_offset_in_tile[0]
                                const top = l.tile_pos_in_workspace_view[1] + l.window_offset_in_tile[1]
                                list.push({ id: w.id, x1: x1, x2: x1 + l.window_size[0], y: top })
                            }
                            brain.updateSurfaces(list)
                        } catch (e) {
                            brain.updateSurfaces([])
                        }
                    }
                }
            }
            Timer {
                interval: 350; running: true; repeat: true; triggeredOnStart: true
                onTriggered: if (!niri.running) niri.running = true
            }

            // -------------------------------------------------- the pet ----
            Item {
                id: pet
                width: sprite.width
                height: sprite.height
                readonly property real bob: brain.state === "dance" ? -Math.abs(Math.sin(brain.t * 7)) * 6
                                          : brain.state === "happy" ? -Math.abs(Math.sin(brain.t * 9)) * 10 : 0
                x: Math.round(brain.x - width / 2)
                y: Math.round(brain.y - height + bob)

                PixelSprite {
                    id: sprite
                    rows: brain.frame()
                    px: Prefs.size
                    palette: ({ "o": "#2b2235", "b": "#" + Prefs.body[0], "s": "#" + Prefs.body[1], "e": "#2b2235",
                                "w": "#ffffff", "p": "#f4a3b4", "m": "#c0566b" })
                    flip: brain.facing < 0
                }

                // floating speech bubble: z for sleep, ♥ when petted, ♪ when dancing
                Text {
                    visible: brain.bubble !== ""
                    text: brain.bubble === "z" ? (Math.floor(brain.t) % 2 ? "z" : "Z") : brain.bubble
                    color: brain.bubble === "♥" ? "#f4a3b4" : "#fbeadb"
                    style: Text.Outline; styleColor: "#2b2235"
                    font.pixelSize: 16; font.bold: true
                    x: parent.width * 0.7 + Math.sin(brain.t * 3) * 3
                    y: -14 - (brain.t * 12) % 10
                }

                MouseArea {
                    id: grab
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    property point start
                    property point last
                    property real lastT
                    property real vX: 0
                    property real vY: 0
                    property bool moved: false
                    property string before: "idle"
                    property var beforeSurf: null

                    onPressed: mouse => {
                        if (mouse.button === Qt.MiddleButton) { if (Prefs.ask) askBar.open ? askBar.closeBar() : askBar.openBar(); return }
                        start = mapToItem(stage, mouse.x, mouse.y)
                        last = start; lastT = Date.now(); moved = false
                        before = brain.state; beforeSurf = brain.surfId
                    }
                    onPositionChanged: mouse => {
                        if (!(mouse.buttons & Qt.LeftButton)) return
                        const p = mapToItem(stage, mouse.x, mouse.y)
                        if (!moved && Math.hypot(p.x - start.x, p.y - start.y) < 5) return
                        p.y = Math.min(p.y, stage.height)
                        if (!moved) { moved = true; brain.surfId = null; brain.enter("drag"); brain.bubble = "!" }
                        const now = Date.now()
                        const dt = Math.max(1, now - lastT) / 1000
                        vX = vX * 0.5 + 0.5 * (p.x - last.x) / dt
                        vY = vY * 0.5 + 0.5 * (p.y - last.y) / dt
                        brain.x = brain.x + (p.x - last.x)
                        brain.y = brain.y + (p.y - last.y)
                        last = p; lastT = now
                    }
                    onReleased: mouse => {
                        if (mouse.button === Qt.MiddleButton) return
                        if (moved) {
                            // throw!
                            brain.vx = Math.max(-1500, Math.min(1500, vX))
                            brain.vy = Math.max(-1500, Math.min(1500, vY))
                            brain.surfId = null
                            brain.enter("fall")
                        } else {
                            // a pat: wake up or be happy
                            brain.surfId = beforeSurf
                            brain.enter(before === "sleep" ? "wake" : "happy", before === "sleep" ? 0.8 : 1.4)
                        }
                        vX = 0; vY = 0
                    }
                }
            }
        
            // ------------------------------------------- ask bar + speech ----
            Helper {
                id: helper
                brain: brain
                onReply: (text, secs) => speech.show(text, secs)
                onThinking: (on) => { brain.listening = on || askBar.open; if (on) speech.show("…", 0) }
            }

            // the text bar: middle-click Mochi to open, Enter to send, Esc to close
            Rectangle {
                id: askBar
                property bool open: false
                function openBar() {
                    open = true
                    brain.listening = true; brain.awakeUntil = brain.t + 60
                    if (brain.state === "sleep") brain.enter("wake", 0.8)
                    else if (["walk", "dance", "idle", "happy"].indexOf(brain.state) >= 0) { brain.enter("idle", 1); brain.bubble = "?" }
                    input.text = ""
                    focusTimer.start()
                }
                function closeBar() { open = false; input.focus = false; brain.listening = helper.ai.running }
                Timer { id: focusTimer; interval: 60; onTriggered: input.forceActiveFocus() }

                width: open ? 360 : 0
                height: open ? 44 : 0
                visible: open
                x: Math.max(8, Math.min(stage.width - 368, pet.x + pet.width / 2 - 180))
                y: Math.max(8, pet.y - 58)
                radius: 22
                color: "#e62b2235"
                border.width: 1.5; border.color: "#66fbeadb"
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: "Ask Mochi… open firefox · screenshot · search cats"
                    color: "#99fbeadb"; font.pixelSize: 14
                }
                TextInput {
                    id: input
                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#fbeadb"; selectionColor: "#f4a3b4"; selectedTextColor: "#2b2235"
                    font.pixelSize: 14
                    clip: true
                    Keys.onEscapePressed: askBar.closeBar()
                    onAccepted: {
                        const q = text
                        askBar.closeBar()
                        const r = helper.handle(q)
                        if (r) { speech.show(r, 0); brain.enter("happy", 1.2) }
                    }
                    onActiveFocusChanged: if (!activeFocus && askBar.open) closeLater.restart()
                }
                // clicking somewhere else closes the bar
                Timer { id: closeLater; interval: 250; onTriggered: if (!input.activeFocus) askBar.closeBar() }
            }

            // Mochi's speech bubble for replies (click to dismiss)
            Rectangle {
                id: speech
                property string msg: ""
                function show(t, secs) {
                    msg = t
                    visible = true
                    hideTimer.interval = (secs > 0 ? secs : Math.min(12, 3 + t.length / 18)) * 1000
                    if (t !== "…") hideTimer.restart(); else hideTimer.stop()
                }
                visible: false
                width: Math.min(340, label.implicitWidth + 28)
                height: label.implicitHeight + 20
                x: Math.max(8, Math.min(stage.width - width - 8, pet.x + pet.width / 2 - width / 2))
                y: Math.max(8, pet.y - height - (askBar.open ? 66 : 14))
                radius: 16
                color: "#f2fbeadb"
                border.width: 2; border.color: "#2b2235"
                Text {
                    id: label
                    x: 14; y: 10
                    width: Math.min(312, implicitWidth)
                    text: speech.msg === "…" ? ["·", "· ·", "· · ·"][Math.floor(brain.t * 3) % 3] : speech.msg
                    wrapMode: Text.WordWrap
                    color: "#2b2235"; font.pixelSize: 13; font.bold: true
                    onTextChanged: width = Math.min(312, implicitWidth)
                }
                Rectangle {        // the little tail pointing at Mochi
                    width: 12; height: 12; rotation: 45
                    color: parent.color; border.width: 2; border.color: "#2b2235"
                    x: Math.max(10, Math.min(parent.width - 22, pet.x + pet.width / 2 - parent.x - 6))
                    y: parent.height - 7; z: -1
                }
                Timer { id: hideTimer; onTriggered: speech.visible = false }
                MouseArea { anchors.fill: parent; onClicked: speech.visible = false }
            }
}
    }
}
