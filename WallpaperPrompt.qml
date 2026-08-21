import Quickshell
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
  property string viewMode: "new"
  property string initialPrompt: ""
  property string selectedRecordId: ""
  property bool themeContextEnabled: true

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color mutedForeground: Color.menu.text
  property color border: Color.menu.border
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color scrim: Color.menu.scrim
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(
    Style.space(root.viewMode === "history" ? 680 : 520),
    panel.width - Style.gapsOut * 2
  )
  readonly property int cardHeight: Math.min(
    Style.space(root.viewMode === "history" ? 470 : 160),
    panel.height - Style.gapsOut * 2
  )

  ListModel { id: historyModel }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.viewMode = payload.mode === "history" ? "history" : "new"
    root.initialPrompt = String(payload.prompt || "")
    root.selectedRecordId = ""
    root.themeContextEnabled = payload.themeContextEnabled !== false

    historyModel.clear()
    var history = payload.history || []
    for (var i = 0; i < history.length; i++) {
      var entry = history[i] || ({})
      historyModel.append({
        recordId: String(entry.recordId || ""),
        prompt: String(entry.prompt || "Generated wallpaper"),
        image: String(entry.image || ""),
        themeName: String(entry.themeName || entry.themeSlug || "Unknown theme"),
        updatedAt: String(entry.updatedAt || ""),
        lastInstruction: String(entry.lastInstruction || "")
      })
    }
    historyList.currentIndex = historyModel.count > 0 ? 0 : -1

    root.opened = true
    Qt.callLater(function() {
      if (root.viewMode === "history") {
        historyList.forceActiveFocus()
      } else {
        promptInput.text = root.initialPrompt
        promptInput.forceActiveFocus()
        promptInput.cursorPosition = promptInput.text.length
      }
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
      root.shell.hide((root.manifest && root.manifest.id) || "jesperlugner.wallpaper-agent")
  }

  function beginRefine(index) {
    if (index < 0 || index >= historyModel.count)
      return

    root.selectedRecordId = historyModel.get(index).recordId
    root.viewMode = "refine"
    promptInput.text = ""
    Qt.callLater(function() { promptInput.forceActiveFocus() })
  }

  function reusePrompt(index) {
    if (index < 0 || index >= historyModel.count)
      return

    root.selectedRecordId = ""
    root.viewMode = "new"
    promptInput.text = historyModel.get(index).prompt
    promptInput.cursorPosition = promptInput.text.length
    Qt.callLater(function() { promptInput.forceActiveFocus() })
  }

  function showHistory() {
    root.selectedRecordId = ""
    root.viewMode = "history"
    historyList.currentIndex = historyModel.count > 0 ? Math.max(0, historyList.currentIndex) : -1
    Qt.callLater(function() { historyList.forceActiveFocus() })
  }

  function showNew() {
    root.selectedRecordId = ""
    root.viewMode = "new"
    promptInput.text = ""
    Qt.callLater(function() { promptInput.forceActiveFocus() })
  }

  function submit(ignoreThemeContext) {
    var prompt = String(promptInput.text || "").trim()
    if (!prompt) {
      Quickshell.execDetached([
        root.omarchyPath + "/bin/omarchy-notification-send",
        root.viewMode === "refine" ? "Wallpaper needs a change" : "Wallpaper needs an idea",
        root.viewMode === "refine" ? "Describe what Codex should change" : "Describe what you want Codex to create"
      ])
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
    if (root.viewMode === "refine")
      command.push("--refine", root.selectedRecordId)
    if (!root.themeContextEnabled || ignoreThemeContext === true)
      command.push("--no-theme-context")
    command.push("--prompt", prompt)
    Quickshell.execDetached(command)
    root.dismiss()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jesperlugner-wallpaper-agent"
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
      height: root.cardHeight
      anchors.centerIn: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Item {
          id: promptView
          anchors.fill: parent
          visible: root.viewMode !== "history"

          Text {
            id: promptTitle
            anchors.top: parent.top
            anchors.left: parent.left
            text: root.viewMode === "refine" ? "Refine wallpaper" : "Generate a wallpaper"
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }

          Rectangle {
            width: Style.space(88)
            height: Style.space(30)
            anchors.top: parent.top
            anchors.right: parent.right
            radius: root.cornerRadius
            color: root.selectedBackground
            opacity: promptHistoryMouse.containsMouse ? 1 : 0.72

            Text {
              anchors.centerIn: parent
              text: "History  →"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: promptHistoryMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.showHistory()
            }
          }

          Rectangle {
            id: promptBox
            height: Style.space(52)
            anchors.top: promptTitle.bottom
            anchors.topMargin: Style.spacing.lg
            anchors.left: parent.left
            anchors.right: parent.right
            radius: root.cornerRadius
            color: root.selectedBackground

            Text {
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              verticalAlignment: Text.AlignVCenter
              visible: promptInput.text.length === 0
              text: root.viewMode === "refine"
                ? "Make the water brighter and preserve everything else..."
                : "A misty brutalist city at sunrise..."
              color: root.mutedForeground
              opacity: 0.55
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            TextInput {
              id: promptInput
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              verticalAlignment: TextInput.AlignVCenter
              color: root.selectedText
              selectionColor: Color.menu.selectedBorder
              selectedTextColor: root.selectedText
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              clip: true
              selectByMouse: true
              maximumLength: 600

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.dismiss()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.submit((event.modifiers & Qt.ShiftModifier) !== 0)
                  event.accepted = true
                }
              }
            }
          }

          Text {
            anchors.top: promptBox.bottom
            anchors.topMargin: Style.spacing.md
            anchors.left: parent.left
            text: "Return  ·  Shift+Return ignores theme  ·  Esc"
            color: root.mutedForeground
            opacity: 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          id: historyView
          anchors.fill: parent
          visible: root.viewMode === "history"

          Text {
            id: historyTitle
            anchors.top: parent.top
            anchors.left: parent.left
            text: "Wallpaper history"
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }

          Rectangle {
            width: Style.space(72)
            height: Style.space(30)
            anchors.top: parent.top
            anchors.right: parent.right
            radius: root.cornerRadius
            color: root.selectedBackground
            opacity: historyNewMouse.containsMouse ? 1 : 0.72

            Text {
              anchors.centerIn: parent
              text: "←  New"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: historyNewMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.showNew()
            }
          }

          Text {
            id: historyHint
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "Return edits  ·  Shift+Return reuses prompt  ·  Esc"
            color: root.mutedForeground
            opacity: 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.centerIn: parent
            visible: historyModel.count === 0
            text: "No generated wallpapers yet"
            color: root.mutedForeground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }

          ListView {
            id: historyList
            anchors.top: historyTitle.bottom
            anchors.topMargin: Style.spacing.lg
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: historyHint.top
            anchors.bottomMargin: Style.spacing.md
            visible: historyModel.count > 0
            model: historyModel
            spacing: Style.spacing.sm
            clip: true
            focus: root.viewMode === "history"
            keyNavigationEnabled: true
            keyNavigationWraps: true

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.dismiss()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if ((event.modifiers & Qt.ShiftModifier) !== 0)
                  root.reusePrompt(historyList.currentIndex)
                else
                  root.beginRefine(historyList.currentIndex)
                event.accepted = true
              }
            }

            delegate: Rectangle {
              width: historyList.width
              height: Style.space(76)
              radius: root.cornerRadius
              color: ListView.isCurrentItem ? root.selectedBackground : "transparent"

              Rectangle {
                id: thumbnailFrame
                width: Style.space(104)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: Style.spacing.xs
                anchors.left: parent.left
                radius: Math.max(1, root.cornerRadius - Style.spacing.xs)
                color: root.selectedBackground
                clip: true

                Image {
                  anchors.fill: parent
                  source: "file://" + model.image
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                }
              }

              Text {
                anchors.top: parent.top
                anchors.topMargin: Style.spacing.sm
                anchors.left: thumbnailFrame.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                text: model.prompt
                color: root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              Text {
                anchors.left: thumbnailFrame.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.spacing.sm
                text: model.themeName + "  ·  " + model.updatedAt.replace("T", " ").slice(0, 16)
                color: root.mutedForeground
                opacity: 0.55
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  historyList.currentIndex = index
                  historyList.forceActiveFocus()
                }
                onDoubleClicked: root.beginRefine(index)
              }
            }
          }
        }
      }
    }
  }
}
