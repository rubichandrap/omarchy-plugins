import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Desktop-background audio visualizer — a port of cliamp's "Mosaic" mode.
// The grid never scrolls: each cell is wired to one spectrum band and has a
// personal ignition threshold, so loud passages light up many cells at once
// while quiet passages light only the most sensitive ones — the speckled,
// gradually-saturating pattern. Runs along the bottom edge plus the left and
// right edges (a "U" frame) on the layer-shell bottom layer, above the
// wallpaper and below windows.
Item {
  id: root

  // ---- knobs: edit freely, then `omarchy restart shell` ----
  property int columns: 44        // spectrum bands (match cava's `bars`)
  property real rows: 4           // cell rows per strip (2.5 = two full rows + a half row)
  property real tileFill: 0.62    // lit cell size as a fraction of its slot
  property real gain: 0.85        // band sensitivity multiplier
  property real decay: 0.94       // per-frame brightness decay (used only when binary: false)
  property bool binary: true      // cells snap on/off 0-1 without decay
  property real tileAlpha: 0.52   // global opacity multiplier
  property real rowFade: 0.55     // how much dimmer the inner row gets
  property real vignette: 0.30    // soft shadow behind the strips for contrast
  property bool bottomStrip: false // bottom edge strip
  property bool topStrip: false   // top edge strip
  property bool leftStrip: true   // left edge strip
  property bool rightStrip: true  // right edge strip
  property int idleFadeout: 1000  // ms after last audible frame until fade-out
  property int fadeMs: 0          // strip show/hide fade duration; 0 = instant
  property int cellMs: 0          // per-cell opacity/size transition; 0 = instant jump
  property real marginTop: -20      // per-edge strip offset; negative pushes the strip
  property real marginBottom: -20   // off-screen, so the outer tiles get cut at the edge
  property real marginLeft: -20
  property real marginRight: -20
  property real endInsetLeft: 100   // blank this much of the left end of the top/bottom strips
  property real endInsetRight: 100  // same for the right end
  property real endInsetTop: 100    // blank this much of the top end of the left/right strips
  property real endInsetBottom: 100 // same for the bottom end
  property real sideShade: 0.5      // darkening at the left/right screen edges (0 = off)
  property real sideShadeWidth: 280 // how far that shade reaches from each edge
  // ----------------------------------------------------------

  property var cellValues: []
  property var cellBand: []
  property var cellThreshold: []
  property var sideValues: []
  property var sideBand: []
  property var sideThreshold: []
  property int sideCount: 0
  property bool active: false

  // ---- geometry: pitch follows the screen so the bottom strip is full width
  function boardW() {
    return Quickshell.screens.length ? Quickshell.screens[0].width : 1536
  }
  function boardH() {
    return Quickshell.screens.length ? Quickshell.screens[0].height : 960
  }
  function cellPitch() {
    return boardW() / columns
  }
  function tileSize() {
    return cellPitch() * tileFill
  }
  function stripExtent() {
    return tileSize() + (Math.ceil(rows) - 1) * cellPitch()
  }

  // Stable per-cell pseudo-random value in [0,1).
  function hash(a, b) {
    var x = Math.sin(a * 127.1 + b * 311.7) * 43758.5453
    return x - Math.floor(x)
  }

  function clampBand(b) {
    if (b < 0) return 0
    if (b >= columns) return columns - 1
    return b
  }

  // Per-cell band assignment + ignition threshold in [0.04, 0.78], mirroring
  // cliamp's mosaic driver. Bottom strip: edge row = bass, inner rows toward
  // treble. Side strips: bands spread bottom (bass) to top (treble) along the
  // edge. Runs at startup; after changing columns/rows, restart the shell.
  function buildGrid() {
    var tile = tileSize()
    var pitch = cellPitch()
    var n = Math.max(1, Math.floor((boardH() - tile) / pitch) + 1)
    sideCount = n

    var b1 = []
    var t1 = []
    for (var r = 0; r < Math.ceil(rows); r++) {
      var base = rows > 1 ? Math.round(r * (columns - 1) / (rows - 1)) : 0
      for (var c = 0; c < columns; c++) {
        b1.push(clampBand(base + Math.floor(hash(c * 7.3 + 0.5, r * 3.7 + 1.1) * 5) - 2))
        t1.push(0.04 + hash(c * 1.7 + 0.31, r * 2.9 + 0.77) * 0.74)
      }
    }
    cellBand = b1
    cellThreshold = t1
    var v1 = []
    for (var i = 0; i < Math.ceil(rows) * columns; i++) v1.push(0)
    cellValues = v1

    var b2 = []
    var t2 = []
    for (var cc = 0; cc < n; cc++) {
      var base2 = n > 1 ? Math.round(cc * (columns - 1) / (n - 1)) : 0
      for (var rr = 0; rr < Math.ceil(rows); rr++) {
        b2.push(clampBand(base2 + Math.floor(hash(cc * 5.9 + 100.5, rr * 4.3 + 77.1) * 5) - 2))
        t2.push(0.04 + hash(cc * 2.3 + 100.31, rr * 3.1 + 77.77) * 0.74)
      }
    }
    sideBand = b2
    sideThreshold = t2
    var v2 = []
    for (var j = 0; j < n * Math.ceil(rows); j++) v2.push(0)
    sideValues = v2
  }

  Component.onCompleted: buildGrid()

  // One ignite step over a grid; returns the new value array. With binary on,
  // a cell is simply lit (1) while its band beats its threshold, else off (0).
  // With binary off it keeps cliamp's gradual decay instead.
  function stepGrid(prev, bands, gridBand, gridThreshold) {
    var next = []
    for (var i = 0; i < gridBand.length; i++) {
      var b = bands[gridBand[i]]
      var lvl = (b === undefined ? 0 : b) * gain
      var val
      if (binary) {
        val = lvl > gridThreshold[i] ? 1 : 0
      } else {
        val = i < prev.length ? prev[i] * decay : 0
        if (lvl > gridThreshold[i]) {
          var ignited = lvl > 1.05 ? 1.05 : lvl
          if (ignited > val) val = ignited
        }
        if (val < 0.001) val = 0
      }
      next.push(val)
    }
    return next
  }

  // Brightness tiers — cliamp's mosaicLevelFor: dim tiers shrink the cell,
  // hot tiers lighten the accent in place.
  function tierAlpha(v) {
    if (v >= 0.65) return 1.00
    if (v >= 0.45) return 0.95
    if (v >= 0.28) return 0.80
    if (v >= 0.15) return 0.62
    if (v >= 0.05) return 0.42
    return 0
  }
  function tierSize(v) {
    if (v >= 0.45) return 1.00
    if (v >= 0.28) return 0.85
    if (v >= 0.15) return 0.68
    return 0.50
  }
  // Fractional `rows`: the innermost row shrinks to the fractional part
  // (rows 2.5 = two full rows + a half-size third row).
  function rowScale(index) {
    var frac = rows - Math.floor(rows)
    return (frac > 0 && index >= Math.floor(rows)) ? frac : 1
  }
  function tierColor(v) {
    // Binary cells are always fully lit, so they keep the plain theme accent
    // — no tier lightening, no white drift.
    if (binary) return Color.accent
    // Hue stays inside the theme accent family: hot tiers are the accent
    // lightened in place, never shifted to another hue (no gray, no white).
    // Same trick bjarneo's music-wallpaper uses: min(1, accent * 1.3 + 0.15).
    if (v >= 0.85) {
      return Qt.rgba(Math.min(1, Color.accent.r * 1.5 + 0.25),
                     Math.min(1, Color.accent.g * 1.5 + 0.25),
                     Math.min(1, Color.accent.b * 1.5 + 0.25), 1)
    }
    if (v >= 0.65) {
      return Qt.rgba(Math.min(1, Color.accent.r * 1.3 + 0.15),
                     Math.min(1, Color.accent.g * 1.3 + 0.15),
                     Math.min(1, Color.accent.b * 1.3 + 0.15), 1)
    }
    return Color.accent
  }
  function cellOpacity(v, row) {
    return tileAlpha * tierAlpha(v) * (1 - rowFade * row / Math.max(1, Math.ceil(rows) - 1))
  }

  // Corner guard: where two perpendicular strips are both enabled, the cells
  // that would sit inside the other strip's area are not drawn, so the corner
  // stays empty instead of stacking two grids on top of each other.
  function sideCellBlocked(alongIndex) {
    var center = (alongIndex + 0.5) * cellPitch()
    if (center < endInsetBottom) return true
    if (boardH() - center < endInsetTop) return true
    if (topStrip && boardH() - center < stripExtent()) return true
    if (bottomStrip && center < stripExtent()) return true
    return false
  }
  function edgeCellBlocked(acrossIndex) {
    var center = (acrossIndex + 0.5) * cellPitch()
    if (center < endInsetLeft) return true
    if (boardW() - center < endInsetRight) return true
    if (leftStrip && center < stripExtent()) return true
    if (rightStrip && boardW() - center < stripExtent()) return true
    return false
  }

  Process {
    id: cava
    command: ["cava"]
    running: true
    // cava is a long-lived child; respawn if it dies (device change, crash).
    onExited: respawn.restart()
    stdout: SplitParser {
      onRead: function(line) {
        var parts = line.split(";")
        var bands = []
        var peak = 0
        for (var i = 0; i < parts.length; i++) {
          var v = Number(parts[i])
          if (!isFinite(v) || v < 0) v = 0
          v = v / 100
          bands.push(v)
          if (v > peak) peak = v
        }
        root.cellValues = root.stepGrid(root.cellValues, bands, root.cellBand, root.cellThreshold)
        root.sideValues = root.stepGrid(root.sideValues, bands, root.sideBand, root.sideThreshold)
        if (peak > 0.01) {
          root.active = true
          idle.stop()
        } else if (!idle.running) {
          idle.start()
        }
      }
    }
  }

  Timer { id: idle; interval: root.idleFadeout; onTriggered: root.active = false }
  Timer { id: respawn; interval: 3000; onTriggered: if (!cava.running) cava.running = true }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      // Bottom layer: above the wallpaper (background layer), below windows.
      WlrLayershell.namespace: "rubichandrap-audioviz"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Item {
        id: content
        anchors.fill: parent
        opacity: root.active ? 1 : 0
        Behavior on opacity {
          enabled: root.fadeMs > 0
          NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic }
        }

        // Soft shadows along the three edges: the cells keep contrast against
        // bright wallpapers without raising their own opacity (bjarneo/quickshell
        // vignette trick).
        Rectangle {
          visible: root.bottomStrip
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: root.marginBottom; leftMargin: root.endInsetLeft; rightMargin: root.endInsetRight }
          height: root.stripExtent() + root.cellPitch() * 0.5
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.vignette) }
          }
        }
        Rectangle {
          visible: root.topStrip
          anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: root.marginTop; leftMargin: root.endInsetLeft; rightMargin: root.endInsetRight }
          height: root.stripExtent() + root.cellPitch() * 0.5
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.vignette) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
          }
        }
        Rectangle {
          visible: root.leftStrip
          anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: root.marginLeft; topMargin: root.endInsetTop; bottomMargin: root.endInsetBottom }
          width: root.stripExtent() + root.cellPitch() * 0.5
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.vignette) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
          }
        }
        Rectangle {
          visible: root.rightStrip
          anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: root.marginRight; topMargin: root.endInsetTop; bottomMargin: root.endInsetBottom }
          width: root.stripExtent() + root.cellPitch() * 0.5
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.vignette) }
          }
        }

        // Screen-edge shade: a dark gradient hugging the left/right edges for a
        // dramatic frame. Darkness and reach are knobs; it fades with the
        // music like the rest of the overlay.
        Rectangle {
          anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
          width: root.sideShadeWidth
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.sideShade) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
          }
        }
        Rectangle {
          anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
          width: root.sideShadeWidth
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.sideShade) }
          }
        }

        // ---- bottom strip ----
        Row {
          id: row
          visible: root.bottomStrip
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: root.marginBottom }
          Repeater {
            model: root.columns

            Item {
              id: column
              required property int index
              width: root.cellPitch()
              height: root.stripExtent()

              Repeater {
                model: root.rows

                Rectangle {
                  id: tile
                  required property int index
                  readonly property real v: index * root.columns + column.index < root.cellValues.length
                    ? root.cellValues[index * root.columns + column.index] : 0
                  width: root.tileSize() * root.tierSize(v)
                  height: width * root.rowScale(index)
                  x: (column.width - width) / 2
                  y: column.height - height - index * root.cellPitch()
                  color: root.tierColor(v)
                  opacity: root.edgeCellBlocked(column.index) ? 0 : root.cellOpacity(v, index)
                  Behavior on opacity { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                  Behavior on width { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                  Behavior on height { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                }
              }
            }
          }
        }

        // ---- top strip ----
        Row {
          visible: root.topStrip
          anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: root.marginTop }
          Repeater {
            model: root.columns

            Item {
              id: topColumn
              required property int index
              width: root.cellPitch()
              height: root.stripExtent()

              Repeater {
                model: root.rows

                Rectangle {
                  required property int index
                  readonly property real v: index * root.columns + topColumn.index < root.cellValues.length
                    ? root.cellValues[index * root.columns + topColumn.index] : 0
                  width: root.tileSize() * root.tierSize(v)
                  height: width * root.rowScale(index)
                  x: (topColumn.width - width) / 2
                  y: index * root.cellPitch()
                  color: root.tierColor(v)
                  opacity: root.edgeCellBlocked(topColumn.index) ? 0 : root.cellOpacity(v, index)
                  Behavior on opacity { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                  Behavior on width { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                  Behavior on height { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                }
              }
            }
          }
        }

        // ---- left strip (bands run bottom=bass to top=treble) ----
        Repeater {
          model: root.leftStrip ? root.sideCount : 0

          Item {
            id: leftCell
            required property int index

            Repeater {
              model: root.rows

              Rectangle {
                required property int index
                readonly property real v: leftCell.index * Math.ceil(root.rows) + index < root.sideValues.length
                  ? root.sideValues[leftCell.index * Math.ceil(root.rows) + index] : 0
                readonly property real s: root.tileSize() * root.tierSize(v)
                width: s * root.rowScale(index)
                height: s
                x: (root.cellPitch() - s) / 2 + index * root.cellPitch() + root.marginLeft
                y: content.height - height - leftCell.index * root.cellPitch()
                color: root.tierColor(v)
                opacity: root.sideCellBlocked(leftCell.index) ? 0 : root.cellOpacity(v, index)
                Behavior on opacity { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                Behavior on width { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                Behavior on height { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
              }
            }
          }
        }

        // ---- right strip (mirror of the left) ----
        Repeater {
          model: root.rightStrip ? root.sideCount : 0

          Item {
            id: rightCell
            required property int index

            Repeater {
              model: root.rows

              Rectangle {
                required property int index
                readonly property real v: rightCell.index * Math.ceil(root.rows) + index < root.sideValues.length
                  ? root.sideValues[rightCell.index * Math.ceil(root.rows) + index] : 0
                readonly property real s: root.tileSize() * root.tierSize(v)
                width: s * root.rowScale(index)
                height: s
                x: content.width - (root.cellPitch() - s) / 2 - index * root.cellPitch() - width - root.marginRight
                y: content.height - height - rightCell.index * root.cellPitch()
                color: root.tierColor(v)
                opacity: root.sideCellBlocked(rightCell.index) ? 0 : root.cellOpacity(v, index)
                Behavior on opacity { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                Behavior on width { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
                Behavior on height { NumberAnimation { duration: root.cellMs; easing.type: Easing.OutQuad } }
              }
            }
          }
        }
      }
    }
  }
}
