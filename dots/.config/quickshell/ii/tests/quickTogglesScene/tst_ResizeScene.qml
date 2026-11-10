import QtQuick
import QtTest
import qs.services
import "style" as Style

TestCase {
    id: test
    name: "QuickToggleResizeScene"
    width: 800; height: 700
    visible: true
    when: windowShown
    property var pages: [[{id:"bluetooth",type:"bluetooth",sizeW:2,sizeH:1}]]
    property var config: ({pages:pages,layoutVersion:2})
    Item {
        id: panel
        anchors.fill: parent
        property alias editController: controller
        property int currentPage: 0
        Style.QuickToggleEditController {
            id: controller
            config: test.config
            persistedPages: test.pages
        }
        Style.AndroidBluetoothToggle {
            id: tile
            buttonIndex: 0
            buttonData: !visible ? {id:"bluetooth",type:"bluetooth",sizeW:2,sizeH:1} : (controller.active ? controller.draftPages[0][0] : test.config.pages[0][0])
            baseCellWidth: 80; baseCellHeight: 56; cellSpacing: 6; cellSize: 2
            editMode: true
            panel: panel
        }
    }
    Component {
        id: sliderComponent
        Style.AndroidSliderWidgetBase {
            buttonIndex: 0
            buttonData: controller.active ? controller.draftPages[0][0] : test.config.pages[0][0]
            baseCellWidth: 80; baseCellHeight: 56; cellSpacing: 6; cellSize: 2
            editMode: true
            materialSymbol: "volume_up"
            sliderValue: 0.5
            panel: panel
        }
    }
    Component {
        id: mediaComponent
        Style.AndroidMediaWidgetToggle {
            buttonIndex: 0
            buttonData: controller.active ? controller.draftPages[0][0] : test.config.pages[0][0]
            baseCellWidth: 80; baseCellHeight: 56; cellSpacing: 6; cellSize: 2
            editMode: true
            panel: panel
        }
    }
    QtObject {
        id: fakePlayer
        property bool isPlaying: true
        property string trackTitle: "Track"
        property string trackArtist: "Artist"
        property string name: "Headphones"
        property string icon: "headset"
        property string address: "test"
        property real battery: 0.8
        property bool batteryAvailable: true
        function togglePlaying() { isPlaying = !isPlaying; }
        function previous() {}
        function next() {}
    }
    function init() {
        tile.visible = true;
        controller.cancel();
        test.pages = [[{id:"bluetooth",type:"bluetooth",sizeW:2,sizeH:1}]];
        test.config = {pages:test.pages,layoutVersion:2};
        wait(150);
    }
    function editor(target) {
        target = target || tile;
        for (var i=0;i<target.children.length;i++) {
            var child=target.children[i];
            if (typeof child.previewResize === "function") return child;
        }
        return null;
    }
    function test_live_pixels_shared_icon_and_single_commit() {
        var e=editor(); verify(e);
        var icon=findChild(tile,"quickToggleSharedIcon"); verify(icon);
        var iconY=icon.y;
        var surface=e.visualItem;
        compare(surface.width,166); compare(surface.height,56);
        verify(e.beginResize());
        e.previewResize(7.5,14.25);
        compare(surface.width,173.5); compare(surface.height,70.25);
        compare(test.config.pages[0][0].sizeH,1);
        compare(controller.draftPages[0][0].sizeH,1);
        e.previewResize(86,62);
        compare(surface.width,252); compare(surface.height,118);
        compare(findChild(tile,"quickToggleSharedIcon"),icon);
        verify(icon.y !== iconY);
        compare(test.config.pages[0][0].sizeW,2);
        e.finishResize();
        compare(test.config.pages[0][0].sizeW,3);
        compare(test.config.pages[0][0].sizeH,2);
        tryCompare(surface,"width",252,500);
        compare(findChild(tile,"quickToggleSharedIcon"),icon);
    }
    function test_cancel_settles_to_original_and_stops_grab() {
        var e=editor(); verify(e.beginResize());
        e.previewResize(86,62);
        controller.cancelResize();
        verify(!e.resizing);
        e.previewResize(172,124);
        compare(test.config.pages[0][0].sizeH,1);
        tryCompare(e.visualItem,"height",56,500);
        verify(e.beginResize());
        e.previewResize(0,20);
        e.cancelResize();
        tryCompare(e.visualItem,"height",56,500);
    }
    function test_diagonal_mouse_grab_keeps_pointer_attached() {
        var area=findChild(tile,"quickToggleResizeArea"); verify(area);
        var e=editor();
        mousePress(area,area.width-9,area.height-9,Qt.LeftButton);
        verify(e.resizing);
        var start=area.mapToItem(test,area.width-9,area.height-9);
        mouseMove(test,start.x+12,start.y+15,20);
        compare(e.visualItem.width,178);
        compare(e.visualItem.height,71);
        mouseMove(test,start.x+86,start.y+62,20);
        compare(e.visualItem.width,252);
        compare(e.visualItem.height,118);
        mouseRelease(test,start.x+86,start.y+62,Qt.LeftButton);
        verify(!controller.active);
        compare(test.config.pages[0][0].sizeW,3);
    }

    function test_slider_rotates_one_control_continuously() {
        tile.visible = false;
        test.pages = [[{id:"volume",type:"volumeSlider",sizeW:2,sizeH:1}]];
        test.config = {pages:test.pages,layoutVersion:2};
        var slider = createTemporaryObject(sliderComponent,panel,{panel:panel});
        verify(slider);
        var e=editor(slider); verify(e);
        verify(e.beginResize());
        var startH=e.visualItem.height;
        e.previewResize(0,100);
        compare(e.visualItem.height,startH+100);
        verify(slider.verticalProgress > 0 && slider.verticalProgress < 1);
        var track=findChild(slider,"quickToggleSharedSlider"); verify(track);
        e.previewResize(0,150);
        compare(findChild(slider,"quickToggleSharedSlider"),track);
        compare(track.value,0.5);
        e.cancelResize();
        tryCompare(slider,"verticalProgress",0,500);
        compare(track.value,0.5);
    }
    function test_media_playback_identity_survives_every_size() {
        tile.visible = false;
        MprisController.activePlayer = fakePlayer;
        test.pages = [[{id:"media",type:"mediaWidget",sizeW:2,sizeH:1}]];
        test.config = {pages:test.pages,layoutVersion:2};
        var media = createTemporaryObject(mediaComponent,panel,{panel:panel});
        verify(media);
        var play=findChild(media,"quickToggleSharedPlay"); verify(play);
        var e=editor(media); verify(e.beginResize());
        e.previewResize(0,62);
        compare(findChild(media,"quickToggleSharedPlay"),play);
        e.previewResize(172,62);
        compare(findChild(media,"quickToggleSharedPlay"),play);
        e.finishResize();
        compare(test.config.pages[0][0].sizeW,4);
        tryCompare(e.visualItem,"width",338,500);
        verify(fakePlayer.isPlaying);
        play.clicked();
        verify(!fakePlayer.isPlaying);
        MprisController.activePlayer = null;
    }
    function test_bluetooth_artwork_stays_alive_on_reversal() {
        BluetoothStatus.connected = true;
        BluetoothStatus.firstActiveDevice = fakePlayer;
        var e=editor(); verify(e.beginResize());
        e.previewResize(0,62);
        var icon=findChild(tile,"quickToggleSharedIcon");
        verify(icon);
        e.previewResize(86,62);
        compare(findChild(tile,"quickToggleSharedIcon"),icon);
        e.previewResize(0,20);
        e.previewResize(0,62);
        compare(findChild(tile,"quickToggleSharedIcon"),icon);
        e.cancelResize();
        BluetoothStatus.connected = false;
        BluetoothStatus.firstActiveDevice = null;
    }
}
