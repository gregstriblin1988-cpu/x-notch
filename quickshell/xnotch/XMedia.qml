// 1-4 image grid for X-Notch feed cards (photos, gif/video thumbnails with play badge).
import QtQuick
import QtQuick.Effects
Item {
  id: g
  property var media: []
  readonly property int n: Math.min(4, media.length)
  readonly property real gap: 3
  readonly property real h1: n === 1 && media[0].w > 0 ? Math.min(280, Math.max(120, width * media[0].h / media[0].w)) : 0
  readonly property real gh: n === 0 ? 0 : n === 1 ? h1 : n === 2 ? width * 0.56 : width * 0.62
  visible: n > 0
  height: gh
  function cell(i) {  // x, y, w, h
    const W = width, H = gh, hw = (W - gap) / 2, hh = (H - gap) / 2;
    if (n === 1) return [0, 0, W, H];
    if (n === 2) return [i * (hw + gap), 0, hw, H];
    if (n === 3) return i === 0 ? [0, 0, hw, H] : [hw + gap, (i - 1) * (hh + gap), hw, hh];
    return [(i % 2) * (hw + gap), Math.floor(i / 2) * (hh + gap), hw, hh];
  }
  Item {
    id: tiles; anchors.fill: parent; visible: false; layer.enabled: true
    Repeater {
      model: g.n
      Item {
        required property int index
        readonly property var c: g.cell(index)
        readonly property var m: g.media[index]
        x: c[0]; y: c[1]; width: c[2]; height: c[3]
        Rectangle { anchors.fill: parent; color: "#1a1b26" }
        Image { anchors.fill: parent; source: parent.m.src; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
          sourceSize.width: 600 }
        Rectangle { visible: parent.m.type !== "photo"; anchors.centerIn: parent; width: 44; height: 44; radius: 22
          color: "#cc1d9bf0"; border.color: "white"; border.width: 2
          Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; text: "▶"; color: "white"; font.pixelSize: 18 } }
        Rectangle { visible: parent.m.type !== "photo"; x: 6; y: parent.height - 24; height: 18; radius: 4; color: "#b0000000"
          width: durT.implicitWidth + 10
          Text { id: durT; anchors.centerIn: parent; color: "white"; font.pixelSize: 10; font.bold: true
            text: parent.parent.m.type === "animated_gif" ? "GIF" : Math.floor(parent.parent.m.dur / 60) + ":" + ("0" + parent.parent.m.dur % 60).slice(-2) } }
      }
    }
  }
  MultiEffect { anchors.fill: tiles; source: tiles; maskEnabled: true; maskSource: gm }
  Item { id: gm; anchors.fill: parent; layer.enabled: true; visible: false
    Rectangle { anchors.fill: parent; radius: 12; color: "black" } }
  Rectangle { anchors.fill: parent; radius: 12; color: "transparent"; border.color: "#2a2c42" }
}
