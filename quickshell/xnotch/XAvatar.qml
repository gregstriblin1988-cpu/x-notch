// Round avatar for X-Notch feed cards.
import QtQuick
import QtQuick.Effects
Item {
  id: a
  property string src: ""
  property int size: 36
  width: size; height: size
  Rectangle { anchors.fill: parent; radius: width / 2; color: "#23243a" }
  Image { id: img; anchors.fill: parent; source: a.src; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; visible: false
    sourceSize.width: a.size * 2; sourceSize.height: a.size * 2 }
  MultiEffect { anchors.fill: img; source: img; maskEnabled: true; maskSource: m; visible: img.status === Image.Ready }
  Item { id: m; anchors.fill: parent; layer.enabled: true; visible: false
    Rectangle { anchors.fill: parent; radius: width / 2; color: "black" } }
}
