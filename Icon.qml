import QtQuick
import QtQuick.Shapes
import "Model.js" as Model

// One of Tunedex's own SVG icons (exact path data from the site), rendered
// as a vector shape so it stays crisp at any size instead of relying on a
// nerd-font glyph that may not exist in the user's font.
Item {
  id: root
  property string name: "music"
  property color color: "#e8f1f2"
  property real strokeWidth: 1.75

  readonly property var spec: Model.ICONS[name] || Model.ICONS.music
  implicitWidth: 24
  implicitHeight: 24

  Shape {
    id: shape
    // Natural 24x24 (the icons' own viewBox), scaled to fit and centered —
    // NOT anchors.fill, which would size this to root first and then scale
    // that size again.
    width: 24
    height: 24
    anchors.centerIn: parent
    transformOrigin: Item.Center
    scale: Math.min(root.width, root.height) / 24
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.spec.filled ? root.color : "transparent"
      strokeColor: root.spec.filled ? "transparent" : root.color
      strokeWidth: root.spec.filled ? 0 : root.strokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillRule: ShapePath.WindingFill
      PathSvg { path: root.spec.d }
    }
  }
}
