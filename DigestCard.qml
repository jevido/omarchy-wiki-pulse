import QtQuick
import qs.Commons
import qs.Ui
import "DigestModel.js" as Model

// One changed document. Staggers in on reveal, and pulses its accent once when
// it is something actually waiting on the reader — once, not on a loop, so it
// points without nagging.
Item {
  id: card

  property var entry: ({})
  property int position: 0
  property string language: "nl"
  property bool selected: false
  property bool animate: true
  property bool revealed: false

  signal activated()
  signal hovered()

  readonly property bool urgent: entry.suggestedAction === "blocked-on-me"
  readonly property color accent: urgent ? Color.accent : Color.menu.text
  readonly property color surface: card.selected ? Color.menu.selectedBackground : "transparent"

  implicitHeight: body.implicitHeight + Style.space(20)
  height: implicitHeight

  // Stagger: 45ms per row, so the list assembles itself rather than appearing
  // all at once. Capped so a 40-item digest does not take two seconds to land.
  readonly property int revealDelay: Math.min(card.position * 45, 900)

  opacity: 0
  transform: Translate { id: slide; y: 24 }

  states: State {
    name: "shown"
    when: card.revealed
    PropertyChanges { target: card; opacity: 1 }
    PropertyChanges { target: slide; y: 0 }
  }

  transitions: Transition {
    to: "shown"
    SequentialAnimation {
      PauseAnimation { duration: card.animate ? card.revealDelay : 0 }
      ParallelAnimation {
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: card.animate ? 260 : 0; easing.type: Easing.OutCubic }
        NumberAnimation { target: slide; property: "y"; to: 0; duration: card.animate ? 300 : 0; easing.type: Easing.OutCubic }
      }
      ScriptAction { script: if (card.urgent && card.animate) pulse.start() }
    }
  }

  SequentialAnimation {
    id: pulse
    NumberAnimation { target: rail; property: "opacity"; to: 0.25; duration: 220; easing.type: Easing.OutCubic }
    NumberAnimation { target: rail; property: "opacity"; to: 1.0;  duration: 420; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: card.surface
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  // The priority rail carries the colour so the text never has to.
  Rectangle {
    id: rail
    width: Math.max(2, Style.space(3))
    radius: width / 2
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(6)
    anchors.bottomMargin: Style.space(6)
    color: card.accent
    opacity: card.urgent ? 1 : (card.entry.priority === "high" ? 0.75 : 0.28)
  }

  Column {
    id: body
    anchors.left: rail.right
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(3)

    Row {
      spacing: Style.space(8)
      width: parent.width

      Text {
        text: Model.actionGlyph(card.entry.suggestedAction)
        visible: text !== ""
        color: card.accent
        opacity: card.urgent ? 1 : 0.55
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: card.entry.title || ""
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.title
        font.bold: card.entry.priority === "high"
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width - Style.space(180))
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: Model.actionLabel(card.entry.suggestedAction, card.language)
        visible: card.urgent
        color: Color.accent
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      width: parent.width
      text: card.entry.summary || ""
      visible: text !== ""
      color: Color.menu.text
      opacity: 0.85
      wrapMode: Text.WordWrap
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }

    Text {
      width: parent.width
      text: "→ " + (card.entry.whyItMattersToMe || "")
      visible: (card.entry.whyItMattersToMe || "") !== ""
      color: Color.accent
      opacity: 0.8
      wrapMode: Text.WordWrap
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      color: Color.menu.text
      opacity: 0.45
      elide: Text.ElideRight
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
      // `status` only ever has a value on a ticket, so the meta line tells the
      // two sources apart without a badge that would have to be styled.
      text: [
        (card.entry.collection && card.entry.collection.name) || "",
        card.entry.status || "",
        (card.entry.author && card.entry.author.name) || "",
        Model.changeLabel(card.entry.changeKind, card.language, card.entry.source),
        Model.relativeTime(card.entry.updatedAt, card.language)
      ].filter(function (part) { return part !== "" }).join("  ·  ")
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) card.hovered()
    onClicked: card.activated()
  }
}
