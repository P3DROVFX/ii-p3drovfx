#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <optional>
#include <poll.h>
#include <signal.h>
#include <sstream>
#include <string>
#include <string_view>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <utility>
#include <vector>

// Never spend longer than this blocked in poll(), so stdin stays responsive
// even when polling is idle.
static constexpr double MAX_WAIT_S = 0.25;

// A gesture Hyprland dropped without telling anyone looks, from here, like a
// window sitting exactly where it started. So does a drag that has only just
// begun, and a tiled one Hyprland will not move until it swaps on release, so
// the two are told apart by how long the window stays put.
static constexpr double STALE_DRAG_S = 2.0;

// Once the window is following the cursor, it stopping while the cursor keeps
// going is the gesture being let go, and there is no ambiguity left to wait out.
// Long enough that a frame or two of lag between the two samples cannot pass for
// it, short enough that the drop still feels like one.
static constexpr double STALE_FOLLOW_S = 0.15;

// Backstop for anything the checks below still miss: no gesture is a minute
// long, and an overlay that never goes away is worse than one that goes away
// early.
static constexpr double MAX_DRAG_S = 60.0;

static volatile sig_atomic_t g_stop = 0;

static void sig_handler(int sig) {
    (void)sig;
    g_stop = 1;
}

static void setup_signals() {
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    struct sigaction sa;
    std::memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sig_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);
    sigaction(SIGPIPE, &sa, nullptr);
}

static void emit(const std::string& line) {
    std::cout << line << "\n";
    std::cout.flush();
    if (std::cout.fail()) {
        std::exit(0);
    }
}

static void log_err(const std::string& message) {
    std::cerr << "[drag_monitor] " << message << "\n";
    std::cerr.flush();
}

static inline double get_monotonic_s() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<double>(ts.tv_sec) + static_cast<double>(ts.tv_nsec) * 1e-9;
}

// ---------------------------------------------------------------------------
// JSON AST & Parser
// ---------------------------------------------------------------------------

struct JsonValue {
    enum class Type { Null, Bool, Number, String, Array, Object };
    Type type = Type::Null;

    bool bool_val = false;
    double num_val = 0.0;
    std::string str_val;
    std::vector<JsonValue> arr_val;
    std::vector<std::pair<std::string, JsonValue>> obj_val;

    bool is_null() const { return type == Type::Null; }
    bool is_bool() const { return type == Type::Bool; }
    bool is_number() const { return type == Type::Number; }
    bool is_string() const { return type == Type::String; }
    bool is_array() const { return type == Type::Array; }
    bool is_object() const { return type == Type::Object; }

    const JsonValue* get(std::string_view key) const {
        if (type != Type::Object) return nullptr;
        for (const auto& kv : obj_val) {
            if (kv.first == key) return &kv.second;
        }
        return nullptr;
    }

    std::string get_string(std::string_view key, const std::string& def = "") const {
        const JsonValue* v = get(key);
        return (v && v->is_string()) ? v->str_val : def;
    }

    bool as_truthy(bool def = false) const {
        if (type == Type::Bool) return bool_val;
        if (type == Type::Number) return (num_val != 0.0);
        if (type == Type::String) return !str_val.empty();
        if (type == Type::Null) return false;
        return def;
    }

    int64_t as_int(int64_t def = 0) const {
        if (type == Type::Number) return static_cast<int64_t>(std::round(num_val));
        if (type == Type::Bool) return bool_val ? 1 : 0;
        return def;
    }

    double as_double(double def = 0.0) const {
        if (type == Type::Number) return num_val;
        if (type == Type::Bool) return bool_val ? 1.0 : 0.0;
        return def;
    }

    std::string as_string(const std::string& def = "") const {
        if (type == Type::String) return str_val;
        return def;
    }
};

static void skip_ws(const std::string& s, size_t& pos) {
    while (pos < s.size()) {
        char c = s[pos];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            pos++;
        } else {
            break;
        }
    }
}

static void encode_utf8(uint32_t cp, std::string& out) {
    if (cp <= 0x7F) {
        out.push_back(static_cast<char>(cp));
    } else if (cp <= 0x7FF) {
        out.push_back(static_cast<char>(0xC0 | ((cp >> 6) & 0x1F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp <= 0xFFFF) {
        out.push_back(static_cast<char>(0xE0 | ((cp >> 12) & 0x0F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp <= 0x10FFFF) {
        out.push_back(static_cast<char>(0xF0 | ((cp >> 18) & 0x07)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
}

static bool parse_string(const std::string& s, size_t& pos, std::string& out) {
    if (pos >= s.size() || s[pos] != '"') return false;
    pos++; // skip leading '"'
    out.clear();
    while (pos < s.size()) {
        char c = s[pos++];
        if (c == '"') {
            return true;
        }
        if (c == '\\') {
            if (pos >= s.size()) return false;
            char esc = s[pos++];
            switch (esc) {
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                case '/': out.push_back('/'); break;
                case 'b': out.push_back('\b'); break;
                case 'f': out.push_back('\f'); break;
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                case 'u': {
                    if (pos + 4 > s.size()) return false;
                    uint32_t cp = 0;
                    for (int i = 0; i < 4; ++i) {
                        char h = s[pos++];
                        cp <<= 4;
                        if (h >= '0' && h <= '9') cp |= (h - '0');
                        else if (h >= 'a' && h <= 'f') cp |= (h - 'a' + 10);
                        else if (h >= 'A' && h <= 'F') cp |= (h - 'A' + 10);
                        else return false;
                    }
                    if (cp >= 0xD800 && cp <= 0xDBFF) {
                        if (pos + 6 <= s.size() && s[pos] == '\\' && s[pos + 1] == 'u') {
                            size_t save = pos;
                            pos += 2;
                            uint32_t low = 0;
                            bool ok = true;
                            for (int i = 0; i < 4; ++i) {
                                char h = s[pos++];
                                low <<= 4;
                                if (h >= '0' && h <= '9') low |= (h - '0');
                                else if (h >= 'a' && h <= 'f') low |= (h - 'a' + 10);
                                else if (h >= 'A' && h <= 'F') low |= (h - 'A' + 10);
                                else { ok = false; break; }
                            }
                            if (ok && low >= 0xDC00 && low <= 0xDFFF) {
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                            } else {
                                pos = save;
                            }
                        }
                    }
                    encode_utf8(cp, out);
                    break;
                }
                default:
                    out.push_back(esc);
                    break;
            }
        } else {
            out.push_back(c);
        }
    }
    return false;
}

static bool parse_number(const std::string& s, size_t& pos, double& out) {
    size_t start = pos;
    if (pos < s.size() && (s[pos] == '-' || s[pos] == '+')) {
        pos++;
    }
    bool has_digits = false;
    while (pos < s.size() && (s[pos] >= '0' && s[pos] <= '9')) {
        has_digits = true;
        pos++;
    }
    if (pos < s.size() && s[pos] == '.') {
        pos++;
        while (pos < s.size() && (s[pos] >= '0' && s[pos] <= '9')) {
            has_digits = true;
            pos++;
        }
    }
    if (pos < s.size() && (s[pos] == 'e' || s[pos] == 'E')) {
        pos++;
        if (pos < s.size() && (s[pos] == '-' || s[pos] == '+')) {
            pos++;
        }
        while (pos < s.size() && (s[pos] >= '0' && s[pos] <= '9')) {
            pos++;
        }
    }
    if (!has_digits) return false;
    char* end = nullptr;
    const char* c_str = s.c_str() + start;
    out = std::strtod(c_str, &end);
    if (end != c_str + (pos - start)) {
        return false;
    }
    return true;
}

static bool parse_one_value(const std::string& s, size_t& pos, JsonValue& out) {
    skip_ws(s, pos);
    if (pos >= s.size()) return false;

    char c = s[pos];
    if (c == 'n') {
        if (pos + 4 <= s.size() && s.compare(pos, 4, "null") == 0) {
            pos += 4;
            out.type = JsonValue::Type::Null;
            return true;
        }
        return false;
    }
    if (c == 't') {
        if (pos + 4 <= s.size() && s.compare(pos, 4, "true") == 0) {
            pos += 4;
            out.type = JsonValue::Type::Bool;
            out.bool_val = true;
            return true;
        }
        return false;
    }
    if (c == 'f') {
        if (pos + 5 <= s.size() && s.compare(pos, 5, "false") == 0) {
            pos += 5;
            out.type = JsonValue::Type::Bool;
            out.bool_val = false;
            return true;
        }
        return false;
    }
    if (c == '"') {
        out.type = JsonValue::Type::String;
        return parse_string(s, pos, out.str_val);
    }
    if (c == '-' || c == '+' || (c >= '0' && c <= '9')) {
        out.type = JsonValue::Type::Number;
        return parse_number(s, pos, out.num_val);
    }
    if (c == '[') {
        pos++; // skip '['
        out.type = JsonValue::Type::Array;
        out.arr_val.clear();
        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == ']') {
            pos++;
            return true;
        }
        while (pos < s.size()) {
            JsonValue elem;
            if (!parse_one_value(s, pos, elem)) return false;
            out.arr_val.push_back(std::move(elem));
            skip_ws(s, pos);
            if (pos >= s.size()) return false;
            if (s[pos] == ']') {
                pos++;
                return true;
            }
            if (s[pos] == ',') {
                pos++;
                continue;
            }
            return false;
        }
        return false;
    }
    if (c == '{') {
        pos++; // skip '{'
        out.type = JsonValue::Type::Object;
        out.obj_val.clear();
        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == '}') {
            pos++;
            return true;
        }
        while (pos < s.size()) {
            skip_ws(s, pos);
            if (pos >= s.size() || s[pos] != '"') return false;
            std::string key;
            if (!parse_string(s, pos, key)) return false;
            skip_ws(s, pos);
            if (pos >= s.size() || s[pos] != ':') return false;
            pos++; // skip ':'
            JsonValue val;
            if (!parse_one_value(s, pos, val)) return false;
            out.obj_val.emplace_back(std::move(key), std::move(val));
            skip_ws(s, pos);
            if (pos >= s.size()) return false;
            if (s[pos] == '}') {
                pos++;
                return true;
            }
            if (s[pos] == ',') {
                pos++;
                continue;
            }
            return false;
        }
        return false;
    }
    return false;
}

static std::string json_quote(const std::string& s) {
    std::string res;
    res.reserve(s.size() + 2);
    res.push_back('"');
    for (char c : s) {
        switch (c) {
            case '"': res += "\\\""; break;
            case '\\': res += "\\\\"; break;
            case '\b': res += "\\b"; break;
            case '\f': res += "\\f"; break;
            case '\n': res += "\\n"; break;
            case '\r': res += "\\r"; break;
            case '\t': res += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(c));
                    res += buf;
                } else {
                    res.push_back(c);
                }
                break;
        }
    }
    res.push_back('"');
    return res;
}

// ---------------------------------------------------------------------------
// Model & Shape Helpers
// ---------------------------------------------------------------------------

struct Point {
    int x = 0;
    int y = 0;
    bool operator==(const Point& o) const = default;
};

struct Window {
    std::string address;
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
    bool floating = false;
    int monitor = -1;
    int workspace = -1;
    bool fullscreen = false;
};

static std::string to_json(const Window& w) {
    std::ostringstream ss;
    ss << "{\"address\":" << json_quote(w.address)
       << ",\"x\":" << w.x
       << ",\"y\":" << w.y
       << ",\"width\":" << w.width
       << ",\"height\":" << w.height
       << ",\"floating\":" << (w.floating ? "true" : "false")
       << ",\"monitor\":" << w.monitor
       << ",\"workspace\":" << w.workspace
       << ",\"fullscreen\":" << (w.fullscreen ? "true" : "false")
       << "}";
    return ss.str();
}

static std::optional<Point> shape_cursor(const JsonValue& pos) {
    if (!pos.is_object()) return std::nullopt;
    const JsonValue* x = pos.get("x");
    const JsonValue* y = pos.get("y");
    if (!x || !y) return std::nullopt;
    if (!x->is_number() || !y->is_number()) return std::nullopt;
    return Point{static_cast<int>(x->as_int()), static_cast<int>(y->as_int())};
}

static std::optional<Window> shape_window(const JsonValue& win) {
    if (!win.is_object()) return std::nullopt;
    const JsonValue* addr = win.get("address");
    if (!addr || !addr->is_string() || addr->str_val.empty()) {
        return std::nullopt;
    }

    Window w;
    w.address = addr->str_val;

    const JsonValue* at = win.get("at");
    if (at && at->is_array() && at->arr_val.size() >= 2) {
        w.x = static_cast<int>(at->arr_val[0].as_int(0));
        w.y = static_cast<int>(at->arr_val[1].as_int(0));
    } else {
        w.x = 0;
        w.y = 0;
    }

    const JsonValue* size = win.get("size");
    if (size && size->is_array() && size->arr_val.size() >= 2) {
        w.width = static_cast<int>(size->arr_val[0].as_int(0));
        w.height = static_cast<int>(size->arr_val[1].as_int(0));
    } else {
        w.width = 0;
        w.height = 0;
    }

    const JsonValue* fl = win.get("floating");
    w.floating = fl ? fl->as_truthy(false) : false;

    const JsonValue* mon = win.get("monitor");
    w.monitor = mon ? static_cast<int>(mon->as_int(-1)) : -1;

    const JsonValue* ws = win.get("workspace");
    if (ws && ws->is_object()) {
        const JsonValue* id = ws->get("id");
        w.workspace = id ? static_cast<int>(id->as_int(-1)) : -1;
    } else {
        w.workspace = -1;
    }

    const JsonValue* fs = win.get("fullscreen");
    w.fullscreen = fs ? fs->as_truthy(false) : false;

    return w;
}

static std::string normalize_address(std::string_view s) {
    size_t start = 0;
    while (start < s.size() && std::isspace(static_cast<unsigned char>(s[start]))) {
        start++;
    }
    size_t end = s.size();
    while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1]))) {
        end--;
    }
    std::string res;
    res.reserve(end - start);
    for (size_t i = start; i < end; ++i) {
        res.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(s[i]))));
    }
    size_t l = 0;
    while (l < res.size() && (res[l] == '0' || res[l] == 'x')) {
        l++;
    }
    return res.substr(l);
}

static bool same_address(const std::string& one, const std::string& other) {
    if (one.empty() || other.empty()) return false;
    return normalize_address(one) == normalize_address(other);
}

static bool shifted(const Window& before, const Window& after) {
    return (after.x != before.x || after.y != before.y
            || after.width != before.width || after.height != before.height);
}

static int first_css_value(const std::optional<std::string>& css_opt, int fallback) {
    if (!css_opt.has_value()) return fallback;
    std::string s = *css_opt;
    for (char& c : s) {
        if (c == ',') c = ' ';
    }
    std::istringstream iss(s);
    std::string token;
    while (iss >> token) {
        char* end = nullptr;
        double val = std::strtod(token.c_str(), &end);
        if (end != token.c_str() && *end == '\0') {
            return static_cast<int>(val);
        }
    }
    return fallback;
}

// ---------------------------------------------------------------------------
// Hyprland Socket & IPC
// ---------------------------------------------------------------------------

static bool is_directory(const std::string& path) {
    struct stat st;
    if (stat(path.c_str(), &st) != 0) return false;
    return S_ISDIR(st.st_mode);
}

static std::string socket_dir() {
    const char* sig = std::getenv("HYPRLAND_INSTANCE_SIGNATURE");
    if (!sig || *sig == '\0') {
        return "";
    }
    const char* xdg = std::getenv("XDG_RUNTIME_DIR");
    std::string runtime;
    if (xdg && *xdg != '\0') {
        runtime = xdg;
    } else {
        runtime = "/run/user/" + std::to_string(getuid());
    }
    std::string path1 = runtime + "/hypr/" + sig;
    if (is_directory(path1)) return path1;
    std::string path2 = std::string("/tmp/hypr/") + sig;
    if (is_directory(path2)) return path2;
    return "";
}

class Hyprctl {
private:
    std::string path;

public:
    explicit Hyprctl(const std::string& directory)
        : path(directory + "/.socket.sock") {}

    std::string request(const std::string& command) {
        int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) return "";

        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 500000; // 0.5s timeout
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        struct sockaddr_un addr;
        std::memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        if (path.size() >= sizeof(addr.sun_path)) {
            ::close(fd);
            return "";
        }
        std::strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);

        if (::connect(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
            ::close(fd);
            return "";
        }

        size_t total_sent = 0;
        while (total_sent < command.size()) {
            ssize_t n = ::send(fd, command.data() + total_sent, command.size() - total_sent, 0);
            if (n <= 0) {
                ::close(fd);
                return "";
            }
            total_sent += static_cast<size_t>(n);
        }

        std::string response;
        char buf[8192];
        while (true) {
            ssize_t n = ::recv(fd, buf, sizeof(buf), 0);
            if (n > 0) {
                response.append(buf, static_cast<size_t>(n));
            } else if (n == 0) {
                break;
            } else {
                if (errno == EINTR) continue;
                break;
            }
        }
        ::close(fd);
        return response;
    }

    std::optional<JsonValue> json(const std::string& command) {
        std::string raw = request("j/" + command);
        if (raw.empty()) return std::nullopt;
        size_t pos = 0;
        JsonValue val;
        if (parse_one_value(raw, pos, val)) {
            return val;
        }
        return std::nullopt;
    }

    std::vector<std::optional<JsonValue>> json_batch(const std::vector<std::string>& commands) {
        std::string req = "[[BATCH]]";
        for (size_t i = 0; i < commands.size(); ++i) {
            if (i > 0) req += ";";
            req += "j/" + commands[i];
        }
        std::string raw = request(req);
        std::vector<std::optional<JsonValue>> results;
        results.reserve(commands.size());
        if (!raw.empty()) {
            size_t index = 0;
            for (size_t c = 0; c < commands.size(); ++c) {
                while (index < raw.size() && std::isspace(static_cast<unsigned char>(raw[index]))) {
                    index++;
                }
                if (index >= raw.size()) break;
                JsonValue val;
                if (!parse_one_value(raw, index, val)) {
                    break;
                }
                results.push_back(std::move(val));
            }
        }
        while (results.size() < commands.size()) {
            results.push_back(std::nullopt);
        }
        return results;
    }

    std::optional<Point> cursorpos() {
        std::string raw = request("/cursorpos");
        if (raw.empty()) return std::nullopt;
        size_t comma = raw.find(',');
        if (comma == std::string::npos) return std::nullopt;
        std::string p1 = raw.substr(0, comma);
        std::string p2 = raw.substr(comma + 1);
        char* end1 = nullptr;
        char* end2 = nullptr;
        long x = std::strtol(p1.c_str(), &end1, 10);
        long y = std::strtol(p2.c_str(), &end2, 10);
        while (*end1 && std::isspace(static_cast<unsigned char>(*end1))) end1++;
        while (*end2 && std::isspace(static_cast<unsigned char>(*end2))) end2++;
        if (*end1 != '\0' || *end2 != '\0') return std::nullopt;
        return Point{static_cast<int>(x), static_cast<int>(y)};
    }

    std::pair<std::optional<Point>, std::optional<Window>> sample() {
        auto batch = json_batch({"cursorpos", "activewindow"});
        std::optional<Point> cur;
        if (batch.size() > 0 && batch[0].has_value()) {
            cur = shape_cursor(*batch[0]);
        }
        std::optional<Window> win;
        if (batch.size() > 1 && batch[1].has_value()) {
            win = shape_window(*batch[1]);
        }
        return {cur, win};
    }
};

static std::optional<Window> window_sample(Hyprctl& ctl) {
    auto j = ctl.json("activewindow");
    if (j.has_value()) {
        return shape_window(*j);
    }
    return std::nullopt;
}

struct Gaps {
    int outer = 5;
    int inner = 4;
};

static Gaps read_gaps(Hyprctl& ctl) {
    auto out = ctl.json("getoption general:gaps_out");
    auto inn = ctl.json("getoption general:gaps_in");
    Gaps g;
    std::optional<std::string> out_css;
    if (out.has_value() && out->is_object()) {
        if (const JsonValue* v = out->get("css")) {
            if (v->is_string()) out_css = v->str_val;
        }
    }
    std::optional<std::string> inn_css;
    if (inn.has_value() && inn->is_object()) {
        if (const JsonValue* v = inn->get("css")) {
            if (v->is_string()) inn_css = v->str_val;
        }
    }
    g.outer = first_css_value(out_css, 5);
    g.inner = first_css_value(inn_css, 4);
    return g;
}

// ---------------------------------------------------------------------------
// Monitor State Machine
// ---------------------------------------------------------------------------

class Monitor {
public:
    Hyprctl& ctl;
    double idle_interval = 1.0 / 5.0;
    double active_interval = 1.0 / 90.0;
    int tolerance = 2;
    bool use_keybinds = true;

    bool dragging = false;
    std::string kind;
    std::optional<Point> cursor;
    std::optional<Window> window;
    std::optional<Window> before;
    bool left_origin = false;
    double started_at = 0.0;
    std::optional<double> settled_at;

    explicit Monitor(Hyprctl& c) : ctl(c) {}

    void configure(const JsonValue& cmd) {
        double idle_hz = 5.0;
        if (const JsonValue* v = cmd.get("idleHz")) {
            double d = v->as_double(5.0);
            if (d != 0.0) idle_hz = d;
        }
        double active_hz = 90.0;
        if (const JsonValue* v = cmd.get("activeHz")) {
            double d = v->as_double(90.0);
            if (d != 0.0) active_hz = d;
        }
        idle_interval = 1.0 / std::max(1.0, std::min(idle_hz, 240.0));
        active_interval = 1.0 / std::max(1.0, std::min(active_hz, 240.0));

        int tol = 2;
        if (const JsonValue* v = cmd.get("tolerance")) {
            tol = static_cast<int>(v->as_int(0));
        }
        tolerance = std::max(0, tol);

        if (const JsonValue* v = cmd.get("keybinds")) {
            use_keybinds = v->as_truthy(true);
        } else {
            use_keybinds = true;
        }
    }

    double interval() const {
        return dragging ? active_interval : idle_interval;
    }

    void start(const std::string& k, const Point& cur, const Window& win, std::optional<Window> bef = std::nullopt) {
        dragging = true;
        kind = k;
        cursor = cur;
        window = win;
        left_origin = false;
        started_at = get_monotonic_s();
        settled_at = std::nullopt;
        if (!bef.has_value() || bef->address != win.address) {
            bef = win;
        }
        before = bef;

        std::ostringstream ss;
        ss << "{\"event\":\"dragStart\""
           << ",\"kind\":" << json_quote(kind)
           << ",\"address\":" << json_quote(win.address)
           << ",\"x\":" << cur.x
           << ",\"y\":" << cur.y
           << ",\"window\":" << to_json(win)
           << ",\"before\":" << to_json(*before)
           << "}";
        emit(ss.str());
    }

    void stop(bool cancelled = false) {
        if (!dragging) return;
        Point cur = cursor.value_or(Point{0, 0});
        auto win_samp = window_sample(ctl);
        if (window.has_value() && (!win_samp.has_value() || win_samp->address != window->address)) {
            win_samp = window;
        }

        std::ostringstream ss;
        ss << "{\"event\":\"dragEnd\""
           << ",\"kind\":" << json_quote(kind)
           << ",\"x\":" << cur.x
           << ",\"y\":" << cur.y
           << ",\"cancelled\":" << (cancelled ? "true" : "false")
           << ",\"window\":" << (win_samp.has_value() ? to_json(*win_samp) : "null")
           << "}";
        emit(ss.str());

        dragging = false;
        kind.clear();
        before = std::nullopt;
        left_origin = false;
        settled_at = std::nullopt;
    }

    void hint(const JsonValue& cmd) {
        if (!use_keybinds) return;
        std::string k = "move";
        if (const JsonValue* kv = cmd.get("kind")) {
            if (kv->as_string() == "resize") k = "resize";
        }
        std::string state;
        if (const JsonValue* sv = cmd.get("state")) {
            state = sv->as_string();
        }
        if (state == "up") {
            if (dragging && kind == k) {
                poll_cursor();
                stop(false);
            }
            return;
        }
        if (dragging) return;
        auto bef = window;
        auto [cur, win] = ctl.sample();
        if (!cur.has_value() || !win.has_value() || win->fullscreen) {
            return;
        }
        start(k, *cur, *win, bef);
    }

    bool poll_cursor() {
        auto cur = ctl.cursorpos();
        if (!cur.has_value() || (cursor.has_value() && *cur == *cursor)) {
            return false;
        }
        cursor = cur;
        return true;
    }

    void poll_dragging() {
        auto [cur, win] = ctl.sample();
        bool cursor_moved = cur.has_value() && (!cursor.has_value() || *cur != *cursor);
        if (cursor_moved) {
            cursor = cur;
            std::ostringstream ss;
            ss << "{\"event\":\"dragMove\",\"x\":" << cur->x << ",\"y\":" << cur->y << "}";
            emit(ss.str());
        }
        if (get_monotonic_s() - started_at > MAX_DRAG_S) {
            stop(true);
            return;
        }
        poll_keybind_drag(win, cursor_moved);
    }

    void poll_keybind_drag(const std::optional<Window>& win, bool cursor_moved) {
        if (!before.has_value()) {
            stop(true);
            return;
        }
        if (win.has_value() && win->address != before->address) {
            stop(true);
            return;
        }
        if (!win.has_value()) {
            mark_settled(cursor_moved, false);
            return;
        }
        auto previous = window;
        window = win;
        if (!moved(*before, *win)) {
            if (left_origin) {
                stop(true);
                return;
            }
            mark_settled(cursor_moved, false);
            return;
        }
        left_origin = true;
        if (previous.has_value() && shifted(*previous, *win)) {
            settled_at = std::nullopt;
            return;
        }
        mark_settled(cursor_moved, true);
    }

    void mark_settled(bool cursor_moved, bool dropped) {
        double now = get_monotonic_s();
        bool quick = dropped && cursor_moved && (kind == "move");
        double limit = quick ? STALE_FOLLOW_S : STALE_DRAG_S;
        if (!settled_at.has_value()) {
            settled_at = now;
        } else if (now - *settled_at > limit) {
            stop(!dropped);
        }
    }

    void event(const std::string& name, const std::string& data) {
        if (!dragging) return;
        std::string address = before.has_value() ? before->address : "";
        if (name == "workspace" || name == "workspacev2" || name == "fullscreen") {
            stop(true);
        } else if (name == "closewindow" && same_address(data, address)) {
            stop(true);
        } else if (name == "activewindowv2" && !data.empty() && !same_address(data, address)) {
            stop(true);
        }
    }

    bool moved(const Window& bef, const Window& aft) const {
        int tol = tolerance;
        return (std::abs(aft.x - bef.x) > tol ||
                std::abs(aft.y - bef.y) > tol ||
                std::abs(aft.width - bef.width) > tol ||
                std::abs(aft.height - bef.height) > tol);
    }

    void poll_idle() {
        auto w = window_sample(ctl);
        if (w.has_value()) {
            window = w;
        }
    }

    void poll() {
        if (dragging) {
            poll_dragging();
        } else {
            poll_idle();
        }
    }
};

// ---------------------------------------------------------------------------
// Command Handling & Main
// ---------------------------------------------------------------------------

static bool handle_stdin_command(Monitor& monitor, const std::string& line) {
    if (line.empty()) return true;
    size_t pos = 0;
    JsonValue cmd;
    if (!parse_one_value(line, pos, cmd) || !cmd.is_object()) {
        return true;
    }
    std::string name = cmd.get_string("cmd");
    if (name == "quit") {
        return false;
    } else if (name == "hint") {
        monitor.hint(cmd);
    } else if (name == "config") {
        monitor.configure(cmd);
    }
    return true;
}

int main() {
    setup_signals();

    std::string directory = socket_dir();
    if (directory.empty()) {
        log_err("no Hyprland instance found");
        return 1;
    }

    Hyprctl ctl(directory);
    Monitor monitor(ctl);

    int events_fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (events_fd >= 0) {
        struct sockaddr_un addr;
        std::memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        std::string ev_path = directory + "/.socket2.sock";
        if (ev_path.size() < sizeof(addr.sun_path)) {
            std::strncpy(addr.sun_path, ev_path.c_str(), sizeof(addr.sun_path) - 1);
            if (::connect(events_fd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
                int flags = fcntl(events_fd, F_GETFL, 0);
                fcntl(events_fd, F_SETFL, flags | O_NONBLOCK);
            } else {
                ::close(events_fd);
                events_fd = -1;
                log_err("event socket unavailable, gaps will not follow config reloads");
            }
        } else {
            ::close(events_fd);
            events_fd = -1;
        }
    } else {
        log_err("event socket unavailable, gaps will not follow config reloads");
    }

    emit("{\"event\":\"ready\"}");
    {
        auto gaps = read_gaps(ctl);
        std::ostringstream ss;
        ss << "{\"event\":\"gaps\",\"outer\":" << gaps.outer << ",\"inner\":" << gaps.inner << "}";
        emit(ss.str());
    }

    std::string stdin_buffer;
    std::string events_buffer;
    double next_poll = get_monotonic_s();

    while (!g_stop) {
        struct pollfd fds[2];
        int nfds = 1;
        fds[0].fd = STDIN_FILENO;
        fds[0].events = POLLIN;
        fds[0].revents = 0;

        if (events_fd >= 0) {
            fds[1].fd = events_fd;
            fds[1].events = POLLIN;
            fds[1].revents = 0;
            nfds = 2;
        }

        double now = get_monotonic_s();
        double wait_s = std::max(0.0, std::min(next_poll - now, MAX_WAIT_S));
        int timeout_ms = static_cast<int>(std::ceil(wait_s * 1000.0));
        if (timeout_ms < 0) timeout_ms = 0;

        int ret = ::poll(fds, nfds, timeout_ms);
        if (g_stop) break;
        if (ret < 0) {
            if (errno == EINTR) continue;
            if (events_fd >= 0) ::close(events_fd);
            return 1;
        }

        if (fds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
            char buf[4096];
            ssize_t n = ::read(STDIN_FILENO, buf, sizeof(buf));
            if (n <= 0) {
                if (!stdin_buffer.empty()) {
                    if (!handle_stdin_command(monitor, stdin_buffer)) {
                        if (events_fd >= 0) ::close(events_fd);
                        return 0;
                    }
                    stdin_buffer.clear();
                }
                if (events_fd >= 0) ::close(events_fd);
                return 0;
            }
            stdin_buffer.append(buf, static_cast<size_t>(n));
            size_t newline_pos;
            while ((newline_pos = stdin_buffer.find('\n')) != std::string::npos) {
                std::string line = stdin_buffer.substr(0, newline_pos);
                stdin_buffer.erase(0, newline_pos + 1);
                if (!line.empty() && line.back() == '\r') {
                    line.pop_back();
                }
                if (!handle_stdin_command(monitor, line)) {
                    if (events_fd >= 0) ::close(events_fd);
                    return 0;
                }
            }
        }

        if (events_fd >= 0 && (fds[1].revents & (POLLIN | POLLHUP | POLLERR))) {
            while (true) {
                char chunk[8192];
                ssize_t n = ::recv(events_fd, chunk, sizeof(chunk), 0);
                if (n > 0) {
                    events_buffer.append(chunk, static_cast<size_t>(n));
                } else if (n == 0) {
                    ::close(events_fd);
                    events_fd = -1;
                    break;
                } else {
                    if (errno == EAGAIN || errno == EWOULDBLOCK) {
                        break;
                    } else if (errno == EINTR) {
                        continue;
                    } else {
                        ::close(events_fd);
                        events_fd = -1;
                        break;
                    }
                }
            }

            size_t newline_pos;
            while ((newline_pos = events_buffer.find('\n')) != std::string::npos) {
                std::string raw = events_buffer.substr(0, newline_pos);
                events_buffer.erase(0, newline_pos + 1);
                if (!raw.empty() && raw.back() == '\r') {
                    raw.pop_back();
                }
                size_t part = raw.find(">>");
                std::string name;
                std::string data;
                if (part != std::string::npos) {
                    name = raw.substr(0, part);
                    data = raw.substr(part + 2);
                } else {
                    name = raw;
                }

                if (name == "configreloaded") {
                    auto gaps = read_gaps(ctl);
                    std::ostringstream ss;
                    ss << "{\"event\":\"gaps\",\"outer\":" << gaps.outer << ",\"inner\":" << gaps.inner << "}";
                    emit(ss.str());
                } else {
                    size_t comma = data.find(',');
                    std::string first_part = (comma != std::string::npos) ? data.substr(0, comma) : data;
                    size_t s = 0;
                    while (s < first_part.size() && std::isspace(static_cast<unsigned char>(first_part[s]))) s++;
                    size_t e = first_part.size();
                    while (e > s && std::isspace(static_cast<unsigned char>(first_part[e - 1]))) e--;
                    monitor.event(name, first_part.substr(s, e - s));
                }
            }
        }

        now = get_monotonic_s();
        if (now >= next_poll) {
            monitor.poll();
            double interval = monitor.interval();
            next_poll = std::max(now + interval, next_poll + interval);
        }
    }

    if (events_fd >= 0) ::close(events_fd);
    return 0;
}
