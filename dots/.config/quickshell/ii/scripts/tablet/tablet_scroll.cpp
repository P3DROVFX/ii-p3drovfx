#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cmath>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <iostream>
#include <poll.h>
#include <string>
#include <string_view>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <chrono>

#include <linux/input.h>
#include <linux/uinput.h>

namespace {

constexpr int HI_RES = 120;
constexpr double REPEAT_DELAY = 0.30;
constexpr double REPEAT_INTERVAL = 0.06;
constexpr double PX_PER_NOTCH = 40.0;
constexpr double SCAN_INTERVAL = 3.0;

const std::string KEYBOARD_NAME = "OpenTabletDriver Virtual Keyboard";
const std::vector<std::string> TABLET_NAMES = {
    "OpenTabletDriver Virtual Artist Tablet",
    "OpenTabletDriver Virtual Tablet"
};

using Clock = std::chrono::steady_clock;
using TimePoint = Clock::time_point;

volatile std::sig_atomic_t g_running = 1;

void signal_handler(int sig) {
    (void)sig;
    g_running = 0;
}

void die_with_parent() {
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() == 1) {
        std::exit(0);
    }
}

// ---------------------------------------------------------------------------
// Minimal JSON Parser for configuration objects
// ---------------------------------------------------------------------------

enum class JsonType { Null, Bool, Number, String, Array, Object };

struct JsonValue {
    JsonType type = JsonType::Null;
    bool bool_val = false;
    double num_val = 0.0;
    std::string str_val;
    std::vector<JsonValue> arr_val;
    std::unordered_map<std::string, JsonValue> obj_val;
};

class JsonParser {
public:
    explicit JsonParser(std::string_view input) : s_(input) {}

    bool parse(JsonValue& out) {
        skip_whitespace();
        if (!parse_value(out)) return false;
        skip_whitespace();
        return pos_ == s_.size();
    }

private:
    std::string_view s_;
    size_t pos_ = 0;

    void skip_whitespace() {
        while (pos_ < s_.size() && (s_[pos_] == ' ' || s_[pos_] == '\t' ||
                                    s_[pos_] == '\r' || s_[pos_] == '\n')) {
            ++pos_;
        }
    }

    bool parse_value(JsonValue& val) {
        skip_whitespace();
        if (pos_ >= s_.size()) return false;
        char c = s_[pos_];
        if (c == 'n') return parse_null(val);
        if (c == 't' || c == 'f') return parse_bool(val);
        if (c == '"') return parse_string(val.str_val) ? (val.type = JsonType::String, true) : false;
        if (c == '[') return parse_array(val);
        if (c == '{') return parse_object(val);
        if (c == '-' || (c >= '0' && c <= '9')) return parse_number(val);
        return false;
    }

    bool parse_null(JsonValue& val) {
        if (s_.substr(pos_, 4) == "null") {
            pos_ += 4;
            val.type = JsonType::Null;
            return true;
        }
        return false;
    }

    bool parse_bool(JsonValue& val) {
        if (s_.substr(pos_, 4) == "true") {
            pos_ += 4;
            val.type = JsonType::Bool;
            val.bool_val = true;
            return true;
        }
        if (s_.substr(pos_, 5) == "false") {
            pos_ += 5;
            val.type = JsonType::Bool;
            val.bool_val = false;
            return true;
        }
        return false;
    }

    bool parse_string(std::string& str) {
        if (pos_ >= s_.size() || s_[pos_] != '"') return false;
        ++pos_;
        str.clear();
        while (pos_ < s_.size()) {
            char c = s_[pos_++];
            if (c == '"') return true;
            if (c == '\\') {
                if (pos_ >= s_.size()) return false;
                char esc = s_[pos_++];
                switch (esc) {
                    case '"': str += '"'; break;
                    case '\\': str += '\\'; break;
                    case '/': str += '/'; break;
                    case 'b': str += '\b'; break;
                    case 'f': str += '\f'; break;
                    case 'n': str += '\n'; break;
                    case 'r': str += '\r'; break;
                    case 't': str += '\t'; break;
                    case 'u': {
                        if (pos_ + 4 > s_.size()) return false;
                        pos_ += 4;
                        str += '?';
                        break;
                    }
                    default: str += esc; break;
                }
            } else {
                str += c;
            }
        }
        return false;
    }

    bool parse_number(JsonValue& val) {
        size_t start = pos_;
        if (s_[pos_] == '-') ++pos_;
        while (pos_ < s_.size() && (s_[pos_] >= '0' && s_[pos_] <= '9')) ++pos_;
        if (pos_ < s_.size() && s_[pos_] == '.') {
            ++pos_;
            while (pos_ < s_.size() && (s_[pos_] >= '0' && s_[pos_] <= '9')) ++pos_;
        }
        if (pos_ < s_.size() && (s_[pos_] == 'e' || s_[pos_] == 'E')) {
            ++pos_;
            if (pos_ < s_.size() && (s_[pos_] == '+' || s_[pos_] == '-')) ++pos_;
            while (pos_ < s_.size() && (s_[pos_] >= '0' && s_[pos_] <= '9')) ++pos_;
        }
        std::string num_str(s_.substr(start, pos_ - start));
        char* end = nullptr;
        val.num_val = std::strtod(num_str.c_str(), &end);
        val.type = JsonType::Number;
        return end == num_str.c_str() + num_str.size();
    }

    bool parse_array(JsonValue& val) {
        if (pos_ >= s_.size() || s_[pos_] != '[') return false;
        ++pos_;
        val.type = JsonType::Array;
        val.arr_val.clear();
        skip_whitespace();
        if (pos_ < s_.size() && s_[pos_] == ']') {
            ++pos_;
            return true;
        }
        while (pos_ < s_.size()) {
            JsonValue elem;
            if (!parse_value(elem)) return false;
            val.arr_val.push_back(std::move(elem));
            skip_whitespace();
            if (pos_ >= s_.size()) return false;
            if (s_[pos_] == ']') {
                ++pos_;
                return true;
            }
            if (s_[pos_] == ',') {
                ++pos_;
                continue;
            }
            return false;
        }
        return false;
    }

    bool parse_object(JsonValue& val) {
        if (pos_ >= s_.size() || s_[pos_] != '{') return false;
        ++pos_;
        val.type = JsonType::Object;
        val.obj_val.clear();
        skip_whitespace();
        if (pos_ < s_.size() && s_[pos_] == '}') {
            ++pos_;
            return true;
        }
        while (pos_ < s_.size()) {
            skip_whitespace();
            std::string key;
            if (!parse_string(key)) return false;
            skip_whitespace();
            if (pos_ >= s_.size() || s_[pos_] != ':') return false;
            ++pos_;
            JsonValue child;
            if (!parse_value(child)) return false;
            val.obj_val[key] = std::move(child);
            skip_whitespace();
            if (pos_ >= s_.size()) return false;
            if (s_[pos_] == '}') {
                ++pos_;
                return true;
            }
            if (s_[pos_] == ',') {
                ++pos_;
                continue;
            }
            return false;
        }
        return false;
    }
};

struct Config {
    std::unordered_map<int, std::pair<int, int>> fixed;
    std::unordered_set<int> drag;
    int step = 1;
    double speed = 1.0;
    bool invert = false;
};

bool parse_and_apply_config(const std::string& line, Config& cfg) {
    JsonParser parser(line);
    JsonValue root;
    if (!parser.parse(root) || root.type != JsonType::Object) {
        return false;
    }

    if (auto it = root.obj_val.find("fixed"); it != root.obj_val.end() && it->second.type == JsonType::Object) {
        cfg.fixed.clear();
        for (const auto& [k, v] : it->second.obj_val) {
            char* end = nullptr;
            long code = std::strtol(k.c_str(), &end, 10);
            if (end != k.c_str() && *end == '\0') {
                if (v.type == JsonType::Array && v.arr_val.size() >= 2) {
                    if (v.arr_val[0].type == JsonType::Number && v.arr_val[1].type == JsonType::Number) {
                        int dx = static_cast<int>(v.arr_val[0].num_val);
                        int dy = static_cast<int>(v.arr_val[1].num_val);
                        cfg.fixed[static_cast<int>(code)] = {dx, dy};
                    }
                }
            }
        }
    }

    if (auto it = root.obj_val.find("drag"); it != root.obj_val.end() && it->second.type == JsonType::Array) {
        cfg.drag.clear();
        for (const auto& elem : it->second.arr_val) {
            if (elem.type == JsonType::Number) {
                cfg.drag.insert(static_cast<int>(elem.num_val));
            }
        }
    }

    if (auto it = root.obj_val.find("step"); it != root.obj_val.end() && it->second.type == JsonType::Number) {
        cfg.step = std::max(1, static_cast<int>(it->second.num_val));
    }

    if (auto it = root.obj_val.find("speed"); it != root.obj_val.end() && it->second.type == JsonType::Number) {
        cfg.speed = std::max(0.05, it->second.num_val);
    }

    if (auto it = root.obj_val.find("invert"); it != root.obj_val.end() && it->second.type == JsonType::Bool) {
        cfg.invert = it->second.bool_val;
    }

    return true;
}

// ---------------------------------------------------------------------------
// Virtual UInput Mouse Wheel Device
// ---------------------------------------------------------------------------

class Wheel {
public:
    Wheel() {
        fd_ = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd_ < 0) {
            std::perror("Failed to open /dev/uinput");
            std::exit(1);
        }

        if (ioctl(fd_, UI_SET_EVBIT, EV_REL) < 0 ||
            ioctl(fd_, UI_SET_EVBIT, EV_SYN) < 0 ||
            ioctl(fd_, UI_SET_RELBIT, REL_WHEEL) < 0 ||
            ioctl(fd_, UI_SET_RELBIT, REL_HWHEEL) < 0 ||
            ioctl(fd_, UI_SET_RELBIT, REL_WHEEL_HI_RES) < 0 ||
            ioctl(fd_, UI_SET_RELBIT, REL_HWHEEL_HI_RES) < 0) {
            std::perror("Failed to set uinput bits");
            cleanup();
            std::exit(1);
        }

        struct uinput_setup usetup;
        std::memset(&usetup, 0, sizeof(usetup));
        usetup.id.bustype = BUS_USB;
        usetup.id.vendor = 0x1209;
        usetup.id.product = 0x4949;
        usetup.id.version = 1;
        std::strncpy(usetup.name, "ii tablet scroll", UINPUT_MAX_NAME_SIZE - 1);

        if (ioctl(fd_, UI_DEV_SETUP, &usetup) < 0) {
            std::perror("UI_DEV_SETUP failed");
            cleanup();
            std::exit(1);
        }

        if (ioctl(fd_, UI_DEV_CREATE) < 0) {
            std::perror("UI_DEV_CREATE failed");
            cleanup();
            std::exit(1);
        }
    }

    ~Wheel() {
        cleanup();
    }

    Wheel(const Wheel&) = delete;
    Wheel& operator=(const Wheel&) = delete;

    void cleanup() {
        if (fd_ >= 0) {
            ioctl(fd_, UI_DEV_DESTROY);
            close(fd_);
            fd_ = -1;
        }
    }

    void emit_raw(uint16_t type, uint16_t code, int32_t value) {
        if (fd_ < 0) return;
        struct input_event ev;
        std::memset(&ev, 0, sizeof(ev));
        ev.type = type;
        ev.code = code;
        ev.value = value;
        ssize_t ret = write(fd_, &ev, sizeof(ev));
        (void)ret;
    }

    void syn() {
        emit_raw(EV_SYN, SYN_REPORT, 0);
    }

    void hires(double dx, double dy) {
        int idx = static_cast<int>(std::round(dx));
        int idy = static_cast<int>(std::round(dy));
        if (idx == 0 && idy == 0) {
            return;
        }

        if (idy != 0) {
            emit_raw(EV_REL, REL_WHEEL_HI_RES, idy);
        }
        if (idx != 0) {
            emit_raw(EV_REL, REL_HWHEEL_HI_RES, idx);
        }

        rem_x_ += idx;
        int notches_x = static_cast<int>(rem_x_ / HI_RES);
        if (notches_x != 0) {
            rem_x_ -= notches_x * HI_RES;
            emit_raw(EV_REL, REL_HWHEEL, notches_x);
        }

        rem_y_ += idy;
        int notches_y = static_cast<int>(rem_y_ / HI_RES);
        if (notches_y != 0) {
            rem_y_ -= notches_y * HI_RES;
            emit_raw(EV_REL, REL_WHEEL, notches_y);
        }

        syn();
    }

    void step(int dx, int dy) {
        hires(static_cast<double>(dx) * HI_RES, static_cast<double>(dy) * HI_RES);
    }

private:
    int fd_ = -1;
    double rem_x_ = 0.0;
    double rem_y_ = 0.0;
};

// ---------------------------------------------------------------------------
// Device Scanner
// ---------------------------------------------------------------------------

int find_device(const std::vector<std::string>& target_names) {
    DIR* dir = opendir("/dev/input");
    if (!dir) return -1;

    std::vector<int> event_ids;
    struct dirent* entry = nullptr;
    while ((entry = readdir(dir)) != nullptr) {
        if (std::strncmp(entry->d_name, "event", 5) == 0) {
            char* end = nullptr;
            long val = std::strtol(entry->d_name + 5, &end, 10);
            if (end != entry->d_name + 5 && *end == '\0' && val >= 0) {
                event_ids.push_back(static_cast<int>(val));
            }
        }
    }
    closedir(dir);

    std::sort(event_ids.begin(), event_ids.end());

    for (int id : event_ids) {
        std::string path = "/dev/input/event" + std::to_string(id);
        int fd = open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;

        char name[256];
        std::memset(name, 0, sizeof(name));
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0) {
            for (const auto& target : target_names) {
                if (target == name) {
                    return fd;
                }
            }
        }
        close(fd);
    }
    return -1;
}

// ---------------------------------------------------------------------------
// Drag Handling
// ---------------------------------------------------------------------------

class Drag {
public:
    Drag() = default;
    ~Drag() {
        stop();
    }

    Drag(const Drag&) = delete;
    Drag& operator=(const Drag&) = delete;

    bool is_open() const { return fd_ >= 0; }
    int fd() const { return fd_; }

    void start() {
        if (fd_ >= 0) return;
        int found_fd = find_device(TABLET_NAMES);
        if (found_fd < 0) return;

        if (ioctl(found_fd, EVIOCGRAB, 1) < 0) {
            close(found_fd);
            return;
        }

        fd_ = found_fd;
        has_last_x_ = false;
        has_last_y_ = false;

        struct input_absinfo abs_x;
        std::memset(&abs_x, 0, sizeof(abs_x));
        if (ioctl(fd_, EVIOCGABS(ABS_X), &abs_x) >= 0) {
            int span = abs_x.maximum - abs_x.minimum;
            scale_x_ = (span > 100000) ? (1.0 / 1000.0) : ((span > 0) ? (1080.0 / span) : (1.0 / 100.0));
        } else {
            scale_x_ = 1.0 / 1000.0;
        }

        struct input_absinfo abs_y;
        std::memset(&abs_y, 0, sizeof(abs_y));
        if (ioctl(fd_, EVIOCGABS(ABS_Y), &abs_y) >= 0) {
            int span = abs_y.maximum - abs_y.minimum;
            scale_y_ = (span > 100000) ? (1.0 / 1000.0) : ((span > 0) ? (1080.0 / span) : (1.0 / 100.0));
        } else {
            scale_y_ = 1.0 / 1000.0;
        }
    }

    void stop() {
        if (fd_ >= 0) {
            ioctl(fd_, EVIOCGRAB, 0);
            close(fd_);
            fd_ = -1;
            has_last_x_ = false;
            has_last_y_ = false;
        }
    }

    bool read_events(Wheel& wheel, double speed, bool invert) {
        if (fd_ < 0) return true;

        struct input_event evs[64];
        double moved_x = 0.0;
        double moved_y = 0.0;

        while (true) {
            ssize_t n = read(fd_, evs, sizeof(evs));
            if (n < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    break;
                }
                return false;
            }
            if (n == 0) {
                return false;
            }

            size_t count = n / sizeof(struct input_event);
            for (size_t i = 0; i < count; ++i) {
                const auto& ev = evs[i];
                if (ev.type == EV_ABS) {
                    if (ev.code == ABS_X) {
                        if (has_last_x_) {
                            moved_x += (ev.value - last_x_) * scale_x_;
                        }
                        last_x_ = ev.value;
                        has_last_x_ = true;
                    } else if (ev.code == ABS_Y) {
                        if (has_last_y_) {
                            moved_y += (ev.value - last_y_) * scale_y_;
                        }
                        last_y_ = ev.value;
                        has_last_y_ = true;
                    }
                } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
                    if (moved_x != 0.0 || moved_y != 0.0) {
                        double sign = invert ? -1.0 : 1.0;
                        double factor = (HI_RES / PX_PER_NOTCH) * speed * sign;
                        wheel.hires(moved_x * -factor, moved_y * factor);
                        moved_x = 0.0;
                        moved_y = 0.0;
                    }
                }
            }
        }

        if (moved_x != 0.0 || moved_y != 0.0) {
            double sign = invert ? -1.0 : 1.0;
            double factor = (HI_RES / PX_PER_NOTCH) * speed * sign;
            wheel.hires(moved_x * -factor, moved_y * factor);
        }

        return true;
    }

private:
    int fd_ = -1;
    bool has_last_x_ = false;
    bool has_last_y_ = false;
    int32_t last_x_ = 0;
    int32_t last_y_ = 0;
    double scale_x_ = 1.0 / 1000.0;
    double scale_y_ = 1.0 / 1000.0;
};

} // namespace

int main() {
    die_with_parent();

    struct sigaction sa;
    std::memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);

    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    if (flags >= 0) {
        fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    }

    Wheel wheel;
    Drag drag;
    int keyboard_fd = -1;

    Config config;
    std::unordered_map<int, TimePoint> held_fixed;
    std::unordered_set<int> held_drag;

    TimePoint next_scan = Clock::time_point{};
    std::string stdin_buffer;

    while (g_running) {
        auto now = Clock::now();
        if (keyboard_fd < 0 && now >= next_scan) {
            keyboard_fd = find_device({KEYBOARD_NAME});
            next_scan = now + std::chrono::duration_cast<Clock::duration>(
                std::chrono::duration<double>(SCAN_INTERVAL));
        }

        int timeout_ms = -1;
        if (keyboard_fd < 0) {
            double to_scan = std::chrono::duration<double>(next_scan - now).count();
            timeout_ms = (to_scan <= 0.0) ? 0 : static_cast<int>(std::ceil(to_scan * 1000.0));
        }

        if (!held_fixed.empty()) {
            TimePoint earliest = held_fixed.begin()->second;
            for (const auto& [code, due] : held_fixed) {
                if (due < earliest) earliest = due;
            }
            double to_due = std::chrono::duration<double>(earliest - now).count();
            int held_ms = (to_due <= 0.0) ? 0 : static_cast<int>(std::ceil(to_due * 1000.0));
            if (timeout_ms < 0 || held_ms < timeout_ms) {
                timeout_ms = held_ms;
            }
        }

        struct pollfd pfds[3];
        nfds_t nfds = 0;

        pfds[nfds].fd = STDIN_FILENO;
        pfds[nfds].events = POLLIN;
        pfds[nfds].revents = 0;
        int stdin_idx = nfds++;

        int kbd_idx = -1;
        if (keyboard_fd >= 0) {
            pfds[nfds].fd = keyboard_fd;
            pfds[nfds].events = POLLIN;
            pfds[nfds].revents = 0;
            kbd_idx = nfds++;
        }

        int drag_idx = -1;
        if (drag.is_open()) {
            pfds[nfds].fd = drag.fd();
            pfds[nfds].events = POLLIN;
            pfds[nfds].revents = 0;
            drag_idx = nfds++;
        }

        int poll_ret = poll(pfds, nfds, timeout_ms);
        if (poll_ret < 0) {
            if (errno == EINTR) {
                if (!g_running) break;
                continue;
            }
            std::perror("poll failed");
            break;
        }

        if (!g_running) break;

        // Process stdin
        if (stdin_idx >= 0 && (pfds[stdin_idx].revents & (POLLIN | POLLHUP | POLLERR))) {
            char buf[4096];
            bool eof_reached = false;
            while (true) {
                ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
                if (n < 0) {
                    if (errno == EAGAIN || errno == EWOULDBLOCK) {
                        break;
                    }
                    eof_reached = true;
                    break;
                }
                if (n == 0) {
                    eof_reached = true;
                    break;
                }
                stdin_buffer.append(buf, n);
            }

            size_t newline_pos;
            while ((newline_pos = stdin_buffer.find('\n')) != std::string::npos) {
                std::string line = stdin_buffer.substr(0, newline_pos);
                stdin_buffer.erase(0, newline_pos + 1);

                size_t start = 0;
                while (start < line.size() && (line[start] == ' ' || line[start] == '\t' || line[start] == '\r')) {
                    ++start;
                }
                size_t end = line.size();
                while (end > start && (line[end - 1] == ' ' || line[end - 1] == '\t' || line[end - 1] == '\r')) {
                    --end;
                }
                if (end > start) {
                    std::string trimmed = line.substr(start, end - start);
                    if (parse_and_apply_config(trimmed, config)) {
                        for (auto it = held_drag.begin(); it != held_drag.end(); ) {
                            if (config.drag.find(*it) == config.drag.end()) {
                                it = held_drag.erase(it);
                            } else {
                                ++it;
                            }
                        }
                        if (held_drag.empty() && drag.is_open()) {
                            drag.stop();
                        }

                        for (auto it = held_fixed.begin(); it != held_fixed.end(); ) {
                            if (config.fixed.find(it->first) == config.fixed.end()) {
                                it = held_fixed.erase(it);
                            } else {
                                ++it;
                            }
                        }
                    } else {
                        std::cerr << "bad config: " << trimmed << "\n";
                    }
                }
            }

            if (eof_reached) {
                break;
            }
        }

        // Process keyboard
        if (kbd_idx >= 0 && (pfds[kbd_idx].revents & (POLLIN | POLLHUP | POLLERR))) {
            struct input_event k_evs[64];
            bool kbd_error = false;
            while (true) {
                ssize_t n = read(keyboard_fd, k_evs, sizeof(k_evs));
                if (n < 0) {
                    if (errno == EAGAIN || errno == EWOULDBLOCK) {
                        break;
                    }
                    kbd_error = true;
                    break;
                }
                if (n == 0) {
                    kbd_error = true;
                    break;
                }

                size_t count = n / sizeof(struct input_event);
                for (size_t i = 0; i < count; ++i) {
                    const auto& ev = k_evs[i];
                    if (ev.type != EV_KEY || ev.value == 2) {
                        continue;
                    }

                    int code = ev.code;
                    auto fixed_it = config.fixed.find(code);
                    if (fixed_it != config.fixed.end()) {
                        if (ev.value == 1) {
                            auto [dx, dy] = fixed_it->second;
                            wheel.step(dx * config.step, dy * config.step);
                            held_fixed[code] = Clock::now() + std::chrono::duration_cast<Clock::duration>(
                                std::chrono::duration<double>(REPEAT_DELAY));
                        } else if (ev.value == 0) {
                            held_fixed.erase(code);
                        }
                    } else if (config.drag.find(code) != config.drag.end()) {
                        if (ev.value == 1) {
                            held_drag.insert(code);
                            drag.start();
                        } else if (ev.value == 0) {
                            held_drag.erase(code);
                            if (held_drag.empty()) {
                                drag.stop();
                            }
                        }
                    }
                }
            }

            if (kbd_error) {
                close(keyboard_fd);
                keyboard_fd = -1;
                held_fixed.clear();
                held_drag.clear();
                drag.stop();
                next_scan = Clock::now() + std::chrono::duration_cast<Clock::duration>(
                    std::chrono::duration<double>(SCAN_INTERVAL));
            }
        }

        // Process drag
        if (drag_idx >= 0 && (pfds[drag_idx].revents & (POLLIN | POLLHUP | POLLERR))) {
            if (!drag.read_events(wheel, config.speed, config.invert)) {
                drag.stop();
                held_drag.clear();
            }
        }

        // Process held fixed key repeats
        now = Clock::now();
        for (auto& [code, due] : held_fixed) {
            if (now >= due) {
                auto fixed_it = config.fixed.find(code);
                if (fixed_it != config.fixed.end()) {
                    auto [dx, dy] = fixed_it->second;
                    wheel.step(dx * config.step, dy * config.step);
                    due = now + std::chrono::duration_cast<Clock::duration>(
                        std::chrono::duration<double>(REPEAT_INTERVAL));
                }
            }
        }
    }

    drag.stop();
    if (keyboard_fd >= 0) {
        close(keyboard_fd);
        keyboard_fd = -1;
    }
    wheel.cleanup();

    return 0;
}
