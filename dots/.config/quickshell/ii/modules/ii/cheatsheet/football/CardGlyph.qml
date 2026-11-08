import QtQuick

// A booking card, slightly tilted like one held up by the referee.
Rectangle {
    property bool red: false
    property real cardHeight: 14
    width: Math.round(cardHeight * 0.72)
    height: cardHeight
    radius: Math.max(1.5, cardHeight * 0.14)
    rotation: -8
    color: red ? FootballStyle.colRedCard : FootballStyle.colYellowCard
    antialiasing: true
}
