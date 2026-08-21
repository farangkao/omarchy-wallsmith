import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "jesperlugner.wallpaper-agent"

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string statusPath: stateHome + "/omarchy-wallpaper-agent/status"
  readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  property bool working: false
  property int spinnerFrame: 0

  visible: working
  implicitWidth: working ? indicator.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  function applyStatus(content) {
    root.working = String(content || "").trim() === "working"
    if (!root.working)
      root.spinnerFrame = 0
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyStatus(text())
    onFileChanged: reload()
    onLoadFailed: root.applyStatus("")
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: statusFile.reload()
  }

  Timer {
    interval: 90
    repeat: true
    running: root.working
    onTriggered: root.spinnerFrame = (root.spinnerFrame + 1) % root.spinnerFrames.length
  }

  Row {
    id: indicator
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.spinnerFrames[root.spinnerFrame]
      color: root.bar ? root.bar.barForeground : "white"
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar || !root.bar.vertical
      text: "Generating"
      color: root.bar ? root.bar.barForeground : "white"
      opacity: 0.85
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: Style.font.body
    }
  }
}
