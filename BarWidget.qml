import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "jesperlugner.wallsmith"

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string statusPath: stateHome + "/omarchy-wallsmith/status"
  readonly property string activityPath: stateHome + "/omarchy-wallsmith/activity.json"
  readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  property bool working: false
  property int jobCount: 0
  property int spinnerFrame: 0

  visible: working
  implicitWidth: working ? indicator.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  function applyStatus(content) {
    root.working = String(content || "").trim() === "working"
    if (!root.working)
      root.spinnerFrame = 0
  }

  function applyActivity(content) {
    var count = 0
    try {
      var parsed = JSON.parse(String(content || "[]"))
      if (Array.isArray(parsed))
        count = parsed.length
      else if (parsed && parsed.working === true)
        count = 1
    } catch (e) {
      count = 0
    }
    root.jobCount = count
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

  FileView {
    id: activityFile
    path: root.activityPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyActivity(text())
    onFileChanged: reload()
    onLoadFailed: root.applyActivity("")
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      statusFile.reload()
      activityFile.reload()
    }
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
    spacing: Style.space(5)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "󰸉"
      color: root.bar ? root.bar.barForeground : "white"
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: Style.font.icon
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.spinnerFrames[root.spinnerFrame]
      color: root.bar ? root.bar.barForeground : "white"
      opacity: 0.85
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.jobCount > 1
      text: "×" + root.jobCount
      color: root.bar ? root.bar.barForeground : "white"
      opacity: 0.85
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: Style.font.bodySmall
    }
  }
}
