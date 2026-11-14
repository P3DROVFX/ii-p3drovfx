#include <sys/inotify.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <poll.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <clocale>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <csignal>

namespace fs = std::filesystem;

namespace {

volatile std::sig_atomic_t g_running = 1;

void sig_handler(int) {
    g_running = 0;
}

// ─── String Helpers ──────────────────────────────────────────

std::string trim(std::string_view s) {
    size_t start = 0;
    while (start < s.size() && static_cast<unsigned char>(s[start]) <= ' ') start++;
    size_t end = s.size();
    while (end > start && static_cast<unsigned char>(s[end - 1]) <= ' ') end--;
    return std::string(s.substr(start, end - start));
}

std::string to_upper(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        out += static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    }
    return out;
}

std::string to_lower_ascii(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        out += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return out;
}

std::string utf8_tolower(const std::string &str) {
    std::string result;
    result.reserve(str.size());
    size_t i = 0;
    while (i < str.size()) {
        unsigned char c = static_cast<unsigned char>(str[i]);
        if (c < 0x80) {
            result += static_cast<char>(std::tolower(c));
            i++;
        } else {
            uint32_t cp = 0;
            size_t bytes = 0;
            if ((c & 0xE0) == 0xC0) {
                cp = c & 0x1F; bytes = 2;
            } else if ((c & 0xF0) == 0xE0) {
                cp = c & 0x0F; bytes = 3;
            } else if ((c & 0xF8) == 0xF0) {
                cp = c & 0x07; bytes = 4;
            } else {
                result += str[i++];
                continue;
            }
            if (i + bytes > str.size()) {
                result += str[i++];
                continue;
            }
            bool ok = true;
            for (size_t b = 1; b < bytes; ++b) {
                unsigned char cb = static_cast<unsigned char>(str[i + b]);
                if ((cb & 0xC0) != 0x80) { ok = false; break; }
                cp = (cp << 6) | (cb & 0x3F);
            }
            if (!ok) {
                result += str[i++];
                continue;
            }
            i += bytes;
            wint_t lcp = std::towlower(static_cast<wint_t>(cp));
            if (lcp < 0x80) {
                result += static_cast<char>(lcp);
            } else if (lcp < 0x800) {
                result += static_cast<char>(0xC0 | (lcp >> 6));
                result += static_cast<char>(0x80 | (lcp & 0x3F));
            } else if (lcp < 0x10000) {
                result += static_cast<char>(0xE0 | (lcp >> 12));
                result += static_cast<char>(0x80 | ((lcp >> 6) & 0x3F));
                result += static_cast<char>(0x80 | (lcp & 0x3F));
            } else {
                result += static_cast<char>(0xF0 | (lcp >> 18));
                result += static_cast<char>(0x80 | ((lcp >> 12) & 0x3F));
                result += static_cast<char>(0x80 | ((lcp >> 6) & 0x3F));
                result += static_cast<char>(0x80 | (lcp & 0x3F));
            }
        }
    }
    return result;
}

// ─── JSON Helpers ────────────────────────────────────────────

std::string json_escape(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
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

// ─── SHA-256 (FIPS 180-4) ────────────────────────────────────

struct SHA256 {
    uint32_t state[8];
    uint64_t count;
    uint8_t buffer[64];

    static constexpr uint32_t K[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    };

    static uint32_t rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }
    static uint32_t choose(uint32_t e, uint32_t f, uint32_t g) { return (e & f) ^ (~e & g); }
    static uint32_t majority(uint32_t a, uint32_t b, uint32_t c) { return (a & b) ^ (a & c) ^ (b & c); }
    static uint32_t sig0(uint32_t x) { return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22); }
    static uint32_t sig1(uint32_t x) { return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25); }
    static uint32_t theta0(uint32_t x) { return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3); }
    static uint32_t theta1(uint32_t x) { return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10); }

    void init() {
        state[0] = 0x6a09e667;
        state[1] = 0xbb67ae85;
        state[2] = 0x3c6ef372;
        state[3] = 0xa54ff53a;
        state[4] = 0x510e527f;
        state[5] = 0x9b05688c;
        state[6] = 0x1f83d9ab;
        state[7] = 0x5be0cd19;
        count = 0;
    }

    void transform(const uint8_t block[64]) {
        uint32_t W[64];
        for (int i = 0; i < 16; ++i) {
            W[i] = (static_cast<uint32_t>(block[i * 4]) << 24) |
                   (static_cast<uint32_t>(block[i * 4 + 1]) << 16) |
                   (static_cast<uint32_t>(block[i * 4 + 2]) << 8) |
                   (static_cast<uint32_t>(block[i * 4 + 3]));
        }
        for (int i = 16; i < 64; ++i) {
            W[i] = theta1(W[i - 2]) + W[i - 7] + theta0(W[i - 15]) + W[i - 16];
        }

        uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
        uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

        for (int i = 0; i < 64; ++i) {
            uint32_t T1 = h + sig1(e) + choose(e, f, g) + K[i] + W[i];
            uint32_t T2 = sig0(a) + majority(a, b, c);
            h = g;
            g = f;
            f = e;
            e = d + T1;
            d = c;
            c = b;
            b = a;
            a = T1 + T2;
        }

        state[0] += a;
        state[1] += b;
        state[2] += c;
        state[3] += d;
        state[4] += e;
        state[5] += f;
        state[6] += g;
        state[7] += h;
    }

    void update(const uint8_t *data, size_t len) {
        size_t idx = count % 64;
        count += len;
        size_t part_len = 64 - idx;
        size_t i = 0;

        if (len >= part_len) {
            std::memcpy(&buffer[idx], data, part_len);
            transform(buffer);
            for (i = part_len; i + 63 < len; i += 64) {
                transform(&data[i]);
            }
            idx = 0;
        }
        std::memcpy(&buffer[idx], &data[i], len - i);
    }

    void finalize(uint8_t digest[32]) {
        uint8_t final_count[8];
        uint64_t bit_count = count * 8;
        for (int i = 0; i < 8; ++i) {
            final_count[i] = static_cast<uint8_t>((bit_count >> ((7 - i) * 8)) & 0xff);
        }

        size_t idx = count % 64;
        size_t pad_len = (idx < 56) ? (56 - idx) : (120 - idx);
        static const uint8_t PADDING[64] = { 0x80 };
        update(PADDING, pad_len);
        update(final_count, 8);

        for (int i = 0; i < 8; ++i) {
            digest[i * 4]     = static_cast<uint8_t>((state[i] >> 24) & 0xff);
            digest[i * 4 + 1] = static_cast<uint8_t>((state[i] >> 16) & 0xff);
            digest[i * 4 + 2] = static_cast<uint8_t>((state[i] >> 8) & 0xff);
            digest[i * 4 + 3] = static_cast<uint8_t>(state[i] & 0xff);
        }
    }

    static std::string hash_hex(const uint8_t *data, size_t len) {
        SHA256 ctx;
        ctx.init();
        ctx.update(data, len);
        uint8_t digest[32];
        ctx.finalize(digest);
        char hex[65];
        for (int i = 0; i < 32; ++i) {
            std::snprintf(&hex[i * 2], 3, "%02x", digest[i]);
        }
        return std::string(hex, 64);
    }

    static std::string hash_hex(std::string_view s) {
        return hash_hex(reinterpret_cast<const uint8_t*>(s.data()), s.size());
    }
};

// ─── Base64 Decoder ──────────────────────────────────────────

std::vector<uint8_t> base64_decode(std::string_view input) {
    std::vector<uint8_t> out;
    out.reserve((input.size() * 3) / 4);
    int val = 0, valb = -8;
    for (char c : input) {
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') continue;
        if (c == '=') break;
        int d = -1;
        if (c >= 'A' && c <= 'Z') d = c - 'A';
        else if (c >= 'a' && c <= 'z') d = c - 'a' + 26;
        else if (c >= '0' && c <= '9') d = c - '0' + 52;
        else if (c == '+') d = 62;
        else if (c == '/') d = 63;
        else continue;

        val = (val << 6) | d;
        valb += 6;
        if (valb >= 0) {
            out.push_back(static_cast<uint8_t>((val >> valb) & 0xFF));
            valb -= 8;
        }
    }
    return out;
}

// ─── Quoted-Printable Decoder ────────────────────────────────

static int hex_val(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

std::string decode_quoted_printable(std::string_view text) {
    std::string raw_bytes;
    raw_bytes.reserve(text.size());
    size_t i = 0;
    while (i < text.size()) {
        if (text[i] == '=') {
            if (i + 2 < text.size() && text[i + 1] == '\r' && text[i + 2] == '\n') {
                i += 3;
            } else if (i + 1 < text.size() && (text[i + 1] == '\r' || text[i + 1] == '\n')) {
                i += 2;
            } else if (i + 2 < text.size() && isxdigit(static_cast<unsigned char>(text[i + 1])) && isxdigit(static_cast<unsigned char>(text[i + 2]))) {
                int h1 = hex_val(text[i + 1]);
                int h2 = hex_val(text[i + 2]);
                raw_bytes.push_back(static_cast<char>((h1 << 4) | h2));
                i += 3;
            } else if (i + 1 == text.size()) {
                i++; // trailing '=' stripped
            } else {
                raw_bytes.push_back(text[i++]);
            }
        } else {
            raw_bytes.push_back(text[i++]);
        }
    }

    // Decode as UTF-8 with errors='replace' (U+FFFD \xEF\xBF\xBD)
    std::string out;
    out.reserve(raw_bytes.size());
    size_t j = 0;
    while (j < raw_bytes.size()) {
        unsigned char c = static_cast<unsigned char>(raw_bytes[j]);
        if (c < 0x80) {
            out.push_back(static_cast<char>(c));
            j++;
        } else {
            size_t bytes = 0;
            uint32_t cp = 0;
            if ((c & 0xE0) == 0xC0) {
                bytes = 2; cp = c & 0x1F;
            } else if ((c & 0xF0) == 0xE0) {
                bytes = 3; cp = c & 0x0F;
            } else if ((c & 0xF8) == 0xF0) {
                bytes = 4; cp = c & 0x07;
            } else {
                out += "\xEF\xBF\xBD";
                j++;
                continue;
            }
            if (j + bytes > raw_bytes.size()) {
                out += "\xEF\xBF\xBD";
                break;
            }
            bool ok = true;
            for (size_t b = 1; b < bytes; ++b) {
                unsigned char cb = static_cast<unsigned char>(raw_bytes[j + b]);
                if ((cb & 0xC0) != 0x80) { ok = false; break; }
                cp = (cp << 6) | (cb & 0x3F);
            }
            if (bytes == 2 && cp < 0x80) ok = false;
            if (bytes == 3 && (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF))) ok = false;
            if (bytes == 4 && (cp < 0x10000 || cp > 0x10FFFF)) ok = false;

            if (ok) {
                out.append(&raw_bytes[j], bytes);
                j += bytes;
            } else {
                out += "\xEF\xBF\xBD";
                j++;
            }
        }
    }
    return out;
}

// ─── Data Structures ─────────────────────────────────────────

struct Phone {
    std::string value;
    std::string normalized;
    std::string type;
    bool primary;
};

struct Email {
    std::string value;
    std::string type;
    bool primary;
};

struct Birthday {
    std::optional<int> year;
    int month;
    int day;
};

struct Contact {
    std::string id;
    std::string display_name;
    std::string given_name;
    std::string family_name;
    std::string organization;
    std::vector<Phone> phones;
    std::vector<Email> emails;
    std::string avatar_path;
    std::optional<Birthday> birthday;
    std::string source;
    bool nameless;
    int64_t mtime;
};

// ─── Path & Cache Helpers ────────────────────────────────────

fs::path get_cache_dir() {
    const char *home = std::getenv("HOME");
    return fs::path(home ? home : "") / ".cache" / "illogical-impulse" / "phone" / "contacts";
}

fs::path get_kpeoplevcard_root() {
    const char *xdg = std::getenv("XDG_DATA_HOME");
    if (xdg && *xdg != '\0') {
        return fs::path(xdg) / "kpeoplevcard";
    }
    const char *home = std::getenv("HOME");
    return fs::path(home ? home : "") / ".local" / "share" / "kpeoplevcard";
}

bool has_vcf_files(const fs::path &dir_path) {
    std::error_code ec;
    for (const auto &entry : fs::directory_iterator(dir_path, ec)) {
        if (entry.is_regular_file(ec) && entry.path().extension() == ".vcf") {
            return true;
        }
    }
    return false;
}

fs::path pick_most_recent_dir(const std::vector<fs::path> &dirs) {
    std::vector<std::pair<int64_t, fs::path>> dirs_with_mtime;
    dirs_with_mtime.reserve(dirs.size());
    for (const auto &p : dirs) {
        struct stat st;
        int64_t mt = 0;
        if (stat(p.c_str(), &st) == 0) {
            mt = st.st_mtime;
        }
        dirs_with_mtime.emplace_back(mt, p);
    }
    std::stable_sort(dirs_with_mtime.begin(), dirs_with_mtime.end(),
                     [](const auto &a, const auto &b) { return a.first > b.first; });
    return dirs_with_mtime[0].second;
}

fs::path find_device_directory(const std::string &target_device_id) {
    fs::path root = get_kpeoplevcard_root();
    std::error_code ec;
    if (!fs::exists(root, ec) || !fs::is_directory(root, ec)) {
        return {};
    }

    std::vector<fs::path> dirs;
    for (const auto &entry : fs::directory_iterator(root, ec)) {
        if (entry.is_directory(ec)) {
            std::string name = entry.path().filename().string();
            if (name.rfind("kdeconnect-", 0) == 0) {
                dirs.push_back(entry.path());
            }
        }
    }
    if (dirs.empty()) {
        return {};
    }

    fs::path matched_target_dir;
    if (!target_device_id.empty()) {
        std::string target_name = "kdeconnect-" + target_device_id;
        for (const auto &d : dirs) {
            std::string name = d.filename().string();
            if (name == target_name || name.find(target_device_id) != std::string::npos) {
                if (has_vcf_files(d)) {
                    return d;
                }
                if (matched_target_dir.empty()) {
                    matched_target_dir = d;
                }
            }
        }
    }

    // Prefer directories that actually contain .vcf contact files (e.g. when a
    // re-paired device created a new empty kdeconnect-<id> folder before syncing).
    std::vector<fs::path> populated_dirs;
    for (const auto &d : dirs) {
        if (has_vcf_files(d)) {
            populated_dirs.push_back(d);
        }
    }
    if (!populated_dirs.empty()) {
        return pick_most_recent_dir(populated_dirs);
    }

    if (!matched_target_dir.empty()) {
        return matched_target_dir;
    }

    return pick_most_recent_dir(dirs);
}

// ─── vCard Parsing Helpers ───────────────────────────────────

std::string unescape_vcard_val(std::string_view val) {
    std::string out;
    out.reserve(val.size());
    for (size_t i = 0; i < val.size(); ++i) {
        if (val[i] == '\\' && i + 1 < val.size()) {
            char next = val[i + 1];
            if (next == 'n' || next == 'N') { out += '\n'; i++; }
            else if (next == ',') { out += ','; i++; }
            else if (next == ';') { out += ';'; i++; }
            else { out += '\\'; }
        } else {
            out += val[i];
        }
    }
    return trim(out);
}

std::string normalize_phone(std::string_view phone_str) {
    std::string out;
    out.reserve(phone_str.size());
    for (char c : phone_str) {
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n' ||
            c == '-' || c == '(' || c == ')' || c == '.') {
            continue;
        }
        out += c;
    }
    return out;
}

bool looks_like_number(std::string_view text) {
    std::string stripped;
    stripped.reserve(text.size());
    for (char c : text) {
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n' ||
            c == '-' || c == '(' || c == ')' || c == '.' || c == '/') {
            continue;
        }
        stripped += c;
    }
    if (stripped.empty()) return false;
    size_t start = 0;
    if (stripped[0] == '+') start = 1;
    if (start >= stripped.size()) return false;
    for (size_t i = start; i < stripped.size(); ++i) {
        if (!std::isdigit(static_cast<unsigned char>(stripped[i]))) return false;
    }
    return true;
}

std::optional<Birthday> parse_birthday(std::string_view val) {
    std::string raw = unescape_vcard_val(val);
    if (raw.empty()) return std::nullopt;

    // Match: ^(?:(\d{4})-|-+)?(\d{2})-(\d{2})(?:T.*)?$
    size_t pos = 0;
    std::optional<int> year;

    auto is_dig = [](char c) { return std::isdigit(static_cast<unsigned char>(c)) != 0; };

    if (raw[pos] == '-') {
        while (pos < raw.size() && raw[pos] == '-') pos++;
    } else if (pos + 4 < raw.size() &&
               is_dig(raw[pos]) && is_dig(raw[pos + 1]) &&
               is_dig(raw[pos + 2]) && is_dig(raw[pos + 3]) &&
               raw[pos + 4] == '-') {
        year = (raw[pos] - '0') * 1000 + (raw[pos + 1] - '0') * 100 +
               (raw[pos + 2] - '0') * 10 + (raw[pos + 3] - '0');
        pos += 5;
    }

    if (pos + 5 > raw.size() ||
        !is_dig(raw[pos]) || !is_dig(raw[pos + 1]) ||
        raw[pos + 2] != '-' ||
        !is_dig(raw[pos + 3]) || !is_dig(raw[pos + 4])) {
        return std::nullopt;
    }

    int month = (raw[pos] - '0') * 10 + (raw[pos + 1] - '0');
    int day = (raw[pos + 3] - '0') * 10 + (raw[pos + 4] - '0');
    pos += 5;

    if (pos < raw.size() && raw[pos] != 'T') {
        return std::nullopt;
    }

    int y = year.has_value() ? year.value() : 2000;
    if (y < 1 || y > 9999 || month < 1 || month > 12 || day < 1) {
        return std::nullopt;
    }
    bool is_leap = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
    int max_days = 31;
    if (month == 2) {
        max_days = is_leap ? 29 : 28;
    } else if (month == 4 || month == 6 || month == 9 || month == 11) {
        max_days = 30;
    }
    if (day > max_days) {
        return std::nullopt;
    }
    return Birthday{year, month, day};
}

// ─── Parse vCard File ────────────────────────────────────────

std::optional<Contact> parse_vcard_file(const fs::path &file_path, const std::string &source_id) {
    std::ifstream ifs(file_path, std::ios::binary);
    if (!ifs.is_open()) return std::nullopt;

    std::string raw_bytes((std::istreambuf_iterator<char>(ifs)),
                          std::istreambuf_iterator<char>());
    ifs.close();

    // Split lines
    std::vector<std::string> raw_lines;
    size_t pos = 0;
    while (pos < raw_bytes.size()) {
        size_t next = raw_bytes.find('\n', pos);
        std::string line;
        if (next == std::string::npos) {
            line = raw_bytes.substr(pos);
            pos = raw_bytes.size();
        } else {
            line = raw_bytes.substr(pos, next - pos);
            pos = next + 1;
        }
        if (!line.empty() && line.back() == '\r') line.pop_back();
        raw_lines.push_back(std::move(line));
    }

    // Unfold lines (continuation lines starting with space or tab)
    std::vector<std::string> unfolded_lines;
    for (const auto &line : raw_lines) {
        if (!line.empty() && (line[0] == ' ' || line[0] == '\t') && !unfolded_lines.empty()) {
            size_t first_non_ws = 0;
            while (first_non_ws < line.size() && (line[first_non_ws] == ' ' || line[first_non_ws] == '\t')) {
                first_non_ws++;
            }
            unfolded_lines.back().append(line.data() + first_non_ws, line.size() - first_non_ws);
        } else {
            unfolded_lines.push_back(line);
        }
    }

    std::string fn;
    std::string given_name;
    std::string family_name;
    std::string org;
    std::string uid;
    std::vector<Phone> phones;
    std::vector<Email> emails;
    std::vector<uint8_t> photo_data;
    std::string photo_ext = "jpg";
    std::optional<Birthday> birthday;

    for (const auto &raw_line : unfolded_lines) {
        std::string line = trim(raw_line);
        if (line.empty()) continue;
        size_t colon_pos = line.find(':');
        if (colon_pos == std::string::npos) continue;

        std::string key_params_str = line.substr(0, colon_pos);
        std::string val = line.substr(colon_pos + 1);

        // Split key_params_str by ';'
        std::vector<std::string> key_params;
        size_t kp_start = 0;
        while (kp_start < key_params_str.size()) {
            size_t semi = key_params_str.find(';', kp_start);
            if (semi == std::string::npos) {
                key_params.push_back(to_upper(key_params_str.substr(kp_start)));
                break;
            }
            key_params.push_back(to_upper(key_params_str.substr(kp_start, semi - kp_start)));
            kp_start = semi + 1;
        }
        if (key_params.empty()) continue;

        std::string key = key_params[0];
        std::vector<std::string> params(key_params.begin() + 1, key_params.end());

        std::unordered_map<std::string, std::string> param_dict;
        for (const auto &p : params) {
            size_t eq = p.find('=');
            if (eq != std::string::npos) {
                param_dict[p.substr(0, eq)] = p.substr(eq + 1);
            } else {
                param_dict[p] = "TRUE";
            }
        }

        // Quoted-Printable check
        bool is_qp = (param_dict.count("ENCODING") && param_dict["ENCODING"] == "QUOTED-PRINTABLE") ||
                     param_dict.count("QUOTED-PRINTABLE");
        if (is_qp) {
            val = decode_quoted_printable(val);
        }

        if (key == "FN") {
            fn = unescape_vcard_val(val);
        } else if (key == "N") {
            std::vector<std::string> n_parts;
            size_t np_start = 0;
            while (np_start < val.size()) {
                size_t semi = val.find(';', np_start);
                if (semi == std::string::npos) {
                    n_parts.push_back(unescape_vcard_val(val.substr(np_start)));
                    break;
                }
                n_parts.push_back(unescape_vcard_val(val.substr(np_start, semi - np_start)));
                np_start = semi + 1;
            }
            if (n_parts.size() > 0) family_name = n_parts[0];
            if (n_parts.size() > 1) given_name = n_parts[1];
        } else if (key == "ORG") {
            org = unescape_vcard_val(val);
        } else if (key == "UID") {
            uid = trim(val);
        } else if (key.rfind("X-KDECONNECT-ID-DEV-", 0) == 0) {
            if (uid.empty()) {
                uid = trim(val);
            }
        } else if (key == "BDAY") {
            birthday = parse_birthday(val);
        } else if (key == "TEL") {
            std::string phone_val = unescape_vcard_val(val);
            if (!phone_val.empty()) {
                std::string ptype = "mobile";
                for (const auto &p : params) {
                    if (p == "CELL" || p == "MOBILE") {
                        ptype = "mobile";
                    } else if (p == "HOME" || p == "WORK" || p == "MAIN" || p == "OTHER") {
                        ptype = to_lower_ascii(p);
                    }
                }
                bool is_primary = param_dict.count("PREF") ||
                                  (std::find(params.begin(), params.end(), "PREF") != params.end());
                phones.push_back(Phone{
                    .value = phone_val,
                    .normalized = normalize_phone(phone_val),
                    .type = ptype,
                    .primary = is_primary || phones.empty()
                });
            }
        } else if (key == "EMAIL") {
            std::string email_val = unescape_vcard_val(val);
            if (!email_val.empty()) {
                std::string etype = "personal";
                for (const auto &p : params) {
                    if (p == "WORK" || p == "HOME") {
                        etype = to_lower_ascii(p);
                    }
                }
                bool is_primary = param_dict.count("PREF") ||
                                  (std::find(params.begin(), params.end(), "PREF") != params.end());
                emails.push_back(Email{
                    .value = email_val,
                    .type = etype,
                    .primary = is_primary || emails.empty()
                });
            }
        } else if (key == "PHOTO") {
            bool has_b64 = param_dict.count("BASE64") ||
                           (param_dict.count("ENCODING") && (param_dict["ENCODING"] == "B" || param_dict["ENCODING"] == "BASE64")) ||
                           (std::find(params.begin(), params.end(), "B") != params.end());
            if (has_b64) {
                photo_data = base64_decode(trim(val));
                std::string line_upper = to_upper(line);
                if (line_upper.find("JPEG") != std::string::npos || line_upper.find("JPG") != std::string::npos) {
                    photo_ext = "jpg";
                } else if (line_upper.find("PNG") != std::string::npos) {
                    photo_ext = "png";
                }
            }
        }
    }

    // Deduplicate phones
    std::vector<Phone> unique_phones;
    std::unordered_set<std::string> seen_phone_vals;
    for (auto &p : phones) {
        if (seen_phone_vals.insert(p.normalized).second) {
            unique_phones.push_back(std::move(p));
        }
    }
    phones = std::move(unique_phones);

    // Deduplicate emails
    std::vector<Email> unique_emails;
    std::unordered_set<std::string> seen_email_vals;
    for (auto &e : emails) {
        std::string val_lower = to_lower_ascii(e.value);
        if (seen_email_vals.insert(val_lower).second) {
            unique_emails.push_back(std::move(e));
        }
    }
    emails = std::move(unique_emails);

    std::string display_name = fn;
    if (display_name.empty()) {
        std::string candidate = given_name;
        if (!candidate.empty() && !family_name.empty()) {
            candidate += " ";
            candidate += family_name;
        } else if (!family_name.empty()) {
            candidate = family_name;
        }
        candidate = trim(candidate);
        if (!candidate.empty()) {
            display_name = candidate;
        } else if (!phones.empty()) {
            display_name = phones[0].value;
        } else {
            display_name = "Unnamed Contact";
        }
    }

    if (display_name == "Unnamed Contact" && phones.empty() && emails.empty()) {
        return std::nullopt;
    }

    bool any_human = false;
    for (const std::string &part : {fn, given_name, family_name, org}) {
        if (!part.empty() && !looks_like_number(part)) {
            any_human = true;
            break;
        }
    }
    bool nameless = !any_human;

    if (uid.empty()) {
        std::string uid_str = file_path.filename().string() + "_" + display_name + "_" +
                              (phones.empty() ? "" : phones[0].value);
        uid = SHA256::hash_hex(uid_str).substr(0, 16);
    }

    std::string avatar_path;
    if (!photo_data.empty()) {
        try {
            fs::path cache_dir = get_cache_dir();
            std::error_code ec;
            fs::create_directories(cache_dir, ec);
            std::string img_hash = SHA256::hash_hex(photo_data.data(), photo_data.size()).substr(0, 16);
            fs::path img_file = cache_dir / (img_hash + "." + photo_ext);
            if (!fs::exists(img_file, ec)) {
                std::ofstream ofs(img_file, std::ios::binary);
                if (ofs.is_open()) {
                    ofs.write(reinterpret_cast<const char*>(photo_data.data()), photo_data.size());
                }
            }
            avatar_path = img_file.string();
        } catch (const std::exception &e) {
            std::cerr << "Error saving avatar for " << display_name << ": " << e.what() << "\n";
        }
    }

    struct stat st;
    int64_t mtime = 0;
    if (stat(file_path.c_str(), &st) == 0) {
        mtime = st.st_mtime;
    }

    return Contact{
        .id = uid,
        .display_name = display_name,
        .given_name = given_name,
        .family_name = family_name,
        .organization = org,
        .phones = std::move(phones),
        .emails = std::move(emails),
        .avatar_path = std::move(avatar_path),
        .birthday = birthday,
        .source = source_id,
        .nameless = nameless,
        .mtime = mtime
    };
}

std::vector<Contact> read_contacts_from_dir(const fs::path &dir_path) {
    std::vector<Contact> contacts;
    std::string source_id = dir_path.filename().string();
    std::error_code ec;

    // Collect .vcf files and sort paths for deterministic order
    std::vector<fs::path> vcf_files;
    for (const auto &entry : fs::directory_iterator(dir_path, ec)) {
        if (entry.is_regular_file(ec) && entry.path().extension() == ".vcf") {
            vcf_files.push_back(entry.path());
        }
    }
    std::sort(vcf_files.begin(), vcf_files.end());

    for (const auto &vcf : vcf_files) {
        auto parsed = parse_vcard_file(vcf, source_id);
        if (parsed) {
            contacts.push_back(std::move(*parsed));
        }
    }

    std::stable_sort(contacts.begin(), contacts.end(), [](const Contact &a, const Contact &b) {
        return utf8_tolower(a.display_name) < utf8_tolower(b.display_name);
    });

    return contacts;
}

// ─── JSON Serialization ──────────────────────────────────────

std::string format_contacts_json(const std::vector<Contact> &contacts) {
    std::string out = "[";
    for (size_t idx = 0; idx < contacts.size(); ++idx) {
        if (idx > 0) out += ", ";
        const auto &c = contacts[idx];
        out += "{\"id\": \"";
        out += json_escape(c.id);
        out += "\", \"displayName\": \"";
        out += json_escape(c.display_name);
        out += "\", \"givenName\": \"";
        out += json_escape(c.given_name);
        out += "\", \"familyName\": \"";
        out += json_escape(c.family_name);
        out += "\", \"organization\": \"";
        out += json_escape(c.organization);
        out += "\", \"phones\": [";
        for (size_t i = 0; i < c.phones.size(); ++i) {
            if (i > 0) out += ", ";
            out += "{\"value\": \"";
            out += json_escape(c.phones[i].value);
            out += "\", \"normalized\": \"";
            out += json_escape(c.phones[i].normalized);
            out += "\", \"type\": \"";
            out += json_escape(c.phones[i].type);
            out += "\", \"primary\": ";
            out += c.phones[i].primary ? "true}" : "false}";
        }
        out += "], \"emails\": [";
        for (size_t i = 0; i < c.emails.size(); ++i) {
            if (i > 0) out += ", ";
            out += "{\"value\": \"";
            out += json_escape(c.emails[i].value);
            out += "\", \"type\": \"";
            out += json_escape(c.emails[i].type);
            out += "\", \"primary\": ";
            out += c.emails[i].primary ? "true}" : "false}";
        }
        out += "], \"avatarPath\": \"";
        out += json_escape(c.avatar_path);
        out += "\", \"birthday\": ";
        if (c.birthday.has_value()) {
            out += "{\"year\": ";
            if (c.birthday->year.has_value()) {
                out += std::to_string(c.birthday->year.value());
            } else {
                out += "null";
            }
            out += ", \"month\": ";
            out += std::to_string(c.birthday->month);
            out += ", \"day\": ";
            out += std::to_string(c.birthday->day);
            out += "}";
        } else {
            out += "null";
        }
        out += ", \"source\": \"";
        out += json_escape(c.source);
        out += "\", \"nameless\": ";
        out += c.nameless ? "true" : "false";
        out += ", \"mtime\": ";
        out += std::to_string(c.mtime);
        out += "}";
    }
    out += "]";
    return out;
}

// ─── ContactMonitor ──────────────────────────────────────────

class ContactMonitor {
public:
    explicit ContactMonitor(std::string target_device_id)
        : target_device_id_(std::move(target_device_id)) {}

    bool update_and_emit() {
        current_dir_ = find_device_directory(target_device_id_);
        std::error_code ec;
        if (current_dir_.empty() || !fs::exists(current_dir_, ec)) {
            std::cout << "{\"event\": \"error\", \"code\": \"no_contact_source\", \"message\": \"No KDE Connect contacts directory found\"}\n" << std::flush;
            return false;
        }

        std::vector<Contact> contacts = read_contacts_from_dir(current_dir_);
        std::string payload = format_contacts_json(contacts);
        std::string payload_hash = SHA256::hash_hex(payload);

        if (payload_hash != last_hash_) {
            last_hash_ = payload_hash;

            std::cout << "{\"event\": \"ready\", \"sourcePath\": \""
                      << json_escape(current_dir_.string())
                      << "\", \"count\": " << contacts.size() << "}\n" << std::flush;

            std::cout << "{\"event\": \"snapshot\", \"contacts\": "
                      << payload << "}\n" << std::flush;
        }
        return true;
    }

    const fs::path &current_dir() const { return current_dir_; }

    void run_fallback() {
        while (g_running) {
            update_and_emit();
            for (int i = 0; i < 30 && g_running; ++i) {
                usleep(100000); // 100ms * 30 = 3s
            }
        }
    }

    void run_inotify() {
        if (!update_and_emit()) {
            return;
        }

        int inotify_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
        if (inotify_fd < 0) {
            run_fallback();
            return;
        }

        int wd = inotify_add_watch(inotify_fd, current_dir_.c_str(),
                                   IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE |
                                   IN_DELETE | IN_MOVED_FROM | IN_MODIFY | IN_ATTRIB);
        if (wd < 0) {
            close(inotify_fd);
            run_fallback();
            return;
        }

        bool pending_update = false;
        auto deadline = std::chrono::steady_clock::now();

        while (g_running) {
            int timeout_ms = -1;
            auto now = std::chrono::steady_clock::now();

            if (pending_update) {
                if (now >= deadline) {
                    update_and_emit();
                    pending_update = false;
                    timeout_ms = -1;
                } else {
                    auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
                    timeout_ms = static_cast<int>(std::max<int64_t>(0, remaining.count()));
                }
            }

            struct pollfd pfd;
            pfd.fd = inotify_fd;
            pfd.events = POLLIN;
            pfd.revents = 0;

            int ret = poll(&pfd, 1, timeout_ms);
            if (ret < 0) {
                if (errno == EINTR) continue;
                break;
            }

            if (ret > 0 && (pfd.revents & POLLIN)) {
                char buf[4096] __attribute__ ((aligned(__alignof__(struct inotify_event))));
                while (read(inotify_fd, buf, sizeof(buf)) > 0) {}
                pending_update = true;
                deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(250);
            } else if (ret == 0 && pending_update) {
                update_and_emit();
                pending_update = false;
            }
        }

        inotify_rm_watch(inotify_fd, wd);
        close(inotify_fd);
    }

private:
    std::string target_device_id_;
    fs::path current_dir_;
    std::string last_hash_;
};

} // namespace

int main(int argc, char **argv) {
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    std::setlocale(LC_ALL, "");

    std::string device_id;
    bool once = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--device") {
            if (i + 1 < argc) {
                std::string val = argv[++i];
                if (!val.empty() && val[0] != '-') {
                    device_id = val;
                }
            }
        } else if (arg == "--once") {
            once = true;
        }
    }

    struct sigaction sa;
    std::memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sig_handler;
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);

    ContactMonitor monitor(device_id);

    if (once) {
        monitor.update_and_emit();
        return 0;
    }

    monitor.run_inotify();
    return 0;
}
