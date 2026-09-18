import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool themeContextEnabled: true
  property int activeJobs: 0
  property var activeRefineIds: ({})
  property var activeRefineJobs: ({})
  property var pendingJobs: []
  property var records: []
  property var _prevJobIds: []
  property string _pendingSig: ""
  property string singleJobMode: ""
  readonly property bool workerBusy: activeJobs > 0
  readonly property int maxParallelJobs: 4

  property string confirmAction: ""
  property string confirmTargetId: ""
  property string confirmMessage: ""

  property bool actionMenuOpen: false
  property int actionRowIndex: -1

  property string refineRecordId: ""
  property string refinePrompt: ""
  property string refineImage: ""
  property var refineEdits: []
  property var refineVersions: []
  property int refineVersionIndex: -1
  readonly property var refineSelected: refineVersionIndex >= 0 && refineVersionIndex < refineVersions.length
    ? refineVersions[refineVersionIndex] : null
  readonly property bool refineActive: refineRecordId !== ""

  property string inlineError: ""

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string activityPath: stateHome + "/omarchy-wallsmith/activity.json"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property color accentColor: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int contentMargin: Style.spacing.panelPadding

  readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  property int spinnerFrame: 0
  readonly property string statusText: activeJobs > 1
    ? activeJobs + " wallpaper jobs running…"
    : singleJobMode === "refine" ? "Editing wallpaper…" : "Generating wallpaper…"

  readonly property int cardWidth: Math.min(Style.space(660), panel.width - Style.gapsOut * 2)
  readonly property int rowHeight: Math.max(
    Style.space(64),
    Math.round(Style.font.body * 2.6 + Style.font.caption * 1.4 + Style.spacing.sm * 2)
  )
  readonly property int maxVisibleRows: 4
  readonly property int visibleRows: Math.min(historyModel.count, maxVisibleRows)
  readonly property int listHeight: visibleRows > 0
    ? visibleRows * rowHeight + (visibleRows - 1) * Style.spacing.sm
    : 0
  readonly property int editorHeight: Math.max(
    Style.space(84),
    Math.min(
      Math.ceil(promptInput.contentHeight) + Style.spacing.md * 2 + Style.space(4),
      Math.round(panel.height * 0.35)
    )
  )

  ListModel { id: historyModel }

  function updateWorkingRows() {
    for (var i = 0; i < historyModel.count; i++) {
      var row = historyModel.get(i)
      if (row.pending)
        continue
      historyModel.setProperty(i, "working", root.activeRefineIds[row.recordId] === true)
    }
  }

  function currentRowKey() {
    if (historyList.currentIndex < 0 || historyList.currentIndex >= historyModel.count)
      return ""
    var row = historyModel.get(historyList.currentIndex)
    return row.pending ? "job:" + row.jobId : "rec:" + row.recordId
  }

  function rebuildModel() {
    var selKey = root.currentRowKey()
    historyModel.clear()
    for (var p = 0; p < root.pendingJobs.length; p++) {
      var pend = root.pendingJobs[p]
      historyModel.append({
        pending: true,
        jobId: pend.jobId,
        recordId: "",
        prompt: pend.prompt || "Generating wallpaper",
        image: "",
        themeName: "",
        updatedAt: pend.startedAt || "",
        editsJson: "[]",
        editCount: 0,
        turnsJson: "[]",
        versionsJson: "[]",
        working: false
      })
    }
    for (var r = 0; r < root.records.length; r++)
      historyModel.append(root.records[r])

    var nextIndex = historyModel.count > 0 ? 0 : -1
    if (selKey !== "") {
      for (var i = 0; i < historyModel.count; i++) {
        var row = historyModel.get(i)
        var key = row.pending ? "job:" + row.jobId : "rec:" + row.recordId
        if (key === selKey) {
          nextIndex = i
          break
        }
      }
    }
    historyList.currentIndex = nextIndex
    root.updateWorkingRows()
  }

  function prepareRecord(entry) {
    entry = entry || ({})
    var turns = entry.turns || []
    var edits = []
    for (var t = 0; t < turns.length; t++) {
      var turn = turns[t] || ({})
      if (String(turn.kind || "") === "refine")
        edits.push({ instruction: String(turn.instruction || ""), at: String(turn.at || "") })
    }
    var allTurns = []
    for (var a = 0; a < turns.length; a++) {
      var at = turns[a] || ({})
      allTurns.push({
        kind: String(at.kind || ""),
        instruction: String(at.instruction || ""),
        at: String(at.at || "")
      })
    }
    return {
      pending: false,
      jobId: "",
      recordId: String(entry.recordId || ""),
      prompt: String(entry.prompt || "Generated wallpaper"),
      image: String(entry.image || ""),
      themeName: String(entry.themeName || entry.themeSlug || "Unknown theme"),
      updatedAt: String(entry.updatedAt || ""),
      editsJson: JSON.stringify(edits),
      editCount: edits.length,
      turnsJson: JSON.stringify(allTurns),
      versionsJson: JSON.stringify(entry.versions || []),
      working: false
    }
  }

  // Version list for the refine strip: each snapshot v<N>.jpg holds the
  // result of turn N-1, plus the live image as the last (current) entry.
  function buildRefineVersions(entry) {
    var files = []
    var turns = []
    try { files = JSON.parse(entry.versionsJson || "[]") || [] } catch (e) { files = [] }
    try { turns = JSON.parse(entry.turnsJson || "[]") || [] } catch (e) { turns = [] }

    function turnLabel(turn) {
      if (!turn)
        return "Earlier version"
      if (turn.kind === "generate")
        return "Original generation"
      return turn.instruction || "Earlier version"
    }

    var list = []
    for (var i = 0; i < files.length; i++) {
      var file = String(files[i])
      var match = file.match(/v(\d+)\.jpg$/)
      var turn = match ? turns[parseInt(match[1], 10) - 1] : null
      list.push({
        file: file,
        label: turnLabel(turn),
        at: turn ? turn.at : "",
        isCurrent: false
      })
    }
    list.push({
      file: String(entry.image || ""),
      label: turns.length > 1 ? turnLabel(turns[turns.length - 1]) : "Original generation",
      at: String(entry.updatedAt || ""),
      isCurrent: true
    })
    root.refineVersions = list
    root.refineVersionIndex = list.length - 1
  }

  function stepVersion(delta, wrap) {
    var count = root.refineVersions.length
    if (count < 2)
      return
    var next = root.refineVersionIndex + delta
    if (wrap === true)
      next = (next + count) % count
    root.refineVersionIndex = Math.max(0, Math.min(next, count - 1))
  }

  function restoreSelectedVersion() {
    var selected = root.refineSelected
    if (!selected || selected.isCurrent || !root.refineActive)
      return
    var sourceDir = root.manifest ? String(root.manifest.__sourceDir || "") : ""
    if (!sourceDir)
      return
    if (root.activeRefineIds[root.refineRecordId] === true) {
      root.showError("This wallpaper is being edited — wait for that edit to finish")
      return
    }
    var name = selected.file.split("/").pop()
    Quickshell.execDetached([sourceDir + "/bin/restore-version", root.refineRecordId, name])
    root.dismiss()
  }

  function applyActivity(content) {
    var jobs = []
    try {
      var parsed = JSON.parse(String(content || "[]"))
      if (Array.isArray(parsed))
        jobs = parsed
      else if (parsed && parsed.working === true)
        jobs = [parsed]
    } catch (e) {
      jobs = []
    }
    var refineIds = ({})
    var refineJobs = ({})
    var pending = []
    var ids = []
    for (var i = 0; i < jobs.length; i++) {
      var job = jobs[i] || ({})
      var jobId = String(job.jobId || "")
      ids.push(jobId)
      if (String(job.mode || "") === "refine" && job.recordId) {
        refineIds[String(job.recordId)] = true
        refineJobs[String(job.recordId)] = jobId
      } else {
        pending.push({
          jobId: jobId,
          prompt: String(job.prompt || ""),
          startedAt: String(job.startedAt || "")
        })
      }
    }
    root.activeJobs = jobs.length
    root.activeRefineIds = refineIds
    root.activeRefineJobs = refineJobs
    root.singleJobMode = jobs.length === 1 ? String(jobs[0].mode || "") : ""

    var finished = false
    for (var f = 0; f < root._prevJobIds.length; f++) {
      if (ids.indexOf(root._prevJobIds[f]) < 0) {
        finished = true
        break
      }
    }
    root._prevJobIds = ids

    var pendingSig = JSON.stringify(pending)
    if (pendingSig !== root._pendingSig) {
      root._pendingSig = pendingSig
      root.pendingJobs = pending
      root.rebuildModel()
    } else {
      root.updateWorkingRows()
    }

    // A job just completed: its result (new record, or updated turns on a
    // refined record) is on disk but not in our snapshot.
    if (finished && root.opened)
      root.refreshHistory()
  }

  function refreshHistory() {
    var sourceDir = root.manifest ? String(root.manifest.__sourceDir || "") : ""
    if (!sourceDir || historyProc.running)
      return
    historyProc.command = [sourceDir + "/bin/wallpaper-history"]
    historyProc.running = true
  }

  function applyHistoryJson(content) {
    var history = []
    try { history = JSON.parse(String(content || "[]")) || [] } catch (e) { history = [] }
    if (!Array.isArray(history))
      history = []
    var next = []
    for (var i = 0; i < history.length; i++)
      next.push(root.prepareRecord(history[i]))
    root.records = next
    root.rebuildModel()

    if (root.refineActive) {
      var found = null
      for (var r = 0; r < root.records.length; r++) {
        if (root.records[r].recordId === root.refineRecordId) {
          found = root.records[r]
          break
        }
      }
      if (!found) {
        root.clearRefineTarget()
      } else {
        root.refinePrompt = found.prompt
        root.refineImage = found.image
        try { root.refineEdits = JSON.parse(found.editsJson) || [] } catch (e) { root.refineEdits = [] }
        root.buildRefineVersions(found)
      }
    }
  }

  function formatWhen(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    if (isNaN(d.getTime())) return String(iso).replace("T", " ").slice(0, 16)
    var now = new Date()
    var hh = ("0" + d.getHours()).slice(-2)
    var mm = ("0" + d.getMinutes()).slice(-2)
    if (d.toDateString() === now.toDateString()) return "Today " + hh + ":" + mm
    var yesterday = new Date(now.getTime() - 86400000)
    if (d.toDateString() === yesterday.toDateString()) return "Yesterday " + hh + ":" + mm
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var label = d.getDate() + " " + months[d.getMonth()]
    if (d.getFullYear() !== now.getFullYear()) label += " " + d.getFullYear()
    return label + " " + hh + ":" + mm
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    // This overlay is a layer surface, so the launcher's launch feedback never
    // sees a toplevel appear and would pin its "Launching…" OSD until timeout.
    if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.closeLaunchFeedback === "function")
      root.shell.appLibrary.closeLaunchFeedback(root.shell.appLibrary.launchSerial)

    // Omarchy 4.0.4 scopes shell.appLibrary to menu-kind plugins and drops
    // closeLaunchFeedback entirely, so the call above no-ops there. The OSD
    // only appears 2 s after the menu click; close it shortly after.
    launchOsdFallback.restart()

    root.clearRefineTarget()
    root.inlineError = ""
    root.themeContextEnabled = payload.themeContextEnabled !== false
    promptInput.text = String(payload.prompt || "")

    var history = payload.history || []
    var next = []
    for (var i = 0; i < history.length; i++)
      next.push(root.prepareRecord(history[i]))
    root.records = next
    historyList.currentIndex = -1
    root.rebuildModel()
    historyList.currentIndex = historyModel.count > 0 ? 0 : -1

    root.opened = true
    Qt.callLater(function() {
      if (payload.mode === "history" && historyModel.count > 0)
        historyList.forceActiveFocus()
      else
        root.focusPrompt()
    })
  }

  function close() {
    root.opened = false
  }

  function ping() {
    return "ok"
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "jesperlugner.wallsmith")
  }

  function focusPrompt() {
    promptInput.forceActiveFocus()
    promptInput.cursorPosition = promptInput.text.length
  }

  function showError(message) {
    root.inlineError = message
    errorTimer.restart()
  }

  function setRefineTarget(index) {
    if (index < 0 || index >= historyModel.count)
      return
    var entry = historyModel.get(index)
    if (entry.pending) {
      root.showError("Still generating — it can be refined once it lands in history")
      return
    }
    if (root.refineRecordId === entry.recordId) {
      root.clearRefineTarget()
      return
    }
    root.refineRecordId = entry.recordId
    root.refinePrompt = entry.prompt
    root.refineImage = entry.image
    var edits = []
    try { edits = JSON.parse(entry.editsJson || "[]") || [] } catch (e) { edits = [] }
    root.refineEdits = edits
    root.buildRefineVersions(entry)
    root.focusPrompt()
  }

  function clearRefineTarget() {
    root.refineRecordId = ""
    root.refinePrompt = ""
    root.refineImage = ""
    root.refineEdits = []
    root.refineVersions = []
    root.refineVersionIndex = -1
  }

  function reusePrompt(index) {
    if (index < 0 || index >= historyModel.count)
      return
    root.clearRefineTarget()
    promptInput.text = historyModel.get(index).prompt
    root.focusPrompt()
  }

  function openRowActions(index) {
    if (index < 0 || index >= historyModel.count)
      return
    var row = historyModel.get(index)
    historyList.currentIndex = index
    var items = []
    if (row.pending) {
      items.push({ label: "Reuse prompt", kbd: "Shift+Return", action: "reuse" })
      items.push({ label: "Cancel generation", kbd: "Del", action: "rowAction" })
    } else {
      items.push({ label: root.refineRecordId === row.recordId ? "Stop refining" : "Refine", kbd: "", action: "refine" })
      items.push({ label: "Apply as background", kbd: "Alt+Return", action: "apply" })
      items.push({ label: "Reuse prompt", kbd: "Shift+Return", action: "reuse" })
      items.push({ label: "Create theme", kbd: "Alt+T", action: "theme" })
      items.push({ label: row.working ? "Cancel edit" : "Delete", kbd: "Del", action: "rowAction" })
    }
    actionMenu.items = items
    actionMenu.selectedIndex = 0
    actionMenu.title = row.prompt
    root.actionRowIndex = index
    root.actionMenuOpen = true
  }

  function closeActionMenu() {
    root.actionMenuOpen = false
    Qt.callLater(function() {
      if (historyModel.count > 0)
        historyList.forceActiveFocus()
      else
        root.focusPrompt()
    })
  }

  function runRowAction(action) {
    var index = root.actionRowIndex
    root.actionMenuOpen = false
    if (action === "refine")
      root.setRefineTarget(index)
    else if (action === "apply")
      root.applyWallpaper(index)
    else if (action === "reuse")
      root.reusePrompt(index)
    else if (action === "theme")
      root.createTheme(index)
    else if (action === "rowAction")
      root.requestRowAction(index)
  }

  function createTheme(index) {
    if (index < 0 || index >= historyModel.count)
      return
    var entry = historyModel.get(index)
    if (entry.pending || !entry.recordId) {
      root.showError("Still generating — a theme needs the finished wallpaper")
      return
    }
    var sourceDir = root.manifest ? String(root.manifest.__sourceDir || "") : ""
    if (!sourceDir)
      return
    Quickshell.execDetached([sourceDir + "/bin/create-theme", entry.recordId])
    root.dismiss()
  }

  function applyWallpaper(index) {
    if (index < 0 || index >= historyModel.count)
      return
    var entry = historyModel.get(index)
    if (entry.pending || !entry.image) {
      root.showError("Still generating — it can be applied once it finishes")
      return
    }
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-theme-bg-set", entry.image])
    root.dismiss()
  }

  function requestRowAction(index) {
    if (index < 0 || index >= historyModel.count)
      return
    var row = historyModel.get(index)
    if (row.pending) {
      root.confirmAction = "cancel"
      root.confirmTargetId = row.jobId
      root.confirmMessage = "Stop generating this wallpaper?"
    } else if (row.working) {
      var jobId = root.activeRefineJobs[row.recordId]
      if (!jobId)
        return
      root.confirmAction = "cancel"
      root.confirmTargetId = jobId
      root.confirmMessage = "Stop the running edit of this wallpaper?"
    } else {
      root.confirmAction = "delete"
      root.confirmTargetId = row.recordId
      root.confirmMessage = "Delete this wallpaper and its edit history?"
    }
    confirmDialog.selectedIndex = 0
  }

  function closeConfirm() {
    root.confirmAction = ""
    root.confirmTargetId = ""
    root.confirmMessage = ""
    Qt.callLater(function() {
      if (historyModel.count > 0)
        historyList.forceActiveFocus()
      else
        root.focusPrompt()
    })
  }

  function executeConfirm() {
    var sourceDir = root.manifest ? String(root.manifest.__sourceDir || "") : ""
    var action = root.confirmAction
    var target = root.confirmTargetId
    if (sourceDir && target) {
      if (action === "cancel") {
        Quickshell.execDetached([sourceDir + "/bin/cancel-job", target])
      } else if (action === "delete") {
        Quickshell.execDetached([sourceDir + "/bin/delete-record", target])
        var kept = []
        for (var i = 0; i < root.records.length; i++) {
          if (root.records[i].recordId !== target)
            kept.push(root.records[i])
        }
        root.records = kept
        if (root.refineRecordId === target)
          root.clearRefineTarget()
        root.rebuildModel()
      }
    }
    root.closeConfirm()
  }

  // Esc backs out one level: refine target first, then the overlay.
  function handleEscape() {
    if (root.refineActive) {
      root.clearRefineTarget()
      root.focusPrompt()
    } else {
      root.dismiss()
    }
  }

  function submit(ignoreThemeContext) {
    if (root.refineActive && root.activeRefineIds[root.refineRecordId] === true) {
      root.showError("This wallpaper is already being edited — wait for that edit to finish")
      return
    }
    if (root.activeJobs >= root.maxParallelJobs) {
      root.showError("Up to " + root.maxParallelJobs + " wallpaper jobs can run at once — wait for one to finish")
      return
    }

    var prompt = String(promptInput.text || "").trim()
    if (!prompt) {
      root.showError(root.refineActive ? "Describe the change you want" : "Describe the wallpaper you want")
      root.focusPrompt()
      return
    }

    var sourceDir = root.manifest ? String(root.manifest.__sourceDir || "") : ""
    if (!sourceDir) {
      Quickshell.execDetached([
        root.omarchyPath + "/bin/omarchy-notification-send",
        "Wallpaper agent unavailable",
        "Omarchy could not resolve the plugin directory"
      ])
      root.dismiss()
      return
    }

    var command = [sourceDir + "/bin/generate-wallpaper"]
    if (root.refineActive)
      command.push("--refine", root.refineRecordId)
    if (!root.themeContextEnabled || ignoreThemeContext === true)
      command.push("--no-theme-context")
    command.push("--prompt", prompt)
    Quickshell.execDetached(command)
    root.dismiss()
  }

  Timer {
    id: errorTimer
    interval: 3200
    repeat: false
    onTriggered: root.inlineError = ""
  }

  // Same CLI the shell's closeLaunchFeedback uses (AppLibrary.qml). Blunt on
  // purpose: it closes whatever OSD is up, which at +2.5 s after a summon is
  // the launch OSD.
  Timer {
    id: launchOsdFallback
    interval: 2500
    repeat: false
    onTriggered: Quickshell.execDetached(["omarchy-shell", "osd", "close"])
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

  Process {
    id: historyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyHistoryJson(text)
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: activityFile.reload()
  }

  Timer {
    interval: 90
    repeat: true
    running: root.workerBusy && root.opened
    onTriggered: root.spinnerFrame = (root.spinnerFrame + 1) % root.spinnerFrames.length
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jesperlugner-wallsmith"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(
        content.implicitHeight + card.contentTopInset + card.contentBottomInset,
        panel.height - Style.gapsOut * 2
      )
      anchors.centerIn: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 20
        opened: root.confirmAction !== ""
        message: root.confirmMessage
        cancelText: "Keep"
        confirmText: root.confirmAction === "delete" ? "Delete" : "Stop job"
        background: root.background
        foreground: root.foreground
        scrim: root.scrim
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: Style.font.menuFamily
        cornerRadius: root.cornerRadius
        onCanceled: root.closeConfirm()
        onConfirmed: root.executeConfirm()
      }

      Item {
        id: actionMenu
        anchors.fill: parent
        z: 15
        visible: root.actionMenuOpen

        property var items: []
        property int selectedIndex: 0
        property string title: ""

        function handleKey(event) {
          if (!root.actionMenuOpen)
            return false
          if (event.key === Qt.Key_Escape) {
            root.closeActionMenu()
            return true
          }
          if (event.key === Qt.Key_Up || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            actionMenu.selectedIndex = (actionMenu.selectedIndex + actionMenu.items.length - 1) % actionMenu.items.length
            return true
          }
          if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            actionMenu.selectedIndex = (actionMenu.selectedIndex + 1) % actionMenu.items.length
            return true
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.runRowAction(actionMenu.items[actionMenu.selectedIndex].action)
            return true
          }
          return false
        }

        Rectangle {
          anchors.fill: parent
          color: root.scrim

          MouseArea { anchors.fill: parent; onClicked: root.closeActionMenu() }
        }

        BorderSurface {
          id: actionCard
          width: Math.min(Style.space(320), parent.width - Style.space(24))
          height: actionColumn.implicitHeight + actionCard.contentTopInset + actionCard.contentBottomInset
          anchors.centerIn: parent
          color: root.background
          borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
          radius: root.cornerRadius
          padding: Style.spacing.md

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: actionColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: actionCard.contentTopInset
            anchors.leftMargin: actionCard.contentLeftInset
            anchors.rightMargin: actionCard.contentRightInset
            spacing: Style.spacing.xxs

            Text {
              width: parent.width
              text: actionMenu.title
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.55
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              bottomPadding: Style.spacing.sm
            }

            Repeater {
              model: actionMenu.items

              Rectangle {
                required property int index
                required property var modelData

                readonly property bool isSelected: index === actionMenu.selectedIndex

                width: actionColumn.width
                height: Style.space(30)
                radius: root.cornerRadius
                color: isSelected ? root.selectedBackground : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: parent.isSelected ? root.selectedText : root.foreground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.kbd
                  color: root.foreground
                  opacity: 0.45
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: actionMenu.selectedIndex = parent.index
                  onClicked: root.runRowAction(parent.modelData.action)
                }
              }
            }
          }
        }
      }

      Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.lg

        Item {
          width: parent.width
          height: Math.max(titleText.implicitHeight, Style.space(22))

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.refineActive ? "Refine wallpaper" : "Generate a wallpaper"
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm
            visible: root.workerBusy

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.spinnerFrames[root.spinnerFrame]
              color: root.accentColor
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.statusText
              color: root.foreground
              opacity: 0.72
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Rectangle {
          id: promptBox
          width: parent.width
          height: root.editorHeight
          radius: root.cornerRadius
          color: Style.controlFill(promptInput.activeFocus, editorHover.containsMouse, root.foreground, root.accentColor)
          border.width: Style.controlBorderWidth(promptInput.activeFocus, editorHover.containsMouse)
          border.color: Style.controlBorder(promptInput.activeFocus, editorHover.containsMouse, root.foreground, root.accentColor)

          MouseArea {
            id: editorHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            onClicked: root.focusPrompt()
          }

          Text {
            anchors.fill: parent
            anchors.margins: Style.spacing.md
            visible: promptInput.text.length === 0
            wrapMode: Text.Wrap
            text: root.refineActive
              ? "Make the water brighter and preserve everything else..."
              : "A misty brutalist city at sunrise..."
            color: root.foreground
            opacity: 0.45
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }

          TextEdit {
            id: promptInput
            anchors.fill: parent
            anchors.margins: Style.spacing.md
            color: root.foreground
            selectionColor: Style.selectionFillFor(root.foreground, root.accentColor)
            selectedTextColor: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            clip: true
            selectByMouse: true

            Keys.onPressed: function(event) {
              if (root.actionMenuOpen) {
                if (actionMenu.handleKey(event))
                  event.accepted = true
                return
              }
              if (root.confirmAction !== "") {
                if (confirmDialog.handleKey(event))
                  event.accepted = true
                return
              }
              if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                if (historyModel.count > 0)
                  historyList.forceActiveFocus()
                event.accepted = true
              } else if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier) !== 0) {
                root.themeContextEnabled = !root.themeContextEnabled
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.handleEscape()
                event.accepted = true
              } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right)
                  && (event.modifiers & Qt.AltModifier) !== 0
                  && root.refineActive && root.refineVersions.length > 1) {
                root.stepVersion(event.key === Qt.Key_Left ? -1 : 1, false)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if ((event.modifiers & Qt.ControlModifier) !== 0)
                  root.restoreSelectedVersion()
                else if ((event.modifiers & Qt.AltModifier) !== 0)
                  promptInput.insert(promptInput.cursorPosition, "\n")
                else
                  root.submit((event.modifiers & Qt.ShiftModifier) !== 0)
                event.accepted = true
              } else if (event.key === Qt.Key_Down
                  && historyModel.count > 0
                  && promptInput.cursorRectangle.y + promptInput.cursorRectangle.height
                     >= promptInput.contentHeight - 2) {
                historyList.forceActiveFocus()
                event.accepted = true
              }
            }
          }
        }

        Rectangle {
          id: refineStrip
          width: parent.width
          height: stripColumn.implicitHeight + Style.spacing.sm * 2
          visible: root.refineActive
          radius: root.cornerRadius
          color: Util.alpha(root.accentColor, 0.10)

          readonly property int textIndent: refineThumbFrame.width + Style.spacing.md

          Column {
            id: stripColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Style.spacing.sm
            anchors.leftMargin: Style.spacing.sm
            anchors.rightMargin: Style.spacing.sm
            spacing: Style.spacing.xs

            Item {
              width: parent.width
              height: Math.max(Style.space(36), refineHead.implicitHeight)

              Rectangle {
                id: refineThumbFrame
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(36)
                width: Math.round(height * 16 / 9)
                radius: Math.max(1, root.cornerRadius - Style.spacing.xs)
                color: root.selectedBackground
                clip: true

                Image {
                  anchors.fill: parent
                  source: root.refineSelected && root.refineSelected.file
                    ? "file://" + root.refineSelected.file
                    : root.refineImage ? "file://" + root.refineImage : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  sourceSize.width: 320
                }

                MouseArea {
                  anchors.fill: parent
                  visible: root.refineVersions.length > 1
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.stepVersion(1, true)
                }
              }

              Button {
                id: refineClear
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅖"
                iconSize: Style.font.bodySmall
                fontFamily: Style.font.menuFamily
                foreground: root.foreground
                horizontalPadding: Style.spacing.sm
                verticalPadding: Style.spacing.xs
                tooltipText: "Back to new wallpaper (Esc)"
                onClicked: {
                  root.clearRefineTarget()
                  root.focusPrompt()
                }
              }

              Column {
                id: refineHead
                anchors.left: refineThumbFrame.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: refineClear.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Text {
                  width: parent.width
                  text: root.refineEdits.length > 0
                    ? "Refining  ·  " + root.refineEdits.length + (root.refineEdits.length === 1 ? " edit so far" : " edits so far")
                    : "Refining"
                  color: root.accentColor
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                }

                Text {
                  width: parent.width
                  text: root.refinePrompt
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: 0.8
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }

            Text {
              visible: root.refineVersions.length > 1 && root.refineSelected !== null
              width: parent.width
              leftPadding: refineStrip.textIndent
              text: root.refineSelected
                ? "◂ " + (root.refineVersionIndex + 1) + "/" + root.refineVersions.length + " ▸  "
                  + (root.refineSelected.isCurrent
                    ? "Current version"
                    : root.refineSelected.label + "  ·  Ctrl+Return restores")
                : ""
              textFormat: Text.PlainText
              color: root.refineSelected && !root.refineSelected.isCurrent ? root.accentColor : root.foreground
              opacity: root.refineSelected && !root.refineSelected.isCurrent ? 0.95 : 0.55
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              visible: root.refineVersions.length <= 1 && root.refineEdits.length > 0
              width: parent.width
              leftPadding: refineStrip.textIndent
              text: root.refineEdits.length > 0
                ? "✎  " + root.refineEdits[root.refineEdits.length - 1].instruction
                  + (root.refineEdits[root.refineEdits.length - 1].at
                    ? "  ·  " + root.formatWhen(root.refineEdits[root.refineEdits.length - 1].at)
                    : "")
                : ""
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.7
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Column {
          width: parent.width
          visible: historyModel.count > 0
          spacing: Style.spacing.sm

          Text {
            text: "History · " + historyModel.count
            color: root.foreground
            opacity: 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          ListView {
            id: historyList
            width: parent.width
            height: root.listHeight
            model: historyModel
            spacing: Style.spacing.sm
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            keyNavigationWraps: false

            Keys.onPressed: function(event) {
              if (root.actionMenuOpen) {
                if (actionMenu.handleKey(event))
                  event.accepted = true
                return
              }
              if (root.confirmAction !== "") {
                if (confirmDialog.handleKey(event))
                  event.accepted = true
                return
              }
              if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.focusPrompt()
                event.accepted = true
              } else if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier) !== 0) {
                root.themeContextEnabled = !root.themeContextEnabled
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.handleEscape()
                event.accepted = true
              } else if (event.key === Qt.Key_Up && historyList.currentIndex <= 0) {
                root.focusPrompt()
                event.accepted = true
              } else if (event.key === Qt.Key_Delete) {
                root.requestRowAction(historyList.currentIndex)
                event.accepted = true
              } else if (event.key === Qt.Key_T && (event.modifiers & Qt.AltModifier) !== 0) {
                root.createTheme(historyList.currentIndex)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if ((event.modifiers & Qt.AltModifier) !== 0)
                  root.applyWallpaper(historyList.currentIndex)
                else if ((event.modifiers & Qt.ShiftModifier) !== 0)
                  root.reusePrompt(historyList.currentIndex)
                else
                  root.openRowActions(historyList.currentIndex)
                event.accepted = true
              } else if (event.text && event.text.length === 1
                  && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
                root.focusPrompt()
                promptInput.insert(promptInput.cursorPosition, event.text)
                event.accepted = true
              }
            }

            delegate: Rectangle {
              id: row
              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius

              readonly property bool isTarget: !model.pending
                && root.refineRecordId !== ""
                && model.recordId === root.refineRecordId
              readonly property bool hasCursor: historyList.activeFocus && ListView.isCurrentItem

              color: hasCursor ? root.selectedBackground
                : rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accentColor)
                : (model.working || model.pending) ? root.selectedBackground
                : "transparent"

              Rectangle {
                visible: row.isTarget
                width: Style.space(3)
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xs
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: Style.spacing.sm
                anchors.bottomMargin: Style.spacing.sm
                radius: width / 2
                color: root.accentColor
              }

              Rectangle {
                id: thumbnailFrame
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: Style.spacing.xs
                anchors.bottomMargin: Style.spacing.xs
                width: Math.round(height * 16 / 9)
                radius: Math.max(1, root.cornerRadius - Style.spacing.xs)
                color: root.selectedBackground
                clip: true

                Image {
                  anchors.fill: parent
                  source: model.image ? "file://" + model.image : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  sourceSize.width: 320
                }

                Text {
                  anchors.centerIn: parent
                  visible: model.pending
                  text: root.spinnerFrames[root.spinnerFrame]
                  color: root.accentColor
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.title
                }
              }

              Column {
                anchors.left: thumbnailFrame.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Text {
                  width: parent.width
                  text: model.prompt
                  textFormat: Text.PlainText
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: model.pending
                    ? root.spinnerFrames[root.spinnerFrame] + "  Generating…"
                    : model.working
                      ? root.spinnerFrames[root.spinnerFrame] + "  Editing…"
                      : model.themeName + "  ·  " + root.formatWhen(model.updatedAt)
                        + (model.editCount > 0
                          ? "  ·  " + model.editCount + (model.editCount === 1 ? " edit" : " edits")
                          : "")
                  textFormat: Text.PlainText
                  color: (model.pending || model.working) ? root.accentColor : root.foreground
                  opacity: (model.pending || model.working) ? 0.9 : 0.55
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openRowActions(index)
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Math.max(hintText.implicitHeight, themeChip.implicitHeight)

          Text {
            id: hintText
            anchors.left: parent.left
            anchors.right: themeChip.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.inlineError !== "" ? root.inlineError
              : historyList.activeFocus
                ? "Return actions  ·  Tab prompt  ·  Esc"
              : root.refineActive
                ? "Return applies the edit  ·  Alt+Return newline"
                  + (root.refineVersions.length > 1 ? "  ·  Alt+←/→ versions" : "")
                  + "  ·  Esc back"
                : "Return generates  ·  Alt+Return newline"
                  + (historyModel.count > 0 ? "  ·  Tab history" : "")
                  + "  ·  Esc"
            textFormat: Text.PlainText
            color: root.inlineError !== "" ? Color.urgent : root.foreground
            opacity: root.inlineError !== "" ? 1 : 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Button {
            id: themeChip
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.themeContextEnabled ? "󰄲" : "󰄱"
            text: "Match theme"
            fontFamily: Style.font.menuFamily
            fontSize: Style.font.caption
            iconSize: Style.font.bodySmall
            foreground: root.foreground
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.spacing.xs
            tooltipText: "Give the agent the current theme palette. Toggle with Ctrl+T; Shift+Return submits once without it."
            onClicked: root.themeContextEnabled = !root.themeContextEnabled
          }
        }
      }
    }
  }
}
