import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "DigestModel.js" as Model

// The once-a-day fullscreen digest.
//
// Deliberately the only interruption this plugin ever makes, and deliberately
// modal: click-outside is not wired to dismiss, because clearing the morning
// briefing should take a real action rather than a stray click. Escape and the
// footer button are the two ways out.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // Driven by the theme, never hardcoded, so `omarchy theme set` restyles the
  // digest live while it is on screen.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  property var digest: Model.EMPTY
  property var items: []
  property string language: "nl"
  property bool animate: true
  property int selectedIndex: -1

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataDir: home + "/.local/share/omarchy-wiki-digest"

  // The counter rolls up from zero on open; `counter` is what the label reads.
  property real counter: 0

  function open(payloadJson) {
    digestFile.reload()
    root.opened = true
    root.selectedIndex = -1
    root.counter = 0
    if (root.animate) counterAnim.restart()
    else root.counter = root.items.length
    Qt.callLater(root.grabKeyboard)
  }

  function close() {
    root.opened = false
  }

  // Only the surface on the focused monitor holds the grab, so the focus call
  // has to find that one rather than whichever was built first.
  signal grabRequested()

  function grabKeyboard() {
    root.grabRequested()
  }

  function dismiss() {
    root.opened = false
    markRead()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "jevido.wiki")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Clearing the badge is the pipeline's job, not the view's — it owns the
  // state directory, and routing through it keeps one writer per file.
  function markRead() {
    Quickshell.execDetached(["omarchy-wiki-digest", "mark-read"])
  }

  function openItem(index) {
    if (index < 0 || index >= root.items.length) return
    var url = root.items[index].url
    if (!url) return
    Quickshell.execDetached(["xdg-open", url])
    root.dismiss()
  }

  function move(delta) {
    if (root.items.length === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next >= root.items.length) next = root.items.length - 1
    root.selectedIndex = next
    scroller.ensureVisible(next)
  }

  function reload(raw) {
    var parsed = Model.parse(raw)
    root.digest = parsed
    root.items = Model.sorted(parsed.items)
  }

  FileView {
    id: digestFile
    path: root.dataDir + "/digest.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.reload(text())
    // `text()` is stale inside the change signal itself, so both paths route
    // through reload() → onLoaded and always parse fresh content.
    onFileChanged: reload()
    onLoadFailed: root.reload("")
  }

  FileView {
    id: configFile
    path: root.home + "/.config/omarchy/wiki-digest.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.language = JSON.parse(text()).language || "nl"
      } catch (e) {
        root.language = "nl"
      }
    }
    onFileChanged: reload()
  }

  NumberAnimation {
    id: counterAnim
    target: root
    property: "counter"
    from: 0
    to: root.items.length
    duration: 620
    easing.type: Easing.OutCubic
  }

  // One surface per monitor. A digest that lands on the other screen is a
  // digest that gets missed, which is the one thing this app may not do -- so
  // it renders everywhere and only the focused monitor takes the keyboard.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      readonly property bool primary: !Hyprland.focusedMonitor
                                      || Hyprland.focusedMonitor.name === modelData.name
      readonly property int cardWidth: Math.min(Style.space(1100), modelData.width - Style.gapsOut * 8)
      readonly property int cardHeight: Math.min(Style.space(820), modelData.height - Style.gapsOut * 8)

      screen: modelData
      visible: root.opened
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-wikipulse"
      WlrLayershell.layer: WlrLayer.Overlay
      // Two surfaces cannot both hold an exclusive grab; the focused one wins.
      WlrLayershell.keyboardFocus: root.opened && primary
                                   ? WlrKeyboardFocus.Exclusive
                                   : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Rectangle {
        anchors.fill: parent
        color: root.scrim
        opacity: root.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      }

      BorderSurface {
        id: card
        width: panel.cardWidth
        // On a quiet day the card is two lines of text; framing that with a
        // screen of empty panel would read as a broken layout, not as calm.
        height: root.items.length === 0
                ? content.implicitHeight + card.contentTopInset + card.contentBottomInset
                  + footer.height + Style.space(14)
                : panel.cardHeight
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        radius: Style.cornerRadius
        anchors.centerIn: parent
        color: root.background
        borderSpec: root.borderSpec
        padding: Style.spacing.panelPadding

        scale: root.opened ? 1.0 : 0.96
        opacity: root.opened ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Item {
          id: keyCatcher
          anchors.fill: parent
          focus: panel.primary
          Keys.priority: Keys.BeforeItem

          Connections {
            target: root
            function onGrabRequested() {
              if (panel.primary) keyCatcher.forceActiveFocus()
            }
          }

          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) {
              root.dismiss()
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
              root.move(1)
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
              root.move(-1)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.openItem(root.selectedIndex < 0 ? 0 : root.selectedIndex)
            } else {
              return
            }
            event.accepted = true
          }
        }

        Column {
          id: content
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: Style.spacing.md

          // ---- header -------------------------------------------------------
          Item {
            width: parent.width
            height: headerCol.implicitHeight + Style.space(10)

            Column {
              id: headerCol
              width: parent.width
              spacing: Style.space(4)

              Row {
                spacing: Style.space(12)

                Text {
                  text: Math.round(root.counter)
                  visible: root.items.length > 0
                  color: root.accent
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }

                Column {
                  spacing: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: Model.headlineFor(root.digest, root.language)
                    color: root.foreground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }

                  Text {
                    text: Model.subtitleFor(root.digest, root.language)
                    visible: text !== ""
                    color: root.foreground
                    opacity: 0.6
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // The sweep is the one piece of pure decoration here: it reads as
            // "this just arrived" without another colour or another word.
            Rectangle {
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              height: Math.max(2, Style.space(2))
              radius: height / 2
              color: root.accent
              width: root.opened ? parent.width : 0
              Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            }
          }

          // ---- tldr ---------------------------------------------------------
          Text {
            width: parent.width
            visible: text !== ""
            text: root.digest.tldr || ""
            color: root.foreground
            opacity: root.opened ? 0.92 : 0
            wrapMode: Text.WordWrap
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
            lineHeight: 1.35
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: Model.degradedNotice(root.digest, root.language)
            color: root.accent
            opacity: 0.85
            wrapMode: Text.WordWrap
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          // ---- items --------------------------------------------------------
          Flickable {
            id: scroller
            width: parent.width
            // Nothing tall on an empty day: the card shrinks to its text
            // instead of framing a screen of void.
            height: root.items.length === 0
                    ? 0
                    : Math.max(0, parent.height - y - footer.height - Style.space(10))
            contentHeight: itemColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            function ensureVisible(index) {
              if (index < 0 || index >= itemRepeater.count) return
              var entry = itemRepeater.itemAt(index)
              if (!entry) return
              if (entry.y < contentY) contentY = entry.y
              else if (entry.y + entry.height > contentY + height)
                contentY = entry.y + entry.height - height
            }

            Column {
              id: itemColumn
              width: scroller.width
              spacing: Style.space(8)

              Repeater {
                id: itemRepeater
                model: root.items

                DigestCard {
                  required property int index
                  required property var modelData

                  width: itemColumn.width
                  entry: modelData
                  position: index
                  language: root.language
                  selected: root.selectedIndex === index
                  animate: root.animate
                  revealed: root.opened
                  onActivated: root.openItem(index)
                  onHovered: root.selectedIndex = index
                }
              }
            }
          }
        }

        // ---- footer ---------------------------------------------------------
        // A hard cut at the fold hides that there is more; this says so without
        // adding a scrollbar to a surface meant to be read, not operated.
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top
          anchors.leftMargin: card.contentLeftInset
          anchors.rightMargin: card.contentRightInset
          height: Style.space(30)
          visible: scroller.contentHeight > scroller.height + 2
          opacity: scroller.atYEnd ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 160 } }
          gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: root.background }
          }
        }

        Row {
          id: footer
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.language === "nl" ? "↑↓ kiezen · ⏎ openen" : "↑↓ select · ⏎ open"
            color: root.foreground
            opacity: 0.45
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            text: root.language === "nl" ? "Gezien" : "Got it"
            onClicked: root.dismiss()
          }
        }
      }
    }
  }

  IpcHandler {
    target: "jevido.wiki"
    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function show(): void { root.open("{}") }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { digestFile.reload() }
  }
}
