// X-Notch: top-center pill on DP-1 that expands to X account avatars + feed.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: rootShell
  readonly property string home: Quickshell.env("HOME")
  readonly property color bg: "#111219"
  readonly property color violet: "#8b7cf6"
  readonly property color mint: "#5fa89a"
  property var accounts: []
  property bool fullscreen: false

  FileView {
    id: accFile
    path: rootShell.home + "/.config/xnotch/accounts.json"
    watchChanges: true
    // atomic writes (tmp + rename) replace the inode; reload on change and re-arm via a
    // cheap 1.5 s safety poll (only re-parses when the text actually differs).
    onFileChanged: reload()
    property string lastText: ""
    onLoaded: {
      try {
        const t = text();
        if (t === lastText) return;
        lastText = t;
        const a = JSON.parse(t);
        console.log("xnotch accounts reloaded: " + a.length);
        rootShell.accounts = a.map(x => typeof x === "string" ? { handle: x } : x).filter(x => x && x.handle);
      } catch (e) { console.warn("xnotch: bad accounts.json", e); }
    }
  }

  Timer { interval: 1500; running: true; repeat: true; onTriggered: accFile.reload() }

  // hide when focused window is fullscreen
  Process {
    id: fsProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { const w = JSON.parse(text); rootShell.fullscreen = (w && w.fullscreen > 0) ? true : false; }
        catch (e) { rootShell.fullscreen = false; }
      }
    }
  }
  Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: fsProc.running = true }

  PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => s.name === "DP-1") ?? Quickshell.screens[0]
    visible: !rootShell.fullscreen
    anchors.top: true
    margins.top: 0
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 760
    implicitHeight: 700
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "xnotch"
    WlrLayershell.keyboardFocus: win.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { item: hit }

    property bool expanded: false
    property int sel: -1
    property string selHandle: sel >= 0 && sel < rootShell.accounts.length ? rootShell.accounts[sel].handle : ""
    property var feed: ({ status: "loading", posts: [] })
    // add/remove UI: while editing or confirming, the notch is held open
    property bool editing: false
    property int confirmIdx: -1
    readonly property bool holdOpen: editing || confirmIdx >= 0
    property string addError: ""
    readonly property real bandH: holdOpen ? 46 : 0
    function startAdd() { confirmIdx = -1; addError = ""; sel = -1; editing = true; handleField.text = ""; handleField.forceActiveFocus(); console.log("xnotch " + stamp() + " editing=true"); }
    function endEdit(why) { if (!editing && confirmIdx < 0) return; editing = false; confirmIdx = -1; addError = ""; console.log("xnotch " + stamp() + " editing=false why=" + why); if (!hoverH.hovered) collapseTimer.restart(); }
    function submitAdd() {
      const h = handleField.text.trim().replace(/^@/, "");
      if (!/^[A-Za-z0-9_]{1,15}$/.test(h)) { addError = "Invalid handle: letters, digits, _ (max 15)"; return; }
      addError = ""; addProc.command = [rootShell.home + "/.local/bin/xnotch", "add", h]; addProc.running = true;
    }
    // IPC (qs -p ~/.config/quickshell/xnotch ipc call xnotch <fn>): drives the same UI path as the '+' button
    IpcHandler { target: "xnotch"
      function openAdd(): string { win.setExpanded(true, "ipc openAdd"); win.startAdd(); return "ok"; }
      function type(h: string): string { handleField.text = h; win.submitAdd(); return win.addError || "submitted"; }
      function cancel(): string { win.endEdit("ipc cancel"); return "ok"; }
    }
    Process {
      id: addProc
      stderr: StdioCollector { id: addErr }
      onExited: (code) => { console.log("xnotch " + win.stamp() + " cli " + addProc.command.slice(1).join(" ") + " -> " + code);
        if (code === 0) win.endEdit("cli ok"); else win.addError = (addErr.text.trim() || "xnotch failed").replace(/^xnotch: /, ""); }
    }

    // ---- one-way state machine: only the collapsed pill opens; only fully leaving closes ----
    readonly property real k: 1.5          // size scale for the 2560x1440 MSI
    property double regionChangedAt: 0
    onExpandedChanged: regionChangedAt = Date.now()
    function stamp() { return Qt.formatDateTime(new Date(), "hh:mm:ss.zzz"); }
    function setExpanded(v, why) {
      if (expanded === v) return;
      console.log("xnotch " + stamp() + " expanded=" + v + " why=" + why);
      expanded = v;
      if (!v) { sel = -1; selTimer.stop(); }
    }
    Timer { id: collapseTimer; interval: 600
      onTriggered: { if (win.holdOpen) { console.log("xnotch " + win.stamp() + " collapse held: editing"); return; }
                     if (hoverH.hovered) { console.log("xnotch " + win.stamp() + " collapse aborted: still hovered"); return; }
                     win.setExpanded(false, "left expanded rect for 600ms"); } }

    // Fixed (non-animated) target geometry so the input region never moves under the cursor.
    readonly property real notchW: expanded ? Math.max(300, row.implicitWidth + 48) : 180
    readonly property real notchH: expanded ? 117 + bandH : 42
    readonly property real feedX: Math.round((width - 440) / 2)
    readonly property real feedY: notchH + 34
    property bool hovering: hoverH.hovered

    Timer { id: selTimer; interval: 220; property int pending: -1
      onTriggered: { if (pending >= 0 && win.sel !== pending) { win.sel = pending; win.loadFeed(rootShell.accounts[pending].handle); } } }

    // ONE input region + ONE hover state: pill when collapsed; when expanded the full
    // bounding box of row + tether + feed (including gaps between them).
    Item {
      id: hit
      readonly property real l: win.expanded ? Math.min((win.width - win.notchW) / 2, win.sel >= 0 ? win.feedX : 1e9) : (win.width - 180) / 2
      readonly property real r: win.expanded ? Math.max((win.width + win.notchW) / 2, win.sel >= 0 ? win.feedX + 440 : -1e9) : (win.width + 180) / 2
      x: l - 8
      y: 0
      width: r - l + 16
      height: (win.expanded ? (win.sel >= 0 ? win.feedY + 500 : win.notchH) : 42) + 12

    }
    // Single hover source, attached to the window root: hover passes to ancestors, so feed
    // delegates / avatar MouseAreas can never make it "leave". The mask limits it to hit.
    HoverHandler {
      id: hoverH
      parent: win.contentItem
      onHoveredChanged: {
        if (hovered) {
          collapseTimer.stop();
          if (!win.expanded && !win.holdOpen) {
            if (Date.now() - win.regionChangedAt < 300) { console.log("xnotch " + win.stamp() + " ignored enter <300ms after region change"); return; }
            win.setExpanded(true, "entered pill");
          }
        } else if (win.expanded) {
          console.log("xnotch " + win.stamp() + " left rect, collapse in 600ms");
          collapseTimer.restart();
        }
      }
    }
    // watchdog: keeps the single hover state authoritative and tracks the avatar under the cursor
    Timer { interval: 60; repeat: true; running: win.expanded
      onTriggered: {
        if (hoverH.hovered) { if (collapseTimer.running) collapseTimer.stop(); win.trackAvatar(hoverH.point.position.x, hoverH.point.position.y); }
        else if (!collapseTimer.running && !win.holdOpen) collapseTimer.start();
      } }

    // --- notch / avatar bar ---
    Rectangle {
      id: notch
      anchors.horizontalCenter: parent.horizontalCenter
      y: 0
      width: win.notchW
      height: win.notchH
      color: rootShell.bg
      bottomLeftRadius: win.expanded ? 30 : 21
      bottomRightRadius: win.expanded ? 30 : 21
      border.color: Qt.rgba(0.545, 0.486, 0.965, 0.35)
      border.width: 1
      Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true; shadowColor: rootShell.violet; shadowBlur: 0.9; shadowOpacity: 0.85
        shadowHorizontalOffset: 0; shadowVerticalOffset: 2
      }

      // collapsed content: mint dot + X glyph
      Row {
        anchors.centerIn: parent
        spacing: 12
        opacity: win.expanded ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Rectangle { width: 10; height: 10; radius: 5; color: rootShell.mint; anchors.verticalCenter: parent.verticalCenter }
        Text { text: "𝕏"; color: "#e6e6f0"; font.pixelSize: 21; font.bold: true }
      }

      Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        y: 15
        spacing: 21
        opacity: win.expanded ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Repeater {
          model: rootShell.accounts
          delegate: Item {
            id: av
            required property var modelData
            required property int index
            property string handle: modelData.handle
            property color tint: modelData.color || ["#8b7cf6", "#5fa89a", "#d77fa8", "#e0a458", "#5b8def"][index % 5]
            property string imgPath: ""
            width: 69; height: 90
            Process {
              running: true
              command: ["xnotch-avatar", av.handle]
              stdout: StdioCollector { onStreamFinished: av.imgPath = text.trim() }
            }
            Rectangle {
              id: circle
              width: 63; height: 63; radius: 31.5
              anchors.horizontalCenter: parent.horizontalCenter
              color: av.tint
              border.width: win.sel === av.index ? 2 : 0
              border.color: rootShell.mint
              scale: ma.containsMouse ? 1.1 : 1.0
              Behavior on scale { NumberAnimation { duration: 120 } }
              Text {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                text: av.handle.slice(0, 2).toUpperCase()
                color: "white"; font.pixelSize: 21; font.bold: true
              }
              Image {
                id: img
                anchors.fill: parent; anchors.margins: 2
                source: av.imgPath ? "file://" + av.imgPath : ""
                fillMode: Image.PreserveAspectCrop
                smooth: true; mipmap: true
                visible: false
              }
              MultiEffect {
                anchors.fill: img; source: img
                visible: img.status === Image.Ready
                maskEnabled: true; maskSource: maskShape
                maskThresholdMin: 0.5; maskSpreadAtMin: 1.0
              }
              Item {
                id: maskShape
                anchors.fill: img; layer.enabled: true; visible: false
                Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: circle.bottom; anchors.topMargin: 4
              text: "@" + av.handle
              width: 86; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
              color: "#9a9ab0"; font.pixelSize: 13
            }
            MouseArea {
              id: ma
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onClicked: (m) => {
                if (m.button === Qt.RightButton) { win.editing = false; win.sel = -1; win.confirmIdx = av.index; }
                else Quickshell.execDetached(["xdg-open", "https://x.com/" + av.handle]);
              }
            }
          }
        }
        // '+' cell: ghost ring, same size as avatars (no `index` prop -> ignored by trackAvatar)
        Item {
          id: plusCell
          width: 69; height: 90
          Rectangle {
            id: plusCircle
            width: 63; height: 63; radius: 31.5
            anchors.horizontalCenter: parent.horizontalCenter
            color: plusMa.containsMouse || win.editing ? Qt.rgba(0.545, 0.486, 0.965, 0.18) : "transparent"
            border.width: 2; border.color: win.editing ? rootShell.mint : Qt.rgba(0.545, 0.486, 0.965, 0.75)
            scale: plusMa.containsMouse ? 1.1 : 1.0
            Behavior on scale { NumberAnimation { duration: 120 } }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: rootShell.mint; shadowBlur: 0.6; shadowOpacity: 0.6 }
            Text { anchors.centerIn: parent; text: "+"; color: "#e6e6f0"; font.pixelSize: 32; font.bold: false }
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: plusCircle.bottom; anchors.topMargin: 4
            text: "add"; color: "#9a9ab0"; font.pixelSize: 13
          }
          MouseArea { id: plusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: win.editing ? win.endEdit("plus clicked again") : win.startAdd() }
        }
      }

      // inline band: '@handle' field while adding, or remove confirmation
      Item {
        id: band
        x: 24; y: 117; width: parent.width - 48; height: 38
        visible: win.expanded && win.holdOpen
        TextField {
          id: handleField
          visible: win.editing
          anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
          width: Math.min(260, parent.width - 90); height: 34
          placeholderText: "@handle"; placeholderTextColor: "#6a6a80"
          color: "#e6e6f0"; font.pixelSize: 14
          background: Rectangle { radius: 17; color: "#1a1b26"; border.width: 1; border.color: handleField.activeFocus ? rootShell.mint : Qt.rgba(0.545, 0.486, 0.965, 0.6) }
          leftPadding: 14
          Keys.onReturnPressed: win.submitAdd()
          Keys.onEnterPressed: win.submitAdd()
          Keys.onEscapePressed: win.endEdit("esc")
          onTextEdited: win.addError = ""
        }
        Text {
          visible: win.editing
          anchors.left: handleField.right; anchors.leftMargin: 10; anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight; font.pixelSize: 11
          color: win.addError ? "#e07f7f" : "#8a8aa0"
          text: win.addError || (addProc.running ? "adding…" : "Enter to add · Esc to cancel")
        }
        Row {
          visible: win.confirmIdx >= 0
          anchors.centerIn: parent; spacing: 12
          Text { anchors.verticalCenter: parent.verticalCenter; color: "#e6e6f0"; font.pixelSize: 14
            text: win.confirmIdx >= 0 && win.confirmIdx < rootShell.accounts.length ? "Remove @" + rootShell.accounts[win.confirmIdx].handle + "?" : "" }
          Rectangle { width: 84; height: 30; radius: 15; color: "#e07f7f"
            Text { anchors.centerIn: parent; text: "Remove"; color: "white"; font.bold: true; font.pixelSize: 12 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
              onClicked: { const h = rootShell.accounts[win.confirmIdx].handle; addProc.command = [rootShell.home + "/.local/bin/xnotch", "remove", h]; addProc.running = true; win.confirmIdx = -1; } } }
          Rectangle { width: 72; height: 30; radius: 15; color: "transparent"; border.color: "#6a6a80"
            Text { anchors.centerIn: parent; text: "Cancel"; color: "#c8c8d8"; font.pixelSize: 12 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.endEdit("cancel remove") } }
        }
      }
    }

    // --- drip tether ---
    Shape {
      id: tether
      property real cx: {
        if (win.sel < 0) return notch.x + notch.width / 2;
        const it = row.children[win.sel];
        return it ? row.mapToItem(win.contentItem, it.x + it.width / 2, 0).x : notch.x + notch.width / 2;
      }
      x: cx - 14
      y: notch.height - 2
      width: 28
      height: win.sel >= 0 ? win.feedY - y + 4 : 0
      visible: height > 2
      Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
      Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: rootShell.bg
        strokeColor: Qt.rgba(0.545, 0.486, 0.965, 0.5)
        strokeWidth: 1
        startX: 0; startY: 0
        PathCubic { x: 10; y: tether.height * 0.5; control1X: 9; control1Y: 0; control2X: 10; control2Y: tether.height * 0.25 }
        PathLine { x: 9; y: tether.height }
        PathLine { x: 19; y: tether.height }
        PathLine { x: 18; y: tether.height * 0.5 }
        PathCubic { x: 28; y: 0; control1X: 18; control1Y: tether.height * 0.25; control2X: 19; control2Y: 0 }
      }
    }

    // --- feed window ---
    Rectangle {
      id: feedBox
      width: 440
      height: 500
      x: win.feedX
      y: win.feedY
      radius: 18
      color: rootShell.bg
      border.color: Qt.rgba(0.545, 0.486, 0.965, 0.45)
      border.width: 1
      opacity: win.sel >= 0 && win.expanded ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      layer.enabled: true
      layer.effect: MultiEffect { shadowEnabled: true; shadowColor: rootShell.violet; shadowBlur: 1.0; shadowOpacity: 0.7 }

      Text {
        id: title
        x: 18; y: 14
        text: "@" + win.selHandle + " · feed"
        color: "#e6e6f0"; font.pixelSize: 14; font.bold: true
      }
      Rectangle {
        anchors.right: parent.right; anchors.rightMargin: 16; y: 13
        height: 20; width: badge.implicitWidth + 16; radius: 10
        color: "transparent"; border.color: rootShell.mint
        Text { id: badge; anchors.centerIn: parent; color: rootShell.mint; font.pixelSize: 10
          text: win.feed.status === "ok" ? "live" : win.feed.status === "loading" ? "loading…" : win.feed.status === "no_token" ? "no API key" : "offline" }
      }
      Rectangle { x: 14; y: 44; width: parent.width - 28; height: 1; color: "#23243a" }

      // no-token / error state
      Column {
        anchors.centerIn: parent
        spacing: 14
        visible: win.feed.status === "no_token" || win.feed.status === "error"
        width: parent.width - 60
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "🔑"; font.pixelSize: 34 }
        Text {
          width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
          text: win.feed.status === "no_token" ? "Live feed needs an X API key" : "Couldn't load the feed"
          color: "#e6e6f0"; font.pixelSize: 16; font.bold: true
        }
        Text {
          width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
          text: win.feed.status === "no_token" ? "Put an X API v2 bearer token in ~/.config/xnotch/token (chmod 600) to see posts here."
                                               : (win.feed.message || "")
          color: "#9a9ab0"; font.pixelSize: 12
        }
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: openTxt.implicitWidth + 36; height: 36; radius: 18
          gradient: Gradient { orientation: Gradient.Horizontal
            GradientStop { position: 0; color: rootShell.violet } GradientStop { position: 1; color: rootShell.mint } }
          scale: openMa.containsMouse ? 1.05 : 1
          Text { id: openTxt; anchors.centerIn: parent; text: "Open @" + win.selHandle; color: "white"; font.bold: true; font.pixelSize: 13 }
          MouseArea { id: openMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["xdg-open", "https://x.com/" + win.selHandle]) }
        }
      }

      ListView {
        id: list
        visible: win.feed.status === "ok"
        x: 14; y: 52; width: parent.width - 28; height: parent.height - 64
        clip: true; spacing: 2; boundsBehavior: Flickable.StopAtBounds; cacheBuffer: 1200
        model: win.feed.posts || []
        ScrollBar.vertical: ScrollBar {
          contentItem: Rectangle { implicitWidth: 4; radius: 2
            gradient: Gradient { GradientStop { position: 0; color: rootShell.violet } GradientStop { position: 1; color: rootShell.mint } } }
        }
        delegate: Item {
          id: card
          required property var modelData
          readonly property var p: modelData
          readonly property var q: modelData.quoted || null
          width: list.width - 8
          height: cardCol.implicitHeight + 22
          Rectangle { anchors.fill: parent; radius: 10; color: cardMa.containsMouse ? "#181a2a" : "transparent" }
          MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["xdg-open", card.p.url]) }
          Column {
            id: cardCol
            x: 8; y: 10; width: parent.width - 16; spacing: 4
            Text { visible: card.p.header !== ""; x: 46; text: "↻  " + card.p.header; color: "#8a8aa0"; font.pixelSize: 11; font.bold: true }
            Row {
              width: parent.width; spacing: 10
              XAvatar { src: card.p.avatar; size: 36 }
              Column {
                width: parent.width - 46; spacing: 6
                Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText; font.pixelSize: 13; color: "#e6e6f0"
                  text: "<b>" + win.esc(card.p.name) + "</b>" + (card.p.verified ? " <font color='#1d9bf0'>✓</font>" : "")
                        + " <font color='#7a7a92'>@" + card.p.handle + " · " + win.ago(card.p.created_at) + "</font>" }
                Text { width: parent.width; visible: card.p.html !== ""; text: card.p.html; textFormat: Text.RichText; wrapMode: Text.Wrap
                  color: "#d8d8e4"; font.pixelSize: 13; lineHeight: 1.15
                  onLinkActivated: (l) => Quickshell.execDetached(["xdg-open", l])
                  HoverHandler { enabled: parent.hoveredLink !== ""; cursorShape: Qt.PointingHandCursor } }
                XMedia { width: parent.width; media: card.p.media || [] }
                // quoted post
                Rectangle {
                  visible: card.q !== null; width: parent.width; radius: 12; color: "transparent"; border.color: "#2a2c42"
                  height: visible ? qCol.implicitHeight + 18 : 0
                  Column { id: qCol; x: 10; y: 9; width: parent.width - 20; spacing: 5
                    Row { spacing: 6
                      XAvatar { src: card.q ? card.q.avatar : ""; size: 18 }
                      Text { textFormat: Text.StyledText; font.pixelSize: 12; color: "#e6e6f0"; anchors.verticalCenter: parent.verticalCenter
                        text: card.q ? "<b>" + win.esc(card.q.name) + "</b>" + (card.q.verified ? " <font color='#1d9bf0'>✓</font>" : "")
                              + " <font color='#7a7a92'>@" + card.q.handle + " · " + win.ago(card.q.created_at) + "</font>" : "" } }
                    Text { width: parent.width; text: card.q ? card.q.html : ""; textFormat: Text.RichText; wrapMode: Text.Wrap
                      color: "#d0d0dc"; font.pixelSize: 12; maximumLineCount: 6; elide: Text.ElideRight
                      onLinkActivated: (l) => Quickshell.execDetached(["xdg-open", l]) }
                    XMedia { width: parent.width; media: card.q ? (card.q.media || []) : [] }
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; z: -1
                    onClicked: Quickshell.execDetached(["xdg-open", "https://x.com/" + card.q.handle + "/status/" + card.q.id]) }
                }
                Row {
                  spacing: 0; width: parent.width
                  Repeater {
                    model: [["💬", card.p.replies, "#8a8aa0"], ["↻", card.p.reposts, "#00ba7c"], ["♥", card.p.likes, "#f91880"], ["📊", card.p.views, "#8a8aa0"]]
                    Text { required property var modelData; width: parent.width / 4; color: "#8a8aa0"; font.pixelSize: 11; textFormat: Text.StyledText
                      text: "<font color='" + modelData[2] + "'>" + modelData[0] + "</font> " + win.fmt(modelData[1]) }
                  }
                }
              }
            }
          }
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#1f2033" }
        }
      }
    }

    Process {
      id: feedProc
      property string handle: ""
      command: ["xnotch-fetch", handle]
      stdout: StdioCollector {
        onStreamFinished: {
          try { const o = JSON.parse(text); if (o.handle === win.selHandle) win.feed = o; }
          catch (e) { win.feed = { status: "error", posts: [], message: "bad fetch output" }; }
        }
      }
    }
    // pick the avatar under the cursor (row band only) with a short debounce
    function trackAvatar(px, py) {
      if (!expanded || py < 8 || py > 112) { if (py <= 112) selTimer.stop(); return; }
      let idx = -1;
      for (let i = 0; i < row.children.length; i++) {
        const it = row.children[i];
        if (!it || it.width <= 0 || it.height <= 0 || it.index === undefined) continue;
        const p = it.mapToItem(win.contentItem, 0, 0);
        if (px >= p.x && px < p.x + it.width) { idx = it.index; break; }
      }
      if (idx < 0) { selTimer.stop(); return; }
      if (idx === sel) { selTimer.stop(); return; }
      if (selTimer.pending !== idx || !selTimer.running) { selTimer.pending = idx; selTimer.restart(); }
    }
    function loadFeed(h) {
      feed = { status: "loading", posts: [] };
      feedProc.running = false;
      feedProc.handle = h;
      feedProc.running = true;
    }
    function esc(t) { return String(t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function fmt(n) { n = n || 0; if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(/\.0$/, "") + "M";
      if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1).replace(/\.0$/, "") + "K"; return "" + n; }
    function ago(iso) {
      if (!iso) return "";
      const s = (Date.now() - new Date(iso).getTime()) / 1000;
      if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "m";
      if (s < 86400) return Math.floor(s / 3600) + "h";
      return Math.floor(s / 86400) + "d";
    }
    // refresh selected feed every 10 min
    Timer { interval: 600000; running: win.sel >= 0; repeat: true; onTriggered: win.loadFeed(win.selHandle) }
  }
}
