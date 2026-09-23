// ═══════════════════════════════════════════════════════════════════════
//  HEXGLASS — HexCombo: a quiet glass dropdown ("SESSION  Hyprland ⌄")
// ═══════════════════════════════════════════════════════════════════════
//  This lives in its OWN FILE on purpose.
//
//  It used to be an inline `component HexCombo: ComboBox { ... }` inside
//  Main.qml. Qt 5.15.13 (Ubuntu 24.04) SEGFAULTS in
//  QQmlObjectCreator::setupBindings when a `delegate` (a QQmlComponent
//  property) declared inside an inline component references that inline
//  component's own id — e.g. `width: cb.width`. The greeter died with a
//  black screen as a result. As a standalone file component the exact same
//  code is fine, so it lives here.
// ═══════════════════════════════════════════════════════════════════════

import QtQuick 2.15
import QtQuick.Controls 2.15

ComboBox {
    id: cb

    // palette (overridable from Main.qml)
    property color hexAccent: "#ac81ff"
    property color hexMid:    "#5d458f"
    property color textMain:  "#ffffff"
    property color textMuted: "#888888"

    // px scale, set by the theme so we track the screen size
    property real s: 1.0
    property string prefix: ""
    // font family comes from Main.qml (FontLoader is per-file)
    property string fontFamily: ""

    implicitHeight: 34 * s
    implicitWidth: Math.max(180 * s, contentItem.implicitWidth + 60 * s)
    hoverEnabled: true
    font.family: fontFamily
    font.pixelSize: 12 * s
    font.letterSpacing: 12 * s * 0.15

    background: Rectangle {
        radius: height / 2
        color: Qt.rgba(0x1a / 255, 0x14 / 255, 0x35 / 255, 0.55)
        border.width: 1
        border.color: cb.hovered || cb.down ? hexAccent : Qt.rgba(0x5d / 255, 0x45 / 255, 0x8f / 255, 0.6)
        Behavior on border.color { ColorAnimation { duration: 200 } }
    }

    contentItem: Row {
        leftPadding: 16 * s
        spacing: 10 * s
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: cb.prefix
            font: cb.font
            color: hexAccent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: cb.displayText
            font: cb.font
            color: textMain
        }
    }

    indicator: Text {
        x: cb.width - width - 14 * s
        anchors.verticalCenter: parent.verticalCenter
        text: "⌄"
        font.pixelSize: 14 * s
        color: textMuted
    }

    delegate: ItemDelegate {
        width: cb.width
        height: 32 * s
        contentItem: Text {
            text: model[cb.textRole]
            font: cb.font
            color: highlighted ? hexAccent : textMain
            verticalAlignment: Text.AlignVCenter
            leftPadding: 12 * s
        }
        background: Rectangle {
            color: highlighted ? Qt.rgba(0x5d / 255, 0x45 / 255, 0x8f / 255, 0.55) : "transparent"
            radius: 6
        }
        highlighted: cb.highlightedIndex === index
    }

    popup: Popup {
        y: -implicitHeight - 6
        width: cb.width
        implicitHeight: Math.min(contentItem.implicitHeight + 12, 320 * s)
        padding: 6
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: cb.popup.visible ? cb.delegateModel : null
            currentIndex: cb.highlightedIndex
        }
        background: Rectangle {
            radius: 10
            color: Qt.rgba(0x0a / 255, 0x07 / 255, 0x15 / 255, 0.92)
            border.width: 1
            border.color: Qt.rgba(0xac / 255, 0x81 / 255, 0xff / 255, 0.5)
        }
    }
}
