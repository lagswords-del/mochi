import QtQuick
import "sprites.js" as Sprites

// Draws one pixel-art frame, scaled up with hard edges.
Canvas {
    id: c
    property var rows: Sprites.frame({})
    property int px: 3
    property bool flip: false

    width: Sprites.W * px
    height: Sprites.H * px
    renderStrategy: Canvas.Cooperative

    property string drawn: ""
    // the brain hands over a new array every tick; repaint only when it differs
    onRowsChanged: {
        const key = rows.join("")
        if (key !== drawn) { drawn = key; requestPaint() }
    }
    onFlipChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        for (let r = 0; r < rows.length; r++) {
            const line = rows[r]
            for (let i = 0; i < line.length; i++) {
                const col = Sprites.PALETTE[line[i]]
                if (!col) continue
                const x = flip ? (Sprites.W - 1 - i) : i
                ctx.fillStyle = col
                ctx.fillRect(x * px, r * px, px, px)
            }
        }
    }
}
