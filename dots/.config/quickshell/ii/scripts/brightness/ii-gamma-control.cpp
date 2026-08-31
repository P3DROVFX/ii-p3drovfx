#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include <wayland-client-protocol.h>

#include "hyprland-ctm-control-v1-client-protocol.h"

namespace {

struct OutputState {
    uint32_t globalName = 0;
    wl_output* output = nullptr;
    std::string name;
    double gamma = 1.0;
};

struct State {
    wl_display* display = nullptr;
    hyprland_ctm_control_manager_v1* manager = nullptr;
    std::vector<OutputState> outputs;
    unsigned int temperature = 0;
    bool blocked = false;
};

std::array<double, 3> matrixForTemperature(unsigned int temperature) {
    if (temperature == 0 || temperature == 6500)
        return {1.0, 1.0, 1.0};

    double temp = std::max(1000u, std::min(20000u, temperature)) / 100.0;
    double red = 1.0;
    double green = 1.0;
    double blue = 1.0;

    if (temp <= 66.0) {
        red = 255.0;
        green = std::clamp(99.4708025861 * std::log(temp) - 161.1195681661, 0.0, 255.0);
        blue = temp <= 19.0
            ? 0.0
            : std::clamp(std::log(temp - 10.0) * 138.5177312231 - 305.0447927307, 0.0, 255.0);
    } else {
        red = std::clamp(329.698727446 * std::pow(temp - 60.0, -0.1332047592), 0.0, 255.0);
        green = std::clamp(288.1221695283 * std::pow(temp - 60.0, -0.0755148492), 0.0, 255.0);
        blue = 255.0;
    }

    return {red / 255.0, green / 255.0, blue / 255.0};
}

void outputGeometry(void*, wl_output*, int32_t, int32_t, int32_t, int32_t, int32_t, const char*, const char*, int32_t) {}
void outputMode(void*, wl_output*, uint32_t, int32_t, int32_t, int32_t) {}
void outputDone(void*, wl_output*) {}
void outputScale(void*, wl_output*, int32_t) {}

void outputName(void* data, wl_output*, const char* name) {
    auto* output = static_cast<OutputState*>(data);
    output->name = name ? name : "";
}

void outputDescription(void*, wl_output*, const char*) {}

const wl_output_listener outputListener = {
    outputGeometry,
    outputMode,
    outputDone,
    outputScale,
    outputName,
    outputDescription,
};

void managerBlocked(void* data, hyprland_ctm_control_manager_v1*) {
    auto* state = static_cast<State*>(data);
    state->blocked = true;
    std::cerr << "ii-gamma-control: another CTM manager is already active\n";
}

const hyprland_ctm_control_manager_v1_listener managerListener = {
    managerBlocked,
};

void registryGlobal(void* data, wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
    auto* state = static_cast<State*>(data);

    if (std::string(interface) == "hyprland_ctm_control_manager_v1") {
        const uint32_t bindVersion = std::min(version, 2u);
        state->manager = static_cast<hyprland_ctm_control_manager_v1*>(wl_registry_bind(
            registry,
            name,
            &hyprland_ctm_control_manager_v1_interface,
            bindVersion
        ));
        if (bindVersion >= 2)
            hyprland_ctm_control_manager_v1_add_listener(state->manager, &managerListener, state);
        return;
    }

    if (std::string(interface) != "wl_output" || state->outputs.size() >= 32)
        return;

    auto output = static_cast<wl_output*>(wl_registry_bind(
        registry,
        name,
        &wl_output_interface,
        std::min(version, 4u)
    ));

    state->outputs.push_back({name, output, "", 1.0});
    auto& outputState = state->outputs.back();
    wl_output_add_listener(output, &outputListener, &outputState);
}

void registryGlobalRemove(void* data, wl_registry*, uint32_t name) {
    auto* state = static_cast<State*>(data);
    std::erase_if(state->outputs, [name](const OutputState& output) {
        return output.globalName == name;
    });
}

const wl_registry_listener registryListener = {
    registryGlobal,
    registryGlobalRemove,
};

bool applyMatrices(State& state) {
    if (!state.manager || state.blocked)
        return false;

    const auto temperature = matrixForTemperature(state.temperature);
    for (const auto& output : state.outputs) {
        const double gamma = std::max(0.0, std::min(2.0, output.gamma));
        hyprland_ctm_control_manager_v1_set_ctm_for_output(
            state.manager,
            output.output,
            wl_fixed_from_double(temperature[0] * gamma),
            wl_fixed_from_double(0.0),
            wl_fixed_from_double(0.0),
            wl_fixed_from_double(0.0),
            wl_fixed_from_double(temperature[1] * gamma),
            wl_fixed_from_double(0.0),
            wl_fixed_from_double(0.0),
            wl_fixed_from_double(0.0),
            wl_fixed_from_double(temperature[2] * gamma)
        );
    }

    hyprland_ctm_control_manager_v1_commit(state.manager);
    return wl_display_flush(state.display) == 0;
}

void setGamma(State& state, const std::string& name, double gamma) {
    for (auto& output : state.outputs) {
        if (output.name == name) {
            output.gamma = std::max(0.0, std::min(2.0, gamma));
            applyMatrices(state);
            return;
        }
    }
    std::cerr << "ii-gamma-control: output not found: " << name << "\n";
}

void handleCommand(State& state, const std::string& line) {
    std::istringstream stream(line);
    std::string command;
    stream >> command;

    if (command == "set") {
        std::string name;
        double gamma = 1.0;
        if (stream >> name >> gamma)
            setGamma(state, name, gamma);
    } else if (command == "temperature") {
        std::string tempStr;
        if (stream >> tempStr) {
            if (tempStr == "identity" || tempStr == "off" || tempStr == "none" || tempStr == "0") {
                state.temperature = 0;
            } else {
                try {
                    unsigned int temperature = std::stoul(tempStr);
                    state.temperature = (temperature == 0 || temperature == 6500) ? 0 : std::max(1000u, std::min(20000u, temperature));
                } catch (...) {
                    state.temperature = 0;
                }
            }
            applyMatrices(state);
        }
    } else if (command == "identity") {
        state.temperature = 0;
        applyMatrices(state);
    } else if (command == "reset") {
        state.temperature = 0;
        for (auto& output : state.outputs)
            output.gamma = 1.0;
        applyMatrices(state);
    } else if (command == "quit") {
        std::exit(0);
    }
}

} // namespace

int main(int argc, char** argv) {
    if (argc < 2 || std::string(argv[1]) != "--daemon") {
        std::cerr << "usage: ii-gamma-control --daemon\n";
        return 2;
    }

    State state;
    state.outputs.reserve(32);
    state.display = wl_display_connect(nullptr);
    if (!state.display) {
        std::cerr << "ii-gamma-control: cannot connect to Wayland\n";
        return 1;
    }

    wl_registry* registry = wl_display_get_registry(state.display);
    wl_registry_add_listener(registry, &registryListener, &state);
    if (wl_display_roundtrip(state.display) < 0 || !state.manager) {
        std::cerr << "ii-gamma-control: Hyprland CTM protocol unavailable\n";
        wl_display_disconnect(state.display);
        return 1;
    }

    // The output name events are delivered after the initial registry roundtrip.
    if (wl_display_roundtrip(state.display) < 0 || state.blocked) {
        wl_display_disconnect(state.display);
        return 1;
    }

    std::cout << "READY\n" << std::flush;
    applyMatrices(state);

    std::string line;
    while (std::getline(std::cin, line)) {
        handleCommand(state, line);
        if (wl_display_dispatch_pending(state.display) < 0)
            break;
    }

    if (state.manager)
        hyprland_ctm_control_manager_v1_destroy(state.manager);
    wl_display_disconnect(state.display);
    return 0;
}
