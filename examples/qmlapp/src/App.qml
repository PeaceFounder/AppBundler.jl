import QtQuick
import QtQuick.Window
import QtQuick.Controls
import jlqml

ApplicationWindow {
    title: "QMLApp"
    width: 300
    height: 300
    visible: true

    Rectangle {

        anchors.fill : parent
        color: "lightgrey"
        
        Text { 
            anchors.centerIn : parent 
            text : "Hello World!" 
            font.pointSize : 32 
            color : "black" 
        } 
    }
}
