.pragma library

// Keys that wake the Always On Display. A modifier held on its own is not typing, and
// Super is the first half of the shortcut that toggles the AOD: waking on it would
// let the rest of the chord raise it again at once.
const IGNORED = [
    Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta,
    Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Hyper_L, Qt.Key_Hyper_R
];

function keyWakes(key) {
    return IGNORED.indexOf(key) === -1;
}
