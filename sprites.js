.pragma library

// Mochi: a 16 x 14 pixel creature. Each frame is built from the base body
// and patched for eyes, mouth and feet. Letters map to colours in PALETTE.

var W = 16
var H = 14

var PALETTE = {
    "o": "#2b2235", // outline
    "b": "#fbeadb", // body
    "s": "#e6c3a8", // shade
    "e": "#2b2235", // eye
    "w": "#ffffff", // eye shine
    "p": "#f4a3b4", // cheek
    "m": "#c0566b"  // mouth
}

var BASE = [
    "...oo......oo...",
    "..obbo....obbo..",
    "..obbboooobbbo..",
    ".obbbbbbbbbbbbo.",
    "obbbbbbbbbbbbbbo",
    "obbbbbbbbbbbbbbo",
    "obbbbbbbbbbbbbbo",
    "obppbbbbbbbbppbo",
    "obbbbbbbbbbbbbbo",
    "osbbbbbbbbbbbbso",
    ".ossbbbbbbbbsso.",
    "..oossssssssoo..",
    "................",
    "................"
]

var FEET = {
    stand: ["...oso....oso...", "...oo......oo..."],
    stepA: ["...oso....oso...", "...........oo..."],
    stepB: ["...oso....oso...", "...oo..........."],
    air:   ["..oso......oso..", "................"],
    tuck:  ["...oo......oo...", "................"]
}

function set(g, r, c, ch) {
    if (r < 0 || r >= H || c < 0 || c >= W) return
    g[r] = g[r].substring(0, c) + ch + g[r].substring(c + 1)
}

// opts: eyes (open|blink|happy|closed|wide), mouth (smile|open|o|flat), feet, squash (bool)
function frame(opts) {
    var g = BASE.slice()
    var f = FEET[opts.feet || "stand"]
    g[12] = f[0]
    g[13] = f[1]

    var eyes = opts.eyes || "open"
    var cols = [4, 11]
    for (var i = 0; i < 2; i++) {
        var c = cols[i]
        if (eyes === "open") {
            set(g, 5, c, "e"); set(g, 6, c, "e")
        } else if (eyes === "wide") {
            set(g, 4, c, "e"); set(g, 5, c, "e"); set(g, 6, c, "e")
            set(g, 5, c + (i ? -1 : 1), "w")
        } else if (eyes === "blink" || eyes === "closed") {
            set(g, 6, c - 1, "e"); set(g, 6, c, "e"); set(g, 6, c + 1, "e")
        } else if (eyes === "happy") {
            set(g, 5, c, "e"); set(g, 6, c - 1, "e"); set(g, 6, c + 1, "e")
        }
    }

    var mouth = opts.mouth || "smile"
    if (mouth === "smile") { set(g, 7, 7, "m"); set(g, 7, 8, "m") }
    else if (mouth === "open") { set(g, 7, 7, "m"); set(g, 7, 8, "m"); set(g, 8, 7, "m"); set(g, 8, 8, "m") }
    else if (mouth === "o") { set(g, 8, 7, "m"); set(g, 8, 8, "m") }
    else if (mouth === "flat") { set(g, 8, 6, "o"); set(g, 8, 7, "o"); set(g, 8, 8, "o"); set(g, 8, 9, "o") }

    if (opts.squash) {
        // hide the feet: the body sits two rows lower, flat on the ground
        g = ["................", "................"].concat(g.slice(0, 12))
    }
    return g
}
