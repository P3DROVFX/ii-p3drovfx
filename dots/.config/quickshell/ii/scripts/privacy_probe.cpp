#include <algorithm>
#include <cctype>
#include <cerrno>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <dirent.h>
#include <fcntl.h>
#include <iostream>
#include <malloc.h>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <linux/videodev2.h>

#ifndef V4L2_CAP_VIDEO_CAPTURE
#define V4L2_CAP_VIDEO_CAPTURE 0x00000001
#endif
#ifndef V4L2_CAP_VIDEO_CAPTURE_MPLANE
#define V4L2_CAP_VIDEO_CAPTURE_MPLANE 0x00001000
#endif
#ifndef V4L2_CAP_DEVICE_CAPS
#define V4L2_CAP_DEVICE_CAPS 0x80000000
#endif

// Drivers behind /dev/video* nodes that are codecs, not cameras.
static const std::unordered_set<std::string> CODEC_DRIVERS = {
    "amdgpu",
    "bcm2835-codec",
    "hantro-vpu",
    "mtk-vcodec",
    "rkvdec",
    "v4l2-mem2mem",
    "venus",
    "vim2m",
    "visl",
};

static const std::vector<std::string> CODEC_NAME_HINTS = {
    "codec", "decoder", "encoder", "stateless", "-dec", "-enc"
};

// Nodes the shell itself owns or non-camera background tools.
static const std::unordered_set<std::string> IGNORED_PROCESSES = {
    "qs", "quickshell", "cava", "pipewire", "wireplumber",
    "scrcpy", "colord", "systemd-udevd", "udevd", "v4l2-ctl",
    "camera-relay-mo", "camera-relay-gs"
};

static volatile sig_atomic_t g_stop = 0;

static void signal_handler(int sig) {
    (void)sig;
    g_stop = 1;
}

// Monotonic clock in seconds
static inline double get_monotonic_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<double>(ts.tv_sec) + static_cast<double>(ts.tv_nsec) * 1e-9;
}

// String helpers
static inline std::string trim(std::string_view s) {
    while (!s.empty() && static_cast<unsigned char>(s.front()) <= 0x20) {
        s.remove_prefix(1);
    }
    while (!s.empty() && static_cast<unsigned char>(s.back()) <= 0x20) {
        s.remove_suffix(1);
    }
    return std::string(s);
}

static inline std::string to_lower(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        out += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return out;
}

static inline bool starts_with(std::string_view s, std::string_view prefix) {
    return s.size() >= prefix.size() && s.substr(0, prefix.size()) == prefix;
}

static inline bool ends_with(std::string_view s, std::string_view suffix) {
    return s.size() >= suffix.size() && s.substr(s.size() - suffix.size()) == suffix;
}

static inline std::string path_basename(std::string_view p) {
    while (p.size() > 1 && p.back() == '/') {
        p.remove_suffix(1);
    }
    size_t pos = p.rfind('/');
    if (pos == std::string_view::npos) return std::string(p);
    return std::string(p.substr(pos + 1));
}

static std::string read_text(const std::string& path) {
    int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return "";
    std::string out;
    char buf[1024];
    while (true) {
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n <= 0) break;
        out.append(buf, static_cast<size_t>(n));
    }
    close(fd);
    return trim(out);
}

// Escape string for JSON
static std::string json_escape(std::string_view s) {
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
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
                break;
        }
    }
    return out;
}

// --- Recursive Descent JSON Parser ---

enum class JsonType { Null, Bool, Number, String, Array, Object };

struct JsonValue {
    JsonType type = JsonType::Null;
    bool bool_val = false;
    double num_val = 0.0;
    int64_t int_val = 0;
    std::string str_val;
    std::vector<JsonValue> arr_val;
    std::vector<std::pair<std::string, JsonValue>> obj_val;

    JsonValue() = default;
    explicit JsonValue(JsonType t) : type(t) {}

    const JsonValue* get(std::string_view key) const {
        if (type != JsonType::Object) return nullptr;
        for (const auto& kv : obj_val) {
            if (kv.first == key) return &kv.second;
        }
        return nullptr;
    }
};

class JsonParser {
    std::string_view src;
    size_t pos = 0;

    void skip_whitespace() {
        while (pos < src.size()) {
            char c = src[pos];
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                pos++;
            } else {
                break;
            }
        }
    }

    char peek() {
        skip_whitespace();
        if (pos < src.size()) return src[pos];
        return '\0';
    }

    char get() {
        skip_whitespace();
        if (pos < src.size()) return src[pos++];
        return '\0';
    }

public:
    explicit JsonParser(std::string_view s) : src(s), pos(0) {}

    bool parse_value(JsonValue& val) {
        char c = peek();
        if (c == '\0') return false;
        if (c == '{') return parse_object(val);
        if (c == '[') return parse_array(val);
        if (c == '"') return parse_string(val);
        if (c == 't' || c == 'f') return parse_bool(val);
        if (c == 'n') return parse_null(val);
        if (c == '-' || (c >= '0' && c <= '9')) return parse_number(val);
        return false;
    }

    bool parse_object(JsonValue& val) {
        if (get() != '{') return false;
        val.type = JsonType::Object;
        val.obj_val.clear();
        if (peek() == '}') {
            get();
            return true;
        }
        while (pos < src.size()) {
            JsonValue key_val;
            if (peek() != '"') return false;
            if (!parse_string(key_val)) return false;
            if (get() != ':') return false;
            JsonValue member;
            if (!parse_value(member)) return false;
            val.obj_val.emplace_back(std::move(key_val.str_val), std::move(member));
            char next = peek();
            if (next == ',') {
                get();
            } else if (next == '}') {
                get();
                return true;
            } else {
                return false;
            }
        }
        return false;
    }

    bool parse_array(JsonValue& val) {
        if (get() != '[') return false;
        val.type = JsonType::Array;
        val.arr_val.clear();
        if (peek() == ']') {
            get();
            return true;
        }
        while (pos < src.size()) {
            JsonValue elem;
            if (!parse_value(elem)) return false;
            val.arr_val.push_back(std::move(elem));
            char next = peek();
            if (next == ',') {
                get();
            } else if (next == ']') {
                get();
                return true;
            } else {
                return false;
            }
        }
        return false;
    }

    template <typename Fn>
    bool for_each_array_element(Fn&& fn) {
        if (get() != '[') return false;
        if (peek() == ']') {
            get();
            return true;
        }
        while (pos < src.size()) {
            JsonValue elem;
            if (!parse_value(elem)) return false;
            fn(elem);
            char next = peek();
            if (next == ',') {
                get();
            } else if (next == ']') {
                get();
                return true;
            } else {
                return false;
            }
        }
        return false;
    }

    bool parse_string(JsonValue& val) {
        if (get() != '"') return false;
        val.type = JsonType::String;
        val.str_val.clear();
        while (pos < src.size()) {
            char c = src[pos++];
            if (c == '"') return true;
            if (c == '\\') {
                if (pos >= src.size()) return false;
                char esc = src[pos++];
                switch (esc) {
                    case '"': val.str_val += '"'; break;
                    case '\\': val.str_val += '\\'; break;
                    case '/': val.str_val += '/'; break;
                    case 'b': val.str_val += '\b'; break;
                    case 'f': val.str_val += '\f'; break;
                    case 'n': val.str_val += '\n'; break;
                    case 'r': val.str_val += '\r'; break;
                    case 't': val.str_val += '\t'; break;
                    case 'u': {
                        if (pos + 4 > src.size()) return false;
                        uint32_t cp = 0;
                        for (int i = 0; i < 4; ++i) {
                            char h = src[pos++];
                            cp <<= 4;
                            if (h >= '0' && h <= '9') cp |= static_cast<uint32_t>(h - '0');
                            else if (h >= 'a' && h <= 'f') cp |= static_cast<uint32_t>(h - 'a' + 10);
                            else if (h >= 'A' && h <= 'F') cp |= static_cast<uint32_t>(h - 'A' + 10);
                            else return false;
                        }
                        // Handle UTF-16 surrogate pairs
                        if (cp >= 0xD800 && cp <= 0xDBFF && pos + 6 <= src.size() && src[pos] == '\\' && src[pos+1] == 'u') {
                            pos += 2;
                            uint32_t low = 0;
                            for (int i = 0; i < 4; ++i) {
                                char h = src[pos++];
                                low <<= 4;
                                if (h >= '0' && h <= '9') low |= static_cast<uint32_t>(h - '0');
                                else if (h >= 'a' && h <= 'f') low |= static_cast<uint32_t>(h - 'a' + 10);
                                else if (h >= 'A' && h <= 'F') low |= static_cast<uint32_t>(h - 'A' + 10);
                                else return false;
                            }
                            if (low >= 0xDC00 && low <= 0xDFFF) {
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                            }
                        }
                        // Encode cp as UTF-8
                        if (cp <= 0x7F) {
                            val.str_val += static_cast<char>(cp);
                        } else if (cp <= 0x7FF) {
                            val.str_val += static_cast<char>(0xC0 | ((cp >> 6) & 0x1F));
                            val.str_val += static_cast<char>(0x80 | (cp & 0x3F));
                        } else if (cp <= 0xFFFF) {
                            val.str_val += static_cast<char>(0xE0 | ((cp >> 12) & 0x0F));
                            val.str_val += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                            val.str_val += static_cast<char>(0x80 | (cp & 0x3F));
                        } else if (cp <= 0x10FFFF) {
                            val.str_val += static_cast<char>(0xF0 | ((cp >> 18) & 0x07));
                            val.str_val += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
                            val.str_val += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                            val.str_val += static_cast<char>(0x80 | (cp & 0x3F));
                        }
                        break;
                    }
                    default:
                        val.str_val += esc;
                        break;
                }
            } else {
                val.str_val += c;
            }
        }
        return false;
    }

    bool parse_bool(JsonValue& val) {
        skip_whitespace();
        if (pos + 4 <= src.size() && src.substr(pos, 4) == "true") {
            pos += 4;
            val.type = JsonType::Bool;
            val.bool_val = true;
            return true;
        }
        if (pos + 5 <= src.size() && src.substr(pos, 5) == "false") {
            pos += 5;
            val.type = JsonType::Bool;
            val.bool_val = false;
            return true;
        }
        return false;
    }

    bool parse_null(JsonValue& val) {
        skip_whitespace();
        if (pos + 4 <= src.size() && src.substr(pos, 4) == "null") {
            pos += 4;
            val.type = JsonType::Null;
            return true;
        }
        return false;
    }

    bool parse_number(JsonValue& val) {
        skip_whitespace();
        size_t start = pos;
        if (pos < src.size() && src[pos] == '-') pos++;
        while (pos < src.size() && (src[pos] >= '0' && src[pos] <= '9')) pos++;
        bool is_float = false;
        if (pos < src.size() && src[pos] == '.') {
            is_float = true;
            pos++;
            while (pos < src.size() && (src[pos] >= '0' && src[pos] <= '9')) pos++;
        }
        if (pos < src.size() && (src[pos] == 'e' || src[pos] == 'E')) {
            is_float = true;
            pos++;
            if (pos < src.size() && (src[pos] == '+' || src[pos] == '-')) pos++;
            while (pos < src.size() && (src[pos] >= '0' && src[pos] <= '9')) pos++;
        }
        std::string num_str(src.substr(start, pos - start));
        val.type = JsonType::Number;
        char* end = nullptr;
        if (is_float) {
            val.num_val = std::strtod(num_str.c_str(), &end);
            val.int_val = static_cast<int64_t>(val.num_val);
        } else {
            val.int_val = std::strtoll(num_str.c_str(), &end, 10);
            val.num_val = static_cast<double>(val.int_val);
        }
        return true;
    }
};

// --- Privacy Probe Data Structures ---

struct Item {
    std::string kind;
    std::string app;
    int64_t pid = 0;
    std::string detail;

    bool operator==(const Item& o) const = default;
};

struct PwClient {
    int64_t id = 0;
    std::string app_name;
    std::string app_binary;
    int64_t app_pid = 0;
};

struct PwNode {
    int64_t id = 0;
    std::string state;
    std::string media_class;
    std::string media_role;
    std::string node_name;
    std::string node_description;
    bool bluez5_loopback = false;
    int64_t client_id = -1;
    std::string app_name;
    std::string app_binary;
    int64_t app_pid = 0;
};

static int64_t get_int_or_str(const JsonValue* obj, std::string_view key, int64_t default_val = 0) {
    if (!obj || obj->type != JsonType::Object) return default_val;
    const JsonValue* val = obj->get(key);
    if (!val) return default_val;
    if (val->type == JsonType::Number) return val->int_val;
    if (val->type == JsonType::String && !val->str_val.empty()) {
        char* end = nullptr;
        int64_t n = std::strtoll(val->str_val.c_str(), &end, 10);
        if (end != val->str_val.c_str()) return n;
    }
    return default_val;
}

static std::string get_string_prop(const JsonValue* obj, std::string_view key) {
    if (!obj || obj->type != JsonType::Object) return "";
    const JsonValue* val = obj->get(key);
    if (!val) return "";
    if (val->type == JsonType::String) return val->str_val;
    return "";
}

static bool get_bool_prop(const JsonValue* obj, std::string_view key) {
    if (!obj || obj->type != JsonType::Object) return false;
    const JsonValue* val = obj->get(key);
    if (!val) return false;
    if (val->type == JsonType::Bool) return val->bool_val;
    if (val->type == JsonType::String) return val->str_val == "true";
    return false;
}

static void extract_pw_client(const JsonValue& obj, PwClient& client) {
    client.id = get_int_or_str(&obj, "id", 0);
    const JsonValue* info = obj.get("info");
    if (info && info->type == JsonType::Object) {
        const JsonValue* props = info->get("props");
        if (props && props->type == JsonType::Object) {
            client.app_name = get_string_prop(props, "application.name");
            client.app_binary = get_string_prop(props, "application.process.binary");
            client.app_pid = get_int_or_str(props, "application.process.id", 0);
        }
    }
}

static void extract_pw_node(const JsonValue& obj, PwNode& node) {
    node.id = get_int_or_str(&obj, "id", 0);
    const JsonValue* info = obj.get("info");
    if (info && info->type == JsonType::Object) {
        node.state = get_string_prop(info, "state");
        const JsonValue* props = info->get("props");
        if (props && props->type == JsonType::Object) {
            node.media_class = get_string_prop(props, "media.class");
            node.media_role = get_string_prop(props, "media.role");
            node.node_name = get_string_prop(props, "node.name");
            node.node_description = get_string_prop(props, "node.description");
            node.bluez5_loopback = get_bool_prop(props, "bluez5.loopback");
            node.client_id = get_int_or_str(props, "client.id", -1);
            node.app_name = get_string_prop(props, "application.name");
            node.app_binary = get_string_prop(props, "application.process.binary");
            node.app_pid = get_int_or_str(props, "application.process.id", 0);
        }
    }
}

// Subprocess execution with timeout
struct CommandResult {
    int exit_code = -1;
    bool timed_out = false;
    std::string stdout_str;
};

static CommandResult run_command_with_timeout(const std::vector<std::string>& args, double timeout_sec) {
    CommandResult result;
    if (args.empty()) return result;

    int pipefds[2];
    if (pipe(pipefds) != 0) return result;

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefds[0]);
        close(pipefds[1]);
        return result;
    }

    if (pid == 0) {
        prctl(PR_SET_PDEATHSIG, SIGTERM);

        int devnull = open("/dev/null", O_RDWR);
        if (devnull >= 0) {
            dup2(devnull, STDIN_FILENO);
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }

        dup2(pipefds[1], STDOUT_FILENO);
        close(pipefds[0]);
        close(pipefds[1]);

        setenv("LANG", "C", 1);
        setenv("LC_ALL", "C", 1);

        std::vector<char*> c_argv;
        c_argv.reserve(args.size() + 1);
        for (const auto& a : args) {
            c_argv.push_back(const_cast<char*>(a.c_str()));
        }
        c_argv.push_back(nullptr);

        execvp(c_argv[0], c_argv.data());
        _exit(127);
    }

    close(pipefds[1]);
    int read_fd = pipefds[0];

    int flags = fcntl(read_fd, F_GETFL, 0);
    if (flags >= 0) fcntl(read_fd, F_SETFL, flags | O_NONBLOCK);

    double start_time = get_monotonic_time();
    double deadline = start_time + timeout_sec;

    std::string out;
    char buf[4096];

    while (true) {
        double now = get_monotonic_time();
        if (now >= deadline) {
            result.timed_out = true;
            break;
        }

        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(read_fd, &rfds);

        double remain = deadline - now;
        struct timeval tv;
        tv.tv_sec = static_cast<time_t>(remain);
        tv.tv_usec = static_cast<suseconds_t>((remain - static_cast<double>(tv.tv_sec)) * 1e6);

        int sret = select(read_fd + 1, &rfds, nullptr, nullptr, &tv);
        if (sret < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (sret == 0) {
            result.timed_out = true;
            break;
        }

        if (FD_ISSET(read_fd, &rfds)) {
            ssize_t n = read(read_fd, buf, sizeof(buf));
            if (n < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
                if (errno == EINTR) continue;
                break;
            }
            if (n == 0) {
                break;
            }
            out.append(buf, static_cast<size_t>(n));
        }
    }

    close(read_fd);

    if (result.timed_out) {
        kill(pid, SIGKILL);
    }

    int status = 0;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status)) {
        result.exit_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result.exit_code = 128 + WTERMSIG(status);
    }

    result.stdout_str = std::move(out);
    return result;
}

// --- V4L2 and Camera Detection ---

struct V4L2Caps {
    std::string driver;
    std::string card;
    uint32_t caps = 0;
};

static V4L2Caps query_v4l2_caps(const std::string& dev_path) {
    V4L2Caps res;
    int fd = open(dev_path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return res;

    struct v4l2_capability cap;
    std::memset(&cap, 0, sizeof(cap));
    if (ioctl(fd, VIDIOC_QUERYCAP, &cap) == 0) {
        char drv[17] = {0};
        char crd[33] = {0};
        std::memcpy(drv, cap.driver, 16);
        std::memcpy(crd, cap.card, 32);
        res.driver = drv;
        res.card = crd;
        res.caps = (cap.capabilities & V4L2_CAP_DEVICE_CAPS) ? cap.device_caps : cap.capabilities;
    }
    close(fd);
    return res;
}

static std::unordered_map<std::string, std::string> video_capture_nodes() {
    std::unordered_map<std::string, std::string> nodes;
    DIR* dir = opendir("/sys/class/video4linux");
    if (!dir) return nodes;

    std::vector<std::string> entries;
    struct dirent* ent = nullptr;
    while ((ent = readdir(dir)) != nullptr) {
        if (starts_with(ent->d_name, "video")) {
            entries.push_back(ent->d_name);
        }
    }
    closedir(dir);

    std::sort(entries.begin(), entries.end());

    for (const auto& entry_name : entries) {
        std::string dev_path = "/dev/" + entry_name;
        std::string label = read_text("/sys/class/video4linux/" + entry_name + "/name");
        if (label.empty()) label = entry_name;

        std::string driver;
        char drv_buf[PATH_MAX];
        std::string drv_link = "/sys/class/video4linux/" + entry_name + "/device/driver";
        if (realpath(drv_link.c_str(), drv_buf)) {
            driver = path_basename(drv_buf);
        }

        V4L2Caps caps = query_v4l2_caps(dev_path);
        if (!caps.driver.empty()) driver = caps.driver;
        if (!caps.card.empty()) label = caps.card;

        std::string lowered = to_lower(label);
        if (CODEC_DRIVERS.count(driver) > 0) continue;
        bool has_hint = false;
        for (const auto& hint : CODEC_NAME_HINTS) {
            if (lowered.find(hint) != std::string::npos) {
                has_hint = true;
                break;
            }
        }
        if (has_hint) continue;

        if (caps.caps != 0) {
            bool is_capture = (caps.caps & (V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_VIDEO_CAPTURE_MPLANE)) != 0;
            if (!is_capture) continue;
            std::string drv_lower = to_lower(driver);
            if (lowered.find("scrcpy") != std::string::npos || drv_lower.find("scrcpy") != std::string::npos) {
                continue;
            }
        }

        size_t colon_pos = label.find(':');
        std::string formatted = (colon_pos != std::string::npos) ? label.substr(0, colon_pos) : label;
        for (char& c : formatted) {
            if (c == '_') c = ' ';
        }
        formatted = trim(formatted);
        if (formatted.empty()) formatted = entry_name;

        nodes[dev_path] = formatted;
    }
    return nodes;
}

static std::string process_name(const std::string& pid_str) {
    return read_text("/proc/" + pid_str + "/comm");
}

static bool is_write_only_fd(const std::string& pid_str, const std::string& fd_name) {
    std::string path = "/proc/" + pid_str + "/fdinfo/" + fd_name;
    int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;
    std::string content;
    char buf[512];
    while (true) {
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n <= 0) break;
        content.append(buf, static_cast<size_t>(n));
    }
    close(fd);

    size_t pos = 0;
    while (pos < content.size()) {
        size_t next = content.find('\n', pos);
        std::string_view line = (next != std::string::npos) 
            ? std::string_view(content).substr(pos, next - pos)
            : std::string_view(content).substr(pos);
        if (starts_with(line, "flags:")) {
            std::string_view rest = line.substr(6);
            while (!rest.empty() && (rest.front() == ' ' || rest.front() == '\t')) {
                rest.remove_prefix(1);
            }
            if (!rest.empty()) {
                unsigned long val = std::strtoul(rest.data(), nullptr, 8);
                return (val & 3) == O_WRONLY;
            }
        }
        if (next == std::string::npos) break;
        pos = next + 1;
    }
    return false;
}

static bool is_node_suspended(const std::string& node_path) {
    std::string dev_name = path_basename(node_path);
    std::string base = "/sys/class/video4linux/" + dev_name + "/device";
    char resolved[PATH_MAX];
    if (!realpath(base.c_str(), resolved)) {
        return false;
    }
    std::string curr = resolved;
    for (int i = 0; i < 4; ++i) {
        std::string rt = curr + "/power/runtime_status";
        if (access(rt.c_str(), F_OK) == 0) {
            return read_text(rt) == "suspended";
        }
        size_t last_slash = curr.rfind('/');
        if (last_slash == std::string::npos || last_slash == 0) {
            break;
        }
        curr = curr.substr(0, last_slash);
    }
    return false;
}

static std::vector<Item> camera_users(const std::unordered_map<std::string, std::string>& nodes) {
    if (nodes.empty()) return {};

    std::map<std::pair<int64_t, std::string>, Item> found;
    DIR* proc_dir = opendir("/proc");
    if (!proc_dir) return {};

    struct dirent* ent = nullptr;
    while ((ent = readdir(proc_dir)) != nullptr) {
        bool is_digit = ent->d_name[0] != '\0';
        for (const char* p = ent->d_name; *p; ++p) {
            if (*p < '0' || *p > '9') {
                is_digit = false;
                break;
            }
        }
        if (!is_digit) continue;

        std::string pid_str = ent->d_name;
        int64_t pid = std::strtoll(pid_str.c_str(), nullptr, 10);
        std::string fd_dir_path = "/proc/" + pid_str + "/fd";

        DIR* fd_dir = opendir(fd_dir_path.c_str());
        if (!fd_dir) continue;

        struct dirent* fd_ent = nullptr;
        while ((fd_ent = readdir(fd_dir)) != nullptr) {
            if (fd_ent->d_name[0] == '.') continue;
            std::string handle_path = fd_dir_path + "/" + fd_ent->d_name;
            char target_buf[PATH_MAX];
            ssize_t len = readlink(handle_path.c_str(), target_buf, sizeof(target_buf) - 1);
            if (len <= 0) continue;
            target_buf[len] = '\0';
            std::string target = target_buf;

            auto it = nodes.find(target);
            if (it == nodes.end()) continue;

            std::string name = process_name(pid_str);
            if (name.empty() || IGNORED_PROCESSES.count(to_lower(name)) > 0) {
                continue;
            }

            if (is_write_only_fd(pid_str, fd_ent->d_name)) {
                continue;
            }

            if (is_node_suspended(target)) {
                continue;
            }

            std::pair<int64_t, std::string> key{pid, target};
            found[key] = Item{
                .kind = "camera",
                .app = name,
                .pid = pid,
                .detail = it->second,
            };
        }
        closedir(fd_dir);
    }
    closedir(proc_dir);

    std::vector<Item> out;
    out.reserve(found.size());
    for (auto& [_, item] : found) {
        out.push_back(std::move(item));
    }
    return out;
}

// --- PipeWire Classification & Monitor ---

static std::vector<Item> streams_from_nodes(
    const std::vector<PwNode>& nodes,
    const std::unordered_map<int64_t, PwClient>& clients
) {
    std::vector<Item> streams;

    static const std::unordered_set<std::string> screen_roles = {
        "screen", "screenshare", "screencapture", "window", "display", "desktop"
    };
    static const std::vector<std::string> screen_desc_hints = {
        "screen", "screencast", "desktop", "display", "window capture"
    };
    static const std::vector<std::string> screen_name_hints = {
        "screen", "screencast", "desktop", "display", "xdg-desktop-portal"
    };

    for (const auto& node : nodes) {
        if (node.state != "running") continue;

        if (ends_with(node.media_class, "/Internal") ||
            node.bluez5_loopback ||
            starts_with(node.node_name, "bluez_capture")) {
            continue;
        }

        std::string kind;
        if (node.media_class == "Stream/Input/Audio") {
            kind = "microphone";
        } else if (node.media_class == "Stream/Input/Video") {
            std::string role_lower = to_lower(node.media_role);
            std::string desc_lower = to_lower(node.node_description);
            std::string name_lower = to_lower(node.node_name);

            bool is_screen = (screen_roles.count(role_lower) > 0);
            if (!is_screen) {
                for (const auto& h : screen_desc_hints) {
                    if (desc_lower.find(h) != std::string::npos) {
                        is_screen = true;
                        break;
                    }
                }
            }
            if (!is_screen) {
                for (const auto& h : screen_name_hints) {
                    if (name_lower.find(h) != std::string::npos) {
                        is_screen = true;
                        break;
                    }
                }
            }
            kind = is_screen ? "screen" : "camera";
        } else {
            continue;
        }

        std::string client_binary;
        std::string client_name;
        int64_t client_pid = 0;

        if (node.client_id >= 0) {
            auto it = clients.find(node.client_id);
            if (it != clients.end()) {
                client_binary = it->second.app_binary;
                client_name = it->second.app_name;
                client_pid = it->second.app_pid;
            }
        }

        std::string binary = !node.app_binary.empty() ? node.app_binary : client_binary;
        std::string app;
        if (!node.app_name.empty()) {
            app = node.app_name;
        } else if (!client_name.empty()) {
            app = client_name;
        } else if (!binary.empty()) {
            app = binary;
        } else if (!node.node_description.empty()) {
            app = node.node_description;
        } else if (!node.node_name.empty()) {
            app = node.node_name;
        }
        app = trim(app);

        std::string app_lower = to_lower(app);
        std::string binary_lower = to_lower(binary);
        std::string client_name_lower = to_lower(client_name);

        if (app.empty() ||
            IGNORED_PROCESSES.count(app_lower) > 0 ||
            IGNORED_PROCESSES.count(binary_lower) > 0 ||
            IGNORED_PROCESSES.count(client_name_lower) > 0 ||
            app_lower.find("wireplumber") != std::string::npos ||
            app_lower.find("pipewire") != std::string::npos ||
            client_name_lower.find("wireplumber") != std::string::npos ||
            client_name_lower.find("pipewire") != std::string::npos) {
            continue;
        }

        int64_t pid = node.app_pid != 0 ? node.app_pid : client_pid;
        std::string detail = !node.node_description.empty() ? node.node_description : node.node_name;

        streams.push_back(Item{
            .kind = std::move(kind),
            .app = std::move(app),
            .pid = pid,
            .detail = std::move(detail),
        });
    }

    return streams;
}

static std::vector<Item> pipewire_streams() {
    std::vector<std::string> args = {"pw-dump"};
    auto res = run_command_with_timeout(args, 4.0);
    if (res.exit_code != 0 || trim(res.stdout_str).empty()) {
        return {};
    }
    std::unordered_map<int64_t, PwClient> clients;
    std::vector<PwNode> nodes;
    JsonParser parser(res.stdout_str);
    bool ok = parser.for_each_array_element([&](const JsonValue& obj) {
        if (obj.type != JsonType::Object) return;
        const JsonValue* type_val = obj.get("type");
        std::string type_str = (type_val && type_val->type == JsonType::String) ? type_val->str_val : "";
        if (type_str == "PipeWire:Interface:Client") {
            PwClient cl;
            extract_pw_client(obj, cl);
            clients[cl.id] = std::move(cl);
        } else if (type_str.empty() || type_str == "PipeWire:Interface:Node") {
            PwNode nd;
            extract_pw_node(obj, nd);
            nodes.push_back(std::move(nd));
        }
    });
    res.stdout_str.clear();
    res.stdout_str.shrink_to_fit();
    malloc_trim(0);
    if (!ok) {
        return {};
    }
    return streams_from_nodes(nodes, clients);
}

class PipewireMonitor {
public:
    static constexpr double RESPAWN_MIN = 1.0;
    static constexpr double RESPAWN_MAX = 30.0;

    pid_t child_pid = -1;
    int pipe_fd = -1;
    std::unordered_map<int64_t, PwNode> nodes;
    std::unordered_map<int64_t, PwClient> clients;
    bool ready = false;

    std::string partial;
    std::string block_buf;
    double respawn_at = 0.0;
    double backoff = RESPAWN_MIN;

    PipewireMonitor() = default;
    ~PipewireMonitor() {
        stop();
    }

    int fileno() const {
        return pipe_fd;
    }

    std::optional<double> respawn_due(double now) const {
        (void)now;
        if (child_pid > 0) return std::nullopt;
        return respawn_at;
    }

    void start(double now) {
        if (child_pid > 0 || now < respawn_at) {
            return;
        }
        int pipefds[2];
        if (pipe(pipefds) != 0) {
            schedule_respawn(now);
            return;
        }

        pid_t pid = fork();
        if (pid < 0) {
            close(pipefds[0]);
            close(pipefds[1]);
            schedule_respawn(now);
            return;
        }

        if (pid == 0) {
            prctl(PR_SET_PDEATHSIG, SIGTERM);

            int devnull = open("/dev/null", O_RDWR);
            if (devnull >= 0) {
                dup2(devnull, STDIN_FILENO);
                dup2(devnull, STDERR_FILENO);
                close(devnull);
            }

            dup2(pipefds[1], STDOUT_FILENO);
            close(pipefds[0]);
            close(pipefds[1]);

            setenv("LANG", "C", 1);
            setenv("LC_ALL", "C", 1);

            char* const argv[] = {
                const_cast<char*>("pw-dump"),
                const_cast<char*>("--monitor"),
                const_cast<char*>("--no-colors"),
                nullptr
            };
            execvp("pw-dump", argv);
            _exit(127);
        }

        close(pipefds[1]);
        child_pid = pid;
        pipe_fd = pipefds[0];

        int flags = fcntl(pipe_fd, F_GETFL, 0);
        if (flags >= 0) {
            fcntl(pipe_fd, F_SETFL, flags | O_NONBLOCK);
        }
        fcntl(pipe_fd, F_SETFD, FD_CLOEXEC);
    }

    void schedule_respawn(double now) {
        respawn_at = now + backoff;
        backoff = std::min(RESPAWN_MAX, backoff * 2.0);
    }

    void stop() {
        if (child_pid > 0) {
            kill(child_pid, SIGKILL);
            int status = 0;
            waitpid(child_pid, &status, 0);
            child_pid = -1;
        }
        if (pipe_fd >= 0) {
            close(pipe_fd);
            pipe_fd = -1;
        }
        clients.clear();
    }

    bool read(double now) {
        if (pipe_fd < 0) return false;
        bool changed = false;
        char buf[16384];
        while (true) {
            ssize_t n = ::read(pipe_fd, buf, sizeof(buf));
            if (n < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    break;
                }
                if (errno == EINTR) {
                    continue;
                }
                n = 0;
            }
            if (n == 0) {
                stop();
                nodes.clear();
                clients.clear();
                ready = false;
                partial.clear();
                partial.shrink_to_fit();
                block_buf.clear();
                block_buf.shrink_to_fit();
                malloc_trim(0);
                schedule_respawn(now);
                return true;
            }
            changed |= feed(buf, static_cast<size_t>(n));
        }
        return changed;
    }

    bool feed(const char* chunk, size_t len) {
        partial.append(chunk, len);
        bool changed = false;
        bool parsed_any_block = false;
        size_t start = 0;
        size_t pos = 0;
        while ((pos = partial.find('\n', start)) != std::string::npos) {
            std::string_view line(partial.data() + start, pos - start);
            start = pos + 1;
            if (!block_buf.empty()) block_buf += '\n';
            block_buf.append(line.data(), line.size());

            std::string_view sv = line;
            while (!sv.empty() && (sv.back() == '\r' || sv.back() == ' ' || sv.back() == '\t')) {
                sv.remove_suffix(1);
            }
            if (sv == "]") {
                changed |= apply_streaming(block_buf);
                block_buf.clear();
                parsed_any_block = true;
            }
        }
        if (start > 0) {
            partial.erase(0, start);
        }
        if (parsed_any_block) {
            block_buf.shrink_to_fit();
            partial.shrink_to_fit();
            malloc_trim(0);
        }
        return changed;
    }

    bool apply_streaming(std::string_view text) {
        auto next_nodes = nodes;
        auto next_clients = clients;
        bool block_changed = false;

        JsonParser parser(text);
        bool ok = parser.for_each_array_element([&](const JsonValue& obj) {
            if (obj.type != JsonType::Object) return;
            const JsonValue* id_val = obj.get("id");
            if (!id_val) return;
            int64_t obj_id = (id_val->type == JsonType::Number)
                ? id_val->int_val
                : std::strtoll(id_val->str_val.c_str(), nullptr, 10);

            const JsonValue* type_val = obj.get("type");
            const JsonValue* info_val = obj.get("info");

            if (!type_val && (!info_val || info_val->type == JsonType::Null)) {
                if (next_nodes.erase(obj_id) > 0) {
                    block_changed = true;
                }
                next_clients.erase(obj_id);
            } else if (type_val && type_val->type == JsonType::String && type_val->str_val == "PipeWire:Interface:Node") {
                PwNode node;
                extract_pw_node(obj, node);
                next_nodes[obj_id] = std::move(node);
                block_changed = true;
            } else if (type_val && type_val->type == JsonType::String && type_val->str_val == "PipeWire:Interface:Client") {
                PwClient client;
                extract_pw_client(obj, client);
                next_clients[obj_id] = std::move(client);
                block_changed = true;
            }
        });

        if (!ok) return false;
        bool changed = !ready || block_changed;
        ready = true;
        backoff = RESPAWN_MIN;
        nodes = std::move(next_nodes);
        clients = std::move(next_clients);
        return changed;
    }

    std::vector<Item> streams() const {
        std::vector<PwNode> node_list;
        node_list.reserve(nodes.size());
        for (const auto& [_, node] : nodes) {
            node_list.push_back(node);
        }
        return streams_from_nodes(node_list, clients);
    }
};

// --- GeoClue2 Location Detection ---

static std::vector<Item> location_in_use() {
    std::vector<std::string> busctl_cmd = {
        "busctl",
        "--system",
        "get-property",
        "org.freedesktop.GeoClue2",
        "/org/freedesktop/GeoClue2/Manager",
        "org.freedesktop.GeoClue2.Manager",
        "InUse"
    };
    auto res = run_command_with_timeout(busctl_cmd, 4.0);
    if (res.exit_code == 0 && trim(res.stdout_str) == "b true") {
        return {{"location", "", 0, ""}};
    }
    return {};
}

// --- NodeWatch (inotify) ---

class NodeWatch {
public:
    int fd = -1;
    bool complete = false;
    std::unordered_map<int, int> net;
    std::unordered_map<int, int> baseline;
    bool overflowed = false;

    NodeWatch() {
        fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    }

    ~NodeWatch() {
        if (fd >= 0) {
            close(fd);
            fd = -1;
        }
    }

    void watch(const std::unordered_map<std::string, std::string>& nodes) {
        if (fd < 0) {
            complete = false;
            return;
        }
        uint32_t mask = IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE;
        bool ok = true;
        for (const auto& [node, _] : nodes) {
            int wd = inotify_add_watch(fd, node.c_str(), mask);
            if (wd < 0) {
                ok = false;
            }
        }
        complete = ok;
    }

    bool drain() {
        if (fd < 0) return false;
        bool fired = false;
        char buf[65536];
        while (true) {
            ssize_t len = ::read(fd, buf, sizeof(buf));
            if (len <= 0) break;
            fired = true;
            count_events(buf, static_cast<size_t>(len));
        }
        return fired;
    }

    void count_events(const char* buf, size_t len) {
        size_t offset = 0;
        while (offset + sizeof(struct inotify_event) <= len) {
            const auto* event = reinterpret_cast<const struct inotify_event*>(buf + offset);
            offset += sizeof(struct inotify_event) + event->len;
            if (event->mask & IN_Q_OVERFLOW) {
                overflowed = true;
            } else if (event->mask & IN_OPEN) {
                net[event->wd]++;
            } else if (event->mask & (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE)) {
                net[event->wd]--;
            }
        }
    }

    bool moved() const {
        if (overflowed) return true;
        for (const auto& [wd, count] : net) {
            auto it = baseline.find(wd);
            int base = (it != baseline.end()) ? it->second : 0;
            if (count != base) return true;
        }
        return false;
    }

    void mark_walked() {
        overflowed = false;
        baseline = net;
    }
};

// --- Collect, Deduplication and Formatting ---

static std::vector<Item> collect(
    const std::unordered_set<std::string>& kinds,
    const std::unordered_map<std::string, std::string>& nodes,
    const std::vector<Item>* streams_ptr = nullptr,
    const std::vector<Item>* cameras_ptr = nullptr
) {
    std::vector<Item> items;

    bool needs_pw = (kinds.count("camera") || kinds.count("microphone") || kinds.count("screen"));
    if (needs_pw) {
        if (streams_ptr) {
            items.insert(items.end(), streams_ptr->begin(), streams_ptr->end());
        } else {
            auto pw = pipewire_streams();
            items.insert(items.end(), pw.begin(), pw.end());
        }
    }

    if (kinds.count("camera")) {
        if (cameras_ptr) {
            items.insert(items.end(), cameras_ptr->begin(), cameras_ptr->end());
        } else {
            auto cam = camera_users(nodes);
            items.insert(items.end(), cam.begin(), cam.end());
        }
    }

    if (kinds.count("location")) {
        auto loc = location_in_use();
        items.insert(items.end(), loc.begin(), loc.end());
    }

    struct Key {
        std::string kind;
        std::string app_lower;
        int64_t pid;

        bool operator<(const Key& o) const {
            if (kind != o.kind) return kind < o.kind;
            if (app_lower != o.app_lower) return app_lower < o.app_lower;
            return pid < o.pid;
        }
    };

    std::map<Key, Item> deduped;
    for (auto& item : items) {
        if (kinds.count(item.kind) == 0) continue;
        Key k{item.kind, to_lower(item.app), item.pid};
        deduped[k] = std::move(item);
    }

    std::vector<Item> out;
    out.reserve(deduped.size());
    for (auto& [_, item] : deduped) {
        out.push_back(std::move(item));
    }

    std::sort(out.begin(), out.end(), [](const Item& a, const Item& b) {
        if (a.kind != b.kind) return a.kind < b.kind;
        return to_lower(a.app) < to_lower(b.app);
    });

    return out;
}

static std::string emit(const std::vector<Item>& items, std::optional<std::string>& last) {
    std::string payload;
    payload.reserve(64 + items.size() * 96);
    payload += "{\"ok\":true,\"items\":[";
    for (size_t i = 0; i < items.size(); ++i) {
        if (i > 0) payload += ',';
        payload += "{\"kind\":\"";
        payload += json_escape(items[i].kind);
        payload += "\",\"app\":\"";
        payload += json_escape(items[i].app);
        payload += "\",\"pid\":";
        payload += std::to_string(items[i].pid);
        payload += ",\"detail\":\"";
        payload += json_escape(items[i].detail);
        payload += "\"}";
    }
    payload += "]}";

    if (!last.has_value() || payload != *last) {
        if (fputs(payload.c_str(), stdout) < 0 || fputc('\n', stdout) < 0 || fflush(stdout) != 0) {
            g_stop = 1;
        }
        last = payload;
    }
    return payload;
}

// --- Main Event Loop ---

static constexpr double SETTLE = 0.25;
static constexpr double CAMERA_SETTLE = 0.4;
static constexpr double RESCAN_EVERY = 30.0;

static int run_loop(const std::unordered_set<std::string>& kinds,
                    std::unordered_map<std::string, std::string> nodes,
                    double interval) {
    bool watch_pw = (kinds.count("camera") || kinds.count("microphone") || kinds.count("screen"));
    bool watch_camera = (kinds.count("camera") > 0);
    bool poll_location = (kinds.count("location") > 0);

    std::unique_ptr<PipewireMonitor> monitor;
    if (watch_pw) {
        monitor = std::make_unique<PipewireMonitor>();
    }

    std::unique_ptr<NodeWatch> node_watch;
    if (watch_camera) {
        node_watch = std::make_unique<NodeWatch>();
        node_watch->watch(nodes);
    }

    double now = get_monotonic_time();
    if (monitor) {
        monitor->start(now);
    }

    std::vector<Item> cameras = watch_camera ? camera_users(nodes) : std::vector<Item>{};
    std::optional<double> camera_due;
    bool camera_forced = false;

    if (node_watch) {
        node_watch->mark_walked();
    }

    double rescan_at = now + RESCAN_EVERY;
    double poll_at = now + interval;
    std::optional<double> emit_at = now;
    std::optional<std::string> last;

    while (!g_stop) {
        now = get_monotonic_time();

        bool camera_poll = watch_camera && (!cameras.empty() || !(node_watch && node_watch->complete));
        bool polling = poll_location || camera_poll;

        std::vector<double> deadlines;
        deadlines.push_back(rescan_at);
        if (polling) deadlines.push_back(poll_at);
        if (emit_at.has_value()) deadlines.push_back(*emit_at);
        if (camera_due.has_value()) deadlines.push_back(*camera_due);
        if (monitor) {
            auto respawn = monitor->respawn_due(now);
            if (respawn.has_value()) deadlines.push_back(*respawn);
        }

        double min_deadline = deadlines[0];
        for (double d : deadlines) {
            if (d < min_deadline) min_deadline = d;
        }
        double timeout = std::max(0.0, min_deadline - now);

        fd_set read_fds;
        FD_ZERO(&read_fds);
        int max_fd = -1;

        if (monitor && monitor->fileno() >= 0) {
            FD_SET(monitor->fileno(), &read_fds);
            max_fd = std::max(max_fd, monitor->fileno());
        }
        if (node_watch && node_watch->fd >= 0 && !camera_due.has_value()) {
            FD_SET(node_watch->fd, &read_fds);
            max_fd = std::max(max_fd, node_watch->fd);
        }

        struct timeval tv;
        tv.tv_sec = static_cast<time_t>(timeout);
        tv.tv_usec = static_cast<suseconds_t>((timeout - static_cast<double>(tv.tv_sec)) * 1e6);

        int ready_count = select(max_fd + 1, &read_fds, nullptr, nullptr, &tv);
        if (g_stop) break;
        if (ready_count < 0) {
            if (errno == EINTR) continue;
            break;
        }

        now = get_monotonic_time();

        if (monitor) {
            if (monitor->fileno() >= 0 && FD_ISSET(monitor->fileno(), &read_fds)) {
                if (monitor->read(now) && !emit_at.has_value()) {
                    emit_at = now + SETTLE;
                }
            }
            if (monitor->child_pid <= 0) {
                monitor->start(now);
            }
        }

        if (node_watch && node_watch->fd >= 0 && FD_ISSET(node_watch->fd, &read_fds)) {
            if (node_watch->drain()) {
                camera_due = now + CAMERA_SETTLE;
            }
        }

        if (now >= rescan_at) {
            nodes = video_capture_nodes();
            if (node_watch) {
                node_watch->watch(nodes);
            }
            if (watch_camera) {
                camera_forced = true;
                camera_due = now;
            }
            rescan_at = now + RESCAN_EVERY;
        }

        if (polling && now >= poll_at) {
            if (camera_poll) {
                camera_forced = true;
                camera_due = now;
            }
            poll_at = now + interval;
            if (!emit_at.has_value()) {
                emit_at = now;
            }
        }

        if (camera_due.has_value() && now >= *camera_due) {
            camera_due = std::nullopt;
            if (node_watch) {
                node_watch->drain();
            }
            if (camera_forced || (node_watch && node_watch->moved())) {
                camera_forced = false;
                if (node_watch) {
                    node_watch->mark_walked();
                }
                auto fresh = camera_users(nodes);
                if (fresh != cameras) {
                    cameras = std::move(fresh);
                    if (!emit_at.has_value()) {
                        emit_at = now;
                    }
                }
                if (!cameras.empty() && poll_at < now) {
                    poll_at = now + interval;
                }
            }
        }

        if (emit_at.has_value() && now >= *emit_at) {
            emit_at = std::nullopt;
            if (monitor && !monitor->ready && monitor->child_pid > 0) {
                emit_at = now + SETTLE;
                continue;
            }
            auto streams = monitor ? monitor->streams() : std::vector<Item>{};
            emit(collect(kinds, nodes, &streams, &cameras), last);
        }
    }

    if (monitor) {
        monitor->stop();
    }
    return 0;
}

// --- CLI Parsing and Main ---

struct CommandLineArgs {
    double interval = 1.2;
    std::unordered_set<std::string> kinds = {"camera", "microphone", "screen"};
    bool once = false;
};

static CommandLineArgs parse_cli_args(int argc, char* argv[]) {
    CommandLineArgs args;
    for (int i = 1; i < argc; ++i) {
        std::string_view arg = argv[i];
        if (arg == "--once") {
            args.once = true;
        } else if (arg == "--interval") {
            if (i + 1 < argc) {
                args.interval = std::atof(argv[++i]);
            }
        } else if (starts_with(arg, "--interval=")) {
            args.interval = std::atof(arg.substr(11).data());
        } else if (arg == "--kinds") {
            if (i + 1 < argc) {
                args.kinds.clear();
                std::string raw = argv[++i];
                size_t start = 0;
                while (start < raw.size()) {
                    size_t comma = raw.find(',', start);
                    std::string part = (comma != std::string::npos)
                        ? raw.substr(start, comma - start)
                        : raw.substr(start);
                    part = trim(part);
                    if (!part.empty()) args.kinds.insert(std::move(part));
                    if (comma == std::string::npos) break;
                    start = comma + 1;
                }
            }
        } else if (starts_with(arg, "--kinds=")) {
            args.kinds.clear();
            std::string raw = std::string(arg.substr(8));
            size_t start = 0;
            while (start < raw.size()) {
                size_t comma = raw.find(',', start);
                std::string part = (comma != std::string::npos)
                    ? raw.substr(start, comma - start)
                    : raw.substr(start);
                part = trim(part);
                if (!part.empty()) args.kinds.insert(std::move(part));
                if (comma == std::string::npos) break;
                start = comma + 1;
            }
        }
    }
    args.interval = std::max(0.4, args.interval);
    return args;
}

int main(int argc, char* argv[]) {
    prctl(PR_SET_PDEATHSIG, SIGTERM);

    struct sigaction sa;
    std::memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);
    std::signal(SIGPIPE, SIG_IGN);

    CommandLineArgs args = parse_cli_args(argc, argv);
    auto nodes = video_capture_nodes();

    if (args.once) {
        std::optional<std::string> last;
        emit(collect(args.kinds, nodes), last);
        return 0;
    }

    return run_loop(args.kinds, std::move(nodes), args.interval);
}
