#include <algorithm>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <iostream>
#include <map>
#include <poll.h>
#include <set>
#include <string>
#include <string_view>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <unordered_map>
#include <vector>

#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <xkbcommon/xkbcommon.h>

namespace {

constexpr double RESCAN_INTERVAL = 2.0;
constexpr double DEDUP_WINDOW = 0.015;

using Clock = std::chrono::steady_clock;

volatile std::sig_atomic_t g_running = 1;

void handle_signal(int sig) {
    (void)sig;
    g_running = 0;
}

void init_process() {
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() == 1) {
        std::exit(0);
    }
    std::signal(SIGPIPE, SIG_IGN);
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);
}

// ---------------------------------------------------------------------------
// JSON Utilities
// ---------------------------------------------------------------------------

std::string json_escape(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (size_t i = 0; i < s.size(); ++i) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
                break;
        }
    }
    return out;
}

void emit_json(std::string_view s) {
    if (fwrite(s.data(), 1, s.size(), stdout) < s.size() || fputc('\n', stdout) == EOF) {
        if (errno == EPIPE) {
            std::exit(0);
        }
    }
    if (fflush(stdout) == EOF) {
        if (errno == EPIPE) {
            std::exit(0);
        }
    }
}

void emit_note(std::string_view message) {
    std::string out;
    out.reserve(message.size() + 32);
    out += "{\"type\":\"note\",\"message\":\"";
    out += json_escape(message);
    out += "\"}";
    emit_json(out);
}

void emit_error(std::string_view message) {
    std::string out;
    out.reserve(message.size() + 32);
    out += "{\"type\":\"error\",\"message\":\"";
    out += json_escape(message);
    out += "\"}";
    emit_json(out);
}

void emit_ready(int devices, std::string_view layout, bool layout_aware) {
    std::string out;
    out.reserve(layout.size() + 64);
    out += "{\"type\":\"ready\",\"devices\":";
    out += std::to_string(devices);
    out += ",\"layout\":\"";
    out += json_escape(layout);
    out += "\",\"layoutAware\":";
    out += (layout_aware ? "true" : "false");
    out += "}";
    emit_json(out);
}

void emit_release(std::string_view label) {
    std::string out;
    out.reserve(label.size() + 32);
    out += "{\"type\":\"release\",\"label\":\"";
    out += json_escape(label);
    out += "\"}";
    emit_json(out);
}

void emit_key(std::string_view kind,
              std::string_view label,
              const std::vector<std::string>& modifiers,
              bool repeat) {
    std::string out;
    out.reserve(kind.size() + label.size() + 64 + modifiers.size() * 12);
    out += "{\"type\":\"key\",\"kind\":\"";
    out += json_escape(kind);
    out += "\",\"label\":\"";
    out += json_escape(label);
    out += "\",\"modifiers\":[";
    for (size_t i = 0; i < modifiers.size(); ++i) {
        if (i > 0) out += ",";
        out += "\"";
        out += json_escape(modifiers[i]);
        out += "\"";
    }
    out += "],\"repeat\":";
    out += (repeat ? "true" : "false");
    out += "}";
    emit_json(out);
}

// ---------------------------------------------------------------------------
// UTF-8 Helpers
// ---------------------------------------------------------------------------

inline size_t utf8_codepoint_len(std::string_view s) {
    size_t count = 0;
    for (unsigned char c : s) {
        if ((c & 0xC0) != 0x80) {
            ++count;
        }
    }
    return count;
}

inline bool is_printable_utf8(std::string_view s) {
    if (s.empty()) return false;
    for (unsigned char c : s) {
        if (c < 0x20 || c == 0x7f) {
            return false;
        }
    }
    return true;
}

// ---------------------------------------------------------------------------
// Key Tables
// ---------------------------------------------------------------------------

const std::unordered_map<int, const char*> MODIFIER_KEYS = {
    {KEY_LEFTCTRL, "Ctrl"},
    {KEY_RIGHTCTRL, "Ctrl"},
    {KEY_LEFTSHIFT, "Shift"},
    {KEY_RIGHTSHIFT, "Shift"},
    {KEY_LEFTALT, "Alt"},
    {KEY_RIGHTALT, "AltGr"},
    {KEY_LEFTMETA, "Super"},
    {KEY_RIGHTMETA, "Super"},
};

const std::unordered_map<int, const char*> MOUSE_BUTTONS = {
    {BTN_LEFT, "Click"},
    {BTN_RIGHT, "Right click"},
    {BTN_MIDDLE, "Middle click"},
    {BTN_SIDE, "Back"},
    {BTN_EXTRA, "Forward"},
};

const std::unordered_map<std::string_view, const char*> SYM_RENAMES = {
    {"Return", "Enter"},
    {"Escape", "Esc"},
    {"Prior", "PgUp"},
    {"Next", "PgDn"},
    {"BackSpace", "Backspace"},
    {"Up", "↑"},
    {"Down", "↓"},
    {"Left", "←"},
    {"Right", "→"},
    {"space", "Space"},
    {"ISO_Level3_Shift", "AltGr"},
};

std::unordered_map<int, std::string> init_named_keys() {
    std::unordered_map<int, std::string> m = {
        {KEY_ESC, "Esc"},
        {KEY_TAB, "Tab"},
        {KEY_ENTER, "Enter"},
        {KEY_KPENTER, "Enter"},
        {KEY_BACKSPACE, "Backspace"},
        {KEY_DELETE, "Delete"},
        {KEY_INSERT, "Insert"},
        {KEY_HOME, "Home"},
        {KEY_END, "End"},
        {KEY_PAGEUP, "PgUp"},
        {KEY_PAGEDOWN, "PgDn"},
        {KEY_UP, "↑"},
        {KEY_DOWN, "↓"},
        {KEY_LEFT, "←"},
        {KEY_RIGHT, "→"},
        {KEY_CAPSLOCK, "CapsLock"},
        {KEY_NUMLOCK, "NumLock"},
        {KEY_SCROLLLOCK, "ScrollLock"},
        {KEY_SPACE, "Space"},
        {KEY_SYSRQ, "PrtSc"},
        {KEY_PAUSE, "Pause"},
        {KEY_MENU, "Menu"},
        {KEY_COMPOSE, "Menu"},
    };
    for (int fn = 1; fn <= 24; ++fn) {
        int code = -1;
        switch (fn) {
            case 1: code = KEY_F1; break;
            case 2: code = KEY_F2; break;
            case 3: code = KEY_F3; break;
            case 4: code = KEY_F4; break;
            case 5: code = KEY_F5; break;
            case 6: code = KEY_F6; break;
            case 7: code = KEY_F7; break;
            case 8: code = KEY_F8; break;
            case 9: code = KEY_F9; break;
            case 10: code = KEY_F10; break;
            case 11: code = KEY_F11; break;
            case 12: code = KEY_F12; break;
            case 13: code = KEY_F13; break;
            case 14: code = KEY_F14; break;
            case 15: code = KEY_F15; break;
            case 16: code = KEY_F16; break;
            case 17: code = KEY_F17; break;
            case 18: code = KEY_F18; break;
            case 19: code = KEY_F19; break;
            case 20: code = KEY_F20; break;
            case 21: code = KEY_F21; break;
            case 22: code = KEY_F22; break;
            case 23: code = KEY_F23; break;
            case 24: code = KEY_F24; break;
            default: break;
        }
        if (code >= 0) {
            m[code] = "F" + std::to_string(fn);
        }
    }
    return m;
}

const std::unordered_map<int, std::string> NAMED_KEYS = init_named_keys();

const std::unordered_map<int, const char*> FALLBACK_US_KEYS = {
    {0, "Reserved"},
    {1, "Esc"},
    {2, "1"},
    {3, "2"},
    {4, "3"},
    {5, "4"},
    {6, "5"},
    {7, "6"},
    {8, "7"},
    {9, "8"},
    {10, "9"},
    {11, "0"},
    {12, "Minus"},
    {13, "Equal"},
    {14, "Backspace"},
    {15, "Tab"},
    {16, "Q"},
    {17, "W"},
    {18, "E"},
    {19, "R"},
    {20, "T"},
    {21, "Y"},
    {22, "U"},
    {23, "I"},
    {24, "O"},
    {25, "P"},
    {26, "Leftbrace"},
    {27, "Rightbrace"},
    {28, "Enter"},
    {29, "Leftctrl"},
    {30, "A"},
    {31, "S"},
    {32, "D"},
    {33, "F"},
    {34, "G"},
    {35, "H"},
    {36, "J"},
    {37, "K"},
    {38, "L"},
    {39, "Semicolon"},
    {40, "Apostrophe"},
    {41, "Grave"},
    {42, "Leftshift"},
    {43, "Backslash"},
    {44, "Z"},
    {45, "X"},
    {46, "C"},
    {47, "V"},
    {48, "B"},
    {49, "N"},
    {50, "M"},
    {51, "Comma"},
    {52, "Dot"},
    {53, "Slash"},
    {54, "Rightshift"},
    {55, "Kpasterisk"},
    {56, "Leftalt"},
    {57, "Space"},
    {58, "Capslock"},
    {59, "F1"},
    {60, "F2"},
    {61, "F3"},
    {62, "F4"},
    {63, "F5"},
    {64, "F6"},
    {65, "F7"},
    {66, "F8"},
    {67, "F9"},
    {68, "F10"},
    {69, "Numlock"},
    {70, "Scrolllock"},
    {71, "Kp7"},
    {72, "Kp8"},
    {73, "Kp9"},
    {74, "Kpminus"},
    {75, "Kp4"},
    {76, "Kp5"},
    {77, "Kp6"},
    {78, "Kpplus"},
    {79, "Kp1"},
    {80, "Kp2"},
    {81, "Kp3"},
    {82, "Kp0"},
    {83, "Kpdot"},
    {85, "Zenkakuhankaku"},
    {86, "102Nd"},
    {87, "F11"},
    {88, "F12"},
    {89, "Ro"},
    {90, "Katakana"},
    {91, "Hiragana"},
    {92, "Henkan"},
    {93, "Katakanahiragana"},
    {94, "Muhenkan"},
    {95, "Kpjpcomma"},
    {96, "Kpenter"},
    {97, "Rightctrl"},
    {98, "Kpslash"},
    {99, "Sysrq"},
    {100, "Rightalt"},
    {101, "Linefeed"},
    {102, "Home"},
    {103, "Up"},
    {104, "Pageup"},
    {105, "Left"},
    {106, "Right"},
    {107, "End"},
    {108, "Down"},
    {109, "Pagedown"},
    {110, "Insert"},
    {111, "Delete"},
    {112, "Macro"},
    {113, "Mute"},
    {114, "Volumedown"},
    {115, "Volumeup"},
    {116, "Power"},
    {117, "Kpequal"},
    {118, "Kpplusminus"},
    {119, "Pause"},
    {120, "Scale"},
    {121, "Kpcomma"},
    {122, "Hangeul"},
    {123, "Hanja"},
    {124, "Yen"},
    {125, "Leftmeta"},
    {126, "Rightmeta"},
    {127, "Compose"},
    {128, "Stop"},
    {129, "Again"},
    {130, "Props"},
    {131, "Undo"},
    {132, "Front"},
    {133, "Copy"},
    {134, "Open"},
    {135, "Paste"},
    {136, "Find"},
    {137, "Cut"},
    {138, "Help"},
    {139, "Menu"},
    {140, "Calc"},
    {141, "Setup"},
    {142, "Sleep"},
    {143, "Wakeup"},
    {144, "File"},
    {145, "Sendfile"},
    {146, "Deletefile"},
    {147, "Xfer"},
    {148, "Prog1"},
    {149, "Prog2"},
    {150, "Www"},
    {151, "Msdos"},
    {152, "Coffee"},
    {153, "Rotate Display"},
    {154, "Cyclewindows"},
    {155, "Mail"},
    {156, "Bookmarks"},
    {157, "Computer"},
    {158, "Back"},
    {159, "Forward"},
    {160, "Closecd"},
    {161, "Ejectcd"},
    {162, "Ejectclosecd"},
    {163, "Nextsong"},
    {164, "Playpause"},
    {165, "Previoussong"},
    {166, "Stopcd"},
    {167, "Record"},
    {168, "Rewind"},
    {169, "Phone"},
    {170, "Iso"},
    {171, "Config"},
    {172, "Homepage"},
    {173, "Refresh"},
    {174, "Exit"},
    {175, "Move"},
    {176, "Edit"},
    {177, "Scrollup"},
    {178, "Scrolldown"},
    {179, "Kpleftparen"},
    {180, "Kprightparen"},
    {181, "New"},
    {182, "Redo"},
    {183, "F13"},
    {184, "F14"},
    {185, "F15"},
    {186, "F16"},
    {187, "F17"},
    {188, "F18"},
    {189, "F19"},
    {190, "F20"},
    {191, "F21"},
    {192, "F22"},
    {193, "F23"},
    {194, "F24"},
    {200, "Playcd"},
    {201, "Pausecd"},
    {202, "Prog3"},
    {203, "Prog4"},
    {204, "Dashboard"},
    {205, "Suspend"},
    {206, "Close"},
    {207, "Play"},
    {208, "Fastforward"},
    {209, "Bassboost"},
    {210, "Print"},
    {211, "Hp"},
    {212, "Camera"},
    {213, "Sound"},
    {214, "Question"},
    {215, "Email"},
    {216, "Chat"},
    {217, "Search"},
    {218, "Connect"},
    {219, "Finance"},
    {220, "Sport"},
    {221, "Shop"},
    {222, "Alterase"},
    {223, "Cancel"},
    {224, "Brightnessdown"},
    {225, "Brightnessup"},
    {226, "Media"},
    {227, "Switchvideomode"},
    {228, "Kbdillumtoggle"},
    {229, "Kbdillumdown"},
    {230, "Kbdillumup"},
    {231, "Send"},
    {232, "Reply"},
    {233, "Forwardmail"},
    {234, "Save"},
    {235, "Documents"},
    {236, "Battery"},
    {237, "Bluetooth"},
    {238, "Wlan"},
    {239, "Uwb"},
    {240, "Unknown"},
    {241, "Video Next"},
    {242, "Video Prev"},
    {243, "Brightness Cycle"},
    {244, "Brightness Auto"},
    {245, "Display Off"},
    {246, "Wimax"},
    {247, "Rfkill"},
    {248, "Micmute"},
    {256, "0"},
    {257, "1"},
    {258, "2"},
    {259, "3"},
    {260, "4"},
    {261, "5"},
    {262, "6"},
    {263, "7"},
    {264, "8"},
    {265, "9"},
    {288, "Ok"},
    {289, "Select"},
    {290, "Goto"},
    {291, "Clear"},
    {292, "Power2"},
    {293, "Option"},
    {294, "Info"},
    {295, "Time"},
    {296, "Vendor"},
    {297, "Archive"},
    {298, "Program"},
    {299, "Channel"},
    {300, "Favorites"},
    {301, "Epg"},
    {302, "Pvr"},
    {303, "Mhp"},
    {304, "Language"},
    {305, "Title"},
    {306, "Subtitle"},
    {307, "Angle"},
    {308, "Full Screen"},
    {309, "Mode"},
    {310, "Keyboard"},
    {311, "Aspect Ratio"},
    {312, "Pc"},
    {313, "Tvh"},
    {314, "Tvh2"},
    {315, "Vcr"},
    {316, "Vcr2"},
    {317, "Sat"},
    {318, "Sat2"},
    {319, "Cd"},
    {320, "Tape"},
    {321, "Radio"},
    {322, "Tuner"},
    {323, "Player"},
    {324, "Text"},
    {325, "Dvd"},
    {326, "Aux"},
    {327, "Mp3"},
    {328, "Audio"},
    {329, "Video"},
    {330, "Directory"},
    {331, "List"},
    {332, "Memo"},
    {333, "Calendar"},
    {334, "Red"},
    {335, "Green"},
    {336, "Yellow"},
    {337, "Blue"},
    {338, "Channelup"},
    {339, "Channeldown"},
    {340, "First"},
    {341, "Last"},
    {342, "Ab"},
    {343, "Next"},
    {344, "Restart"},
    {345, "Slow"},
    {346, "Shuffle"},
    {347, "Break"},
    {348, "Previous"},
    {349, "Digits"},
    {350, "Teen"},
    {351, "Twen"},
    {352, "Videophone"},
    {353, "Games"},
    {354, "Zoomin"},
    {355, "Zoomout"},
    {356, "Zoomreset"},
    {357, "Wordprocessor"},
    {358, "Editor"},
    {359, "Spreadsheet"},
    {360, "Graphicseditor"},
    {361, "Presentation"},
    {362, "Database"},
    {363, "Newssheet"},
    {364, "Voicemail"},
    {365, "Addressbook"},
    {366, "Messenger"},
    {367, "Displaytoggle"},
    {368, "Spellcheck"},
    {369, "Logoff"},
    {370, "Dollar"},
    {371, "Euro"},
    {372, "Frameback"},
    {373, "Frameforward"},
    {374, "Context Menu"},
    {375, "Media Repeat"},
    {376, "10Channelsup"},
    {377, "10Channelsdown"},
    {378, "Images"},
    {379, "Notification Center"},
    {380, "Pickup Phone"},
    {381, "Hangup Phone"},
    {384, "Del Eol"},
    {385, "Del Eos"},
    {386, "Ins Char"},
    {387, "Del Char"},
    {388, "Fn"},
    {389, "Fn Esc"},
    {390, "Fn F1"},
    {391, "Fn F2"},
    {392, "Fn F3"},
    {393, "Fn F4"},
    {394, "Fn F5"},
    {395, "Fn F6"},
    {396, "Fn F7"},
    {397, "Fn F8"},
    {398, "Fn F9"},
    {399, "Fn F10"},
    {400, "Fn F11"},
    {401, "Fn F12"},
    {402, "Fn 1"},
    {403, "Fn 2"},
    {404, "Fn D"},
    {405, "Fn E"},
    {406, "Fn F"},
    {407, "Fn S"},
    {408, "Fn B"},
    {409, "Fn Right Shift"},
    {416, "Brl Dot1"},
    {417, "Brl Dot2"},
    {418, "Brl Dot3"},
    {419, "Brl Dot4"},
    {420, "Brl Dot5"},
    {421, "Brl Dot6"},
    {422, "Brl Dot7"},
    {423, "Brl Dot8"},
    {424, "Brl Dot9"},
    {425, "Brl Dot10"},
    {432, "Numeric 0"},
    {433, "Numeric 1"},
    {434, "Numeric 2"},
    {435, "Numeric 3"},
    {436, "Numeric 4"},
    {437, "Numeric 5"},
    {438, "Numeric 6"},
    {439, "Numeric 7"},
    {440, "Numeric 8"},
    {441, "Numeric 9"},
    {442, "Numeric Star"},
    {443, "Numeric Pound"},
    {444, "Numeric A"},
    {445, "Numeric B"},
    {446, "Numeric C"},
    {447, "Numeric D"},
    {448, "Camera Focus"},
    {449, "Wps Button"},
    {450, "Touchpad Toggle"},
    {451, "Touchpad On"},
    {452, "Touchpad Off"},
    {453, "Camera Zoomin"},
    {454, "Camera Zoomout"},
    {455, "Camera Up"},
    {456, "Camera Down"},
    {457, "Camera Left"},
    {458, "Camera Right"},
    {459, "Attendant On"},
    {460, "Attendant Off"},
    {461, "Attendant Toggle"},
    {462, "Lights Toggle"},
    {464, "Als Toggle"},
    {465, "Rotate Lock Toggle"},
    {466, "Buttonconfig"},
    {467, "Taskmanager"},
    {468, "Journal"},
    {469, "Controlpanel"},
    {470, "Appselect"},
    {471, "Screensaver"},
    {472, "Voicecommand"},
    {473, "Assistant"},
    {474, "Kbd Layout Next"},
    {475, "Emoji Picker"},
    {476, "Dictate"},
    {477, "Camera Access Enable"},
    {478, "Camera Access Disable"},
    {479, "Camera Access Toggle"},
    {480, "Brightness Min"},
    {481, "Brightness Max"},
    {497, "Kbdinputassist Prev"},
    {498, "Kbdinputassist Next"},
    {499, "Kbdinputassist Prevgroup"},
    {500, "Kbdinputassist Nextgroup"},
    {501, "Kbdinputassist Accept"},
    {502, "Kbdinputassist Cancel"},
    {503, "Right Up"},
    {504, "Right Down"},
    {505, "Left Up"},
    {506, "Left Down"},
    {507, "Root Menu"},
    {508, "Media Top Menu"},
    {509, "Numeric 11"},
    {510, "Numeric 12"},
    {511, "Audio Desc"},
    {512, "3D Mode"},
    {513, "Next Favorite"},
    {514, "Stop Record"},
    {515, "Pause Record"},
    {516, "Vod"},
    {517, "Unmute"},
    {518, "Fastreverse"},
    {519, "Slowreverse"},
    {520, "Data"},
    {521, "Onscreen Keyboard"},
    {522, "Privacy Screen Toggle"},
    {523, "Selective Screenshot"},
    {524, "Next Element"},
    {525, "Previous Element"},
    {526, "Autopilot Toggle"},
    {527, "User Pkkey"},
    {528, "User Pkkey2"},
    {529, "User Pkkey3"},
    {530, "User Pkkey4"},
    {531, "User Pkkey5"},
    {532, "User Pkkey6"},
    {533, "User Pkkey7"},
    {534, "User Pkkey8"},
    {535, "User Pkkey9"},
    {536, "User Pkkey10"},
    {537, "User Pkkey11"},
    {538, "User Pkkey12"},
    {539, "User Pkkey13"},
    {540, "User Pkkey14"},
    {541, "User Pkkey15"},
    {542, "User Pkkey16"},
    {543, "User Pkkey17"},
    {544, "User Pkkey18"},
    {545, "User Pkkey19"},
    {546, "User Pkkey20"},
    {547, "User Pkkey21"},
    {548, "User Pkkey22"},
    {549, "User Pkkey23"},
    {550, "User Pkkey24"},
    {551, "User Pkkey25"},
    {552, "User Pkkey26"},
    {553, "User Pkkey27"},
    {554, "User Pkkey28"},
    {555, "User Pkkey29"},
    {556, "User Pkkey30"},
    {557, "User Pkkey31"},
    {558, "User Pkkey32"},
    {559, "User Pkkey33"},
    {560, "User Pkkey34"},
    {561, "User Pkkey35"},
    {562, "User Pkkey36"},
    {563, "User Pkkey37"},
    {564, "User Pkkey38"},
    {565, "User Pkkey39"},
    {566, "User Pkkey40"},
    {567, "User Pkkey41"},
    {568, "User Pkkey42"},
    {569, "User Pkkey43"},
    {570, "User Pkkey44"},
    {571, "User Pkkey45"},
    {572, "User Pkkey46"},
    {573, "User Pkkey47"},
    {574, "User Pkkey48"},
    {575, "User Pkkey49"},
    {576, "User Pkkey50"},
    {577, "User Pkkey51"},
    {578, "User Pkkey52"},
    {579, "User Pkkey53"},
    {580, "User Pkkey54"},
    {581, "User Pkkey55"},
    {582, "User Pkkey56"},
    {583, "User Pkkey57"},
    {584, "User Pkkey58"},
    {585, "User Pkkey59"},
    {586, "User Pkkey60"},
    {587, "User Pkkey61"},
    {588, "User Pkkey62"},
    {589, "User Pkkey63"},
    {590, "User Pkkey64"},
    {591, "User Pkkey65"},
    {592, "User Pkkey66"},
    {593, "User Pkkey67"},
    {594, "User Pkkey68"},
    {595, "User Pkkey69"},
    {596, "User Pkkey70"},
    {597, "User Pkkey71"},
    {598, "User Pkkey72"},
    {599, "User Pkkey73"},
    {600, "User Pkkey74"},
    {601, "User Pkkey75"},
    {602, "User Pkkey76"},
    {603, "User Pkkey77"},
    {604, "User Pkkey78"},
    {605, "User Pkkey79"},
    {606, "User Pkkey80"},
    {607, "User Pkkey81"},
    {608, "User Pkkey82"},
    {609, "User Pkkey83"},
    {610, "User Pkkey84"},
    {611, "User Pkkey85"},
    {612, "User Pkkey86"},
    {613, "User Pkkey87"},
    {614, "User Pkkey88"},
    {615, "User Pkkey89"},
    {616, "User Pkkey90"},
    {617, "User Pkkey91"},
    {618, "User Pkkey92"},
    {619, "User Pkkey93"},
    {620, "User Pkkey94"},
    {621, "User Pkkey95"},
    {622, "User Pkkey96"},
    {623, "User Pkkey97"},
    {624, "User Pkkey98"},
    {625, "User Pkkey99"},
    {626, "User Pkkey100"},
    {627, "User Pkkey101"},
    {628, "User Pkkey102"},
    {629, "User Pkkey103"},
    {630, "User Pkkey104"},
    {631, "User Pkkey105"},
    {632, "User Pkkey106"},
    {633, "User Pkkey107"},
    {634, "User Pkkey108"},
    {635, "User Pkkey109"},
    {636, "User Pkkey110"},
    {637, "User Pkkey111"},
    {638, "User Pkkey112"},
    {639, "User Pkkey113"},
    {640, "User Pkkey114"},
    {641, "User Pkkey115"},
    {642, "User Pkkey116"},
    {643, "User Pkkey117"},
    {644, "User Pkkey118"},
    {645, "User Pkkey119"},
    {646, "User Pkkey120"},
    {647, "User Pkkey121"},
    {648, "User Pkkey122"},
    {649, "User Pkkey123"},
    {650, "User Pkkey124"},
    {651, "User Pkkey125"},
    {652, "User Pkkey126"},
    {653, "User Pkkey127"},
    {654, "User Pkkey128"},
    {656, "Fn Right Alt"},
    {688, "Macro Record Start"},
    {689, "Macro Record Stop"},
    {690, "Macro Preset Cycle"},
    {691, "Macro Preset1"},
    {692, "Macro Preset2"},
    {693, "Macro Preset3"},
    {696, "Kbd Lcd Menu1"},
    {697, "Kbd Lcd Menu2"},
    {698, "Kbd Lcd Menu3"},
    {699, "Kbd Lcd Menu4"},
    {700, "Kbd Lcd Menu5"},
    {701, "Performance"},
    {767, "Max"},
    {768, "Cnt"},
};

std::string fallback_us_label(int code) {
    auto it = FALLBACK_US_KEYS.find(code);
    if (it != FALLBACK_US_KEYS.end()) {
        return it->second;
    }
    return "#" + std::to_string(code);
}

// ---------------------------------------------------------------------------
// Translator
// ---------------------------------------------------------------------------

class Translator {
public:
    Translator(const std::string& layout, const std::string& variant, const std::string& options) {
        ctx_ = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
        if (!ctx_) {
            emit_note("xkb context creation failed; falling back to US names");
            return;
        }
        xkb_context_set_log_level(ctx_, XKB_LOG_LEVEL_CRITICAL);

        struct xkb_rule_names names;
        std::memset(&names, 0, sizeof(names));
        names.rules = nullptr;
        names.model = nullptr;
        names.layout = layout.empty() ? "us" : layout.c_str();
        names.variant = variant.c_str();
        names.options = options.c_str();

        keymap_ = xkb_keymap_new_from_names(ctx_, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
        if (!keymap_) {
            emit_note("xkb keymap for '" + layout + "' failed; falling back to US names");
            return;
        }

        state_ = xkb_state_new(keymap_);
        if (!state_) {
            emit_note("xkb keymap for '" + layout + "' failed; falling back to US names");
            return;
        }
    }

    ~Translator() {
        if (state_) xkb_state_unref(state_);
        if (keymap_) xkb_keymap_unref(keymap_);
        if (ctx_) xkb_context_unref(ctx_);
    }

    Translator(const Translator&) = delete;
    Translator& operator=(const Translator&) = delete;

    bool layout_aware() const {
        return state_ != nullptr;
    }

    void update(int code, bool pressed) {
        if (state_) {
            xkb_state_update_key(state_, static_cast<xkb_keycode_t>(code + 8),
                                 pressed ? XKB_KEY_DOWN : XKB_KEY_UP);
        }
    }

    std::vector<std::string> active_modifiers() const {
        if (!state_) return {};
        std::vector<std::string> mods;
        if (xkb_state_mod_name_is_active(state_, "Control", XKB_STATE_MODS_EFFECTIVE) > 0) {
            mods.push_back("Ctrl");
        }
        if (xkb_state_mod_name_is_active(state_, "Mod1", XKB_STATE_MODS_EFFECTIVE) > 0 ||
            xkb_state_mod_name_is_active(state_, "Alt", XKB_STATE_MODS_EFFECTIVE) > 0) {
            mods.push_back("Alt");
        }
        if (xkb_state_mod_name_is_active(state_, "Mod4", XKB_STATE_MODS_EFFECTIVE) > 0 ||
            xkb_state_mod_name_is_active(state_, "Super", XKB_STATE_MODS_EFFECTIVE) > 0) {
            mods.push_back("Super");
        }
        if (xkb_state_mod_name_is_active(state_, "Shift", XKB_STATE_MODS_EFFECTIVE) > 0) {
            mods.push_back("Shift");
        }
        return mods;
    }

    std::string label(int code, bool as_shortcut) const {
        auto named_it = NAMED_KEYS.find(code);
        if (named_it != NAMED_KEYS.end()) {
            return named_it->second;
        }

        if (state_) {
            xkb_keysym_t sym = xkb_state_key_get_one_sym(state_, static_cast<xkb_keycode_t>(code + 8));
            char name_buf[64] = {0};
            int n_len = xkb_keysym_get_name(sym, name_buf, sizeof(name_buf));
            if (n_len > 0) {
                std::string name(name_buf);
                auto sym_it = SYM_RENAMES.find(name);
                if (sym_it != SYM_RENAMES.end()) {
                    return sym_it->second;
                }
                if (!name.empty() && name != "NoSymbol") {
                    if (as_shortcut && utf8_codepoint_len(name) == 1) {
                        std::string upper_name = name;
                        for (char &c : upper_name) {
                            if (c >= 'a' && c <= 'z') {
                                c = static_cast<char>(c - 'a' + 'A');
                            }
                        }
                        return upper_name;
                    }
                    char utf8_buf[64] = {0};
                    int u_len = xkb_state_key_get_utf8(state_, static_cast<xkb_keycode_t>(code + 8),
                                                       utf8_buf, sizeof(utf8_buf));
                    if (u_len > 0) {
                        std::string_view text(utf8_buf, static_cast<size_t>(u_len));
                        if (!as_shortcut && is_printable_utf8(text)) {
                            return std::string(text);
                        }
                    }
                    if (utf8_codepoint_len(name) == 1) {
                        return name;
                    }
                    std::string replaced = name;
                    for (char &c : replaced) {
                        if (c == '_') c = ' ';
                    }
                    return replaced;
                }
            }
        }

        return fallback_us_label(code);
    }

private:
    struct xkb_context* ctx_ = nullptr;
    struct xkb_keymap* keymap_ = nullptr;
    struct xkb_state* state_ = nullptr;
};

// ---------------------------------------------------------------------------
// Device Enumeration & Capability Check
// ---------------------------------------------------------------------------

inline bool test_bit(const uint8_t* bits, int bit) {
    if (bit < 0 || bit > KEY_MAX) return false;
    return (bits[bit / 8] & (1U << (bit % 8))) != 0;
}

bool check_device_type(int fd, bool want_mouse, bool& is_kbd, bool& is_ptr) {
    uint8_t key_bits[KEY_MAX / 8 + 1];
    std::memset(key_bits, 0, sizeof(key_bits));
    if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(key_bits)), key_bits) < 0) {
        return false;
    }
    is_kbd = test_bit(key_bits, KEY_A) && test_bit(key_bits, KEY_SPACE);
    is_ptr = test_bit(key_bits, BTN_LEFT) && !test_bit(key_bits, KEY_A);
    return is_kbd || (want_mouse && is_ptr);
}

void scan_devices(bool want_mouse, std::map<std::string, int>& devices) {
    DIR* dir = opendir("/dev/input");
    if (!dir) return;

    std::set<std::string> current_event_paths;
    struct dirent* entry = nullptr;
    while ((entry = readdir(dir)) != nullptr) {
        if (std::strncmp(entry->d_name, "event", 5) == 0) {
            current_event_paths.insert(std::string("/dev/input/") + entry->d_name);
        }
    }
    closedir(dir);

    // Close and remove missing devices
    for (auto it = devices.begin(); it != devices.end(); ) {
        if (current_event_paths.find(it->first) == current_event_paths.end()) {
            close(it->second);
            it = devices.erase(it);
        } else {
            ++it;
        }
    }

    // Open newly discovered devices
    for (const auto& path : current_event_paths) {
        if (devices.find(path) != devices.end()) {
            continue;
        }
        int fd = open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) {
            continue;
        }
        bool is_kbd = false;
        bool is_ptr = false;
        if (check_device_type(fd, want_mouse, is_kbd, is_ptr)) {
            devices[path] = fd;
        } else {
            close(fd);
        }
    }
}

// ---------------------------------------------------------------------------
// CLI Argument Parsing
// ---------------------------------------------------------------------------

struct Options {
    std::string layout = "us";
    std::string variant = "";
    std::string options = "";
    bool mouse = false;
    bool repeats = false;
};

bool parse_args(int argc, char* argv[], Options& opts) {
    for (int i = 1; i < argc; ++i) {
        std::string_view arg = argv[i];
        if (arg == "--layout") {
            if (++i < argc) opts.layout = argv[i];
            else return false;
        } else if (arg.rfind("--layout=", 0) == 0) {
            opts.layout = arg.substr(9);
        } else if (arg == "--variant") {
            if (++i < argc) opts.variant = argv[i];
            else return false;
        } else if (arg.rfind("--variant=", 0) == 0) {
            opts.variant = arg.substr(10);
        } else if (arg == "--options") {
            if (++i < argc) opts.options = argv[i];
            else return false;
        } else if (arg.rfind("--options=", 0) == 0) {
            opts.options = arg.substr(10);
        } else if (arg == "--mouse") {
            opts.mouse = true;
        } else if (arg == "--repeats") {
            opts.repeats = true;
        } else if (arg == "-h" || arg == "--help") {
            std::cout << "Usage: keypress_monitor [--layout <layout>] [--variant <variant>] [--options <options>] [--mouse] [--repeats]\n";
            std::exit(0);
        }
    }
    return true;
}

} // namespace

int main(int argc, char* argv[]) {
    init_process();

    Options opts;
    if (!parse_args(argc, argv, opts)) {
        emit_error("invalid command line arguments");
        return 1;
    }

    if (access("/dev/input", R_OK) != 0) {
        emit_error("no read access to /dev/input (add your user to the 'input' group)");
        return 1;
    }

    Translator translator(opts.layout, opts.variant, opts.options);

    std::map<std::string, int> devices;
    scan_devices(opts.mouse, devices);
    if (devices.empty()) {
        emit_error("no readable keyboard found under /dev/input");
        return 1;
    }

    emit_ready(static_cast<int>(devices.size()), opts.layout, translator.layout_aware());

    auto last_scan = Clock::now();
    std::unordered_map<int, double> recent;

    while (g_running) {
        auto now = Clock::now();
        double elapsed = std::chrono::duration<double>(now - last_scan).count();
        if (elapsed >= RESCAN_INTERVAL) {
            scan_devices(opts.mouse, devices);
            last_scan = Clock::now();
            elapsed = 0.0;
        }

        double wait_sec = RESCAN_INTERVAL - elapsed;
        int timeout_ms = static_cast<int>(wait_sec * 1000.0);
        if (timeout_ms < 0) timeout_ms = 0;
        if (timeout_ms > 2000) timeout_ms = 2000;

        std::vector<std::pair<std::string, int>> dev_list(devices.begin(), devices.end());
        std::vector<struct pollfd> pfds;
        pfds.reserve(dev_list.size());
        for (const auto& item : dev_list) {
            struct pollfd pfd;
            pfd.fd = item.second;
            pfd.events = POLLIN;
            pfd.revents = 0;
            pfds.push_back(pfd);
        }

        int ret = poll(pfds.data(), pfds.size(), timeout_ms);
        if (!g_running) break;

        if (ret < 0) {
            if (errno == EINTR) {
                continue;
            }
            scan_devices(opts.mouse, devices);
            last_scan = Clock::now();
            continue;
        }

        std::vector<std::string> dead_paths;

        for (size_t i = 0; i < pfds.size(); ++i) {
            if (pfds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                dead_paths.push_back(dev_list[i].first);
                continue;
            }

            if (pfds[i].revents & POLLIN) {
                int fd = pfds[i].fd;
                struct input_event evs[64];
                while (true) {
                    ssize_t n = read(fd, evs, sizeof(evs));
                    if (n < 0) {
                        if (errno == EAGAIN || errno == EWOULDBLOCK) {
                            break;
                        }
                        dead_paths.push_back(dev_list[i].first);
                        break;
                    }
                    if (n == 0) {
                        dead_paths.push_back(dev_list[i].first);
                        break;
                    }

                    size_t count = static_cast<size_t>(n) / sizeof(struct input_event);
                    for (size_t k = 0; k < count; ++k) {
                        const auto& event = evs[k];
                        if (event.type != EV_KEY) {
                            continue;
                        }

                        int code = event.code;
                        int value = event.value; // 0 released, 1 pressed, 2 auto-repeat

                        bool is_mouse = (MOUSE_BUTTONS.find(code) != MOUSE_BUTTONS.end());
                        auto mod_it = MODIFIER_KEYS.find(code);
                        bool is_mod = (mod_it != MODIFIER_KEYS.end());

                        if (value != 2 && !is_mouse) {
                            translator.update(code, value == 1);
                        }

                        if (value == 0) {
                            if (is_mod) {
                                emit_release(mod_it->second);
                            }
                            continue;
                        }

                        if (value == 2 && (!opts.repeats || is_mod)) {
                            continue;
                        }

                        double stamp = std::chrono::duration<double>(Clock::now().time_since_epoch()).count();
                        auto recent_it = recent.find(code);
                        if (recent_it != recent.end() && (stamp - recent_it->second) < DEDUP_WINDOW) {
                            continue;
                        }
                        recent[code] = stamp;

                        if (is_mouse) {
                            auto mouse_it = MOUSE_BUTTONS.find(code);
                            emit_key("mouse", mouse_it->second, translator.active_modifiers(), value == 2);
                            continue;
                        }

                        if (is_mod) {
                            emit_key("modifier", mod_it->second, {}, value == 2);
                            continue;
                        }

                        std::vector<std::string> mods = translator.active_modifiers();
                        bool is_shortcut = false;
                        for (const auto& mod : mods) {
                            if (mod == "Ctrl" || mod == "Alt" || mod == "Super") {
                                is_shortcut = true;
                                break;
                            }
                        }

                        std::string label = translator.label(code, is_shortcut);
                        bool is_text = (NAMED_KEYS.find(code) == NAMED_KEYS.end()) && (utf8_codepoint_len(label) == 1);
                        std::string kind = is_shortcut ? "shortcut" : (is_text ? "text" : "key");

                        std::vector<std::string> filtered_mods;
                        filtered_mods.reserve(mods.size());
                        for (const auto& mod : mods) {
                            if (mod != "Shift" || is_shortcut) {
                                filtered_mods.push_back(mod);
                            }
                        }

                        emit_key(kind, label, filtered_mods, value == 2);
                    }
                }
            }
        }

        if (!dead_paths.empty()) {
            for (const auto& path : dead_paths) {
                auto it = devices.find(path);
                if (it != devices.end()) {
                    close(it->second);
                    devices.erase(it);
                }
            }
        }
    }

    for (const auto& item : devices) {
        close(item.second);
    }
    devices.clear();

    return 0;
}
