#pragma once
#include <cstdlib>
#include <utility>
#include <cstdio>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <sys/stat.h>
#include <SDL3/SDL_joystick.h>
#include <SDL3/SDL_gamepad.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_stdinc.h>
namespace SimulatorInput {
inline SDL_Joystick* joystick = nullptr;
inline void Update(void*) {
    static const uint32_t* input = []() -> const uint32_t* {
        const char* path = std::getenv("MKW_SIMULATOR_INPUT");
        if (!path) return nullptr;
        const int fd = open(path, O_RDONLY);
        if (fd < 0) return nullptr;
        struct stat info{};
        if (fstat(fd, &info) != 0 || info.st_size != 4) { close(fd); return nullptr; }
        void* data = mmap(nullptr, 4, PROT_READ, MAP_SHARED, fd, 0);
        close(fd);
        return data == MAP_FAILED ? nullptr : static_cast<const uint32_t*>(data);
    }();
    if (!input) return;
    const uint32_t command = __atomic_load_n(input, __ATOMIC_ACQUIRE);
    // Local diagnostic only: request the built-in CPU driver before race setup.
    if (command & 0x8000) {
        uint32_t data = 0;
        if (Memory::TryRead32(0x809bd728, data) && ((data >= 0x80000000 && data < 0x81800000) || (data >= 0x90000000 && data < 0x98000000))) {
            uint32_t before = 0;
            Memory::TryRead32(data + 56, before);
            if (before == 0) {
                Memory::TryWrite32(data + 56, 1);
                Memory::TryWrite32(data + 3088 + 24, 1);
                std::fprintf(stderr, "[SIMULATOR-DIAGNOSTIC] CPU driver requested: Racedata=%08x playerType=%u->1\n", data, before);
            }
        }
    }
    if (!joystick) return;
    const std::pair<int, uint16_t> buttons[] = {
        {SDL_GAMEPAD_BUTTON_SOUTH, PAD_BUTTON_A}, {SDL_GAMEPAD_BUTTON_EAST, PAD_BUTTON_B},
        {SDL_GAMEPAD_BUTTON_WEST, PAD_BUTTON_X}, {SDL_GAMEPAD_BUTTON_NORTH, PAD_BUTTON_Y},
        {SDL_GAMEPAD_BUTTON_START, PAD_BUTTON_START}, {SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, PAD_TRIGGER_Z},
        {SDL_GAMEPAD_BUTTON_DPAD_UP, PAD_BUTTON_UP}, {SDL_GAMEPAD_BUTTON_DPAD_DOWN, PAD_BUTTON_DOWN},
        {SDL_GAMEPAD_BUTTON_DPAD_LEFT, PAD_BUTTON_LEFT}, {SDL_GAMEPAD_BUTTON_DPAD_RIGHT, PAD_BUTTON_RIGHT},
    };
    for (const auto& [button, mask] : buttons) {
        SDL_SetJoystickVirtualButton(joystick, button, (command & mask) != 0);
    }
    SDL_SetJoystickVirtualAxis(joystick, SDL_GAMEPAD_AXIS_LEFTX, static_cast<int8_t>(command >> 16) * 256);
    SDL_SetJoystickVirtualAxis(joystick, SDL_GAMEPAD_AXIS_LEFTY, -static_cast<int8_t>(command >> 24) * 256);
    SDL_SetJoystickVirtualAxis(joystick, SDL_GAMEPAD_AXIS_LEFT_TRIGGER, (command & PAD_TRIGGER_L) ? 32767 : -32768);
    SDL_SetJoystickVirtualAxis(joystick, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER, (command & PAD_TRIGGER_R) ? 32767 : -32768);
}
inline void Poll() {
    static const bool attached = [] {
        if (!std::getenv("MKW_SIMULATOR_INPUT")) return false;
        SDL_VirtualJoystickDesc desc{};
        SDL_INIT_INTERFACE(&desc);
        desc.type = SDL_JOYSTICK_TYPE_GAMEPAD;
        desc.naxes = SDL_GAMEPAD_AXIS_COUNT;
        desc.nbuttons = SDL_GAMEPAD_BUTTON_COUNT;
        desc.axis_mask = (1u << SDL_GAMEPAD_AXIS_COUNT) - 1;
        desc.button_mask = (1u << SDL_GAMEPAD_BUTTON_COUNT) - 1;
        desc.name = "WiiCompiled Simulator Diagnostic Gamepad";
        desc.Update = Update;
        const auto id = SDL_AttachVirtualJoystick(&desc);
        joystick = id ? SDL_OpenJoystick(id) : nullptr;
        if (!joystick) {
            std::fprintf(stderr, "[SIMULATOR-DIAGNOSTIC] Virtual gamepad failed: %s\n", SDL_GetError());
            return false;
        }
        SDL_SetJoystickPlayerIndex(joystick, 0);
        std::fprintf(stderr, "[SIMULATOR-DIAGNOSTIC] SDL virtual gamepad attached: %u\n", id);
        return true;
    }();
    if (attached) SDL_UpdateJoysticks();
}
}
