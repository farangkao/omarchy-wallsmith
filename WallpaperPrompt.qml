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
  property string initialPrompt: ""
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
  readonly property int cardWidth: Math.min(Style.space(520), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(160), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.initialPrompt = String(payload.prompt || "")
    root.themeContextEnabled = payload.themeContextEnabled !== false
    root.opened = true
    Qt.callLater(function() {
      promptInput.text = root.initialPrompt
      promptInput.forceActiveFocus()
      promptInput.cursorPosition = promptInput.text.length
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

  function submit(ignoreThemeContext) {
    var prompt = String(promptInput.text || "").trim()
    if (!prompt) {
      Quickshell.execDetached([
        root.omarchyPath + "/bin/omarchy-notification-send",
        "Wallpaper needs an idea",
        "Describe what you want Codex to create"
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

        Text {
          id: title
          anchors.top: parent.top
          anchors.left: parent.left
          text: "Generate a wallpaper"
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
        }

        Rectangle {
          id: promptBox
          height: Style.space(52)
          anchors.top: title.bottom
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
            text: "A misty brutalist city at sunrise..."
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
    }
  }
}
