cmake_minimum_required(VERSION 3.21)
project(mpv-wallpaper LANGUAGES CXX)

# QML module `MpvWallpaper`: one item, MpvItem, that renders libmpv into the
# Qt Quick scene graph (OpenGL). Built and installed by
# scripts/videos/build-mpv-wallpaper-plugin.sh (Settings → Background → Video
# Wallpapers shows the same steps).

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Gui Quick OpenGL)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)

qt_policy(SET QTP0001 NEW)
qt_add_qml_module(mpvwallpaper
    URI MpvWallpaper
    VERSION 1.0
    SHARED
    PLUGIN_TARGET mpvwallpaper
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/MpvWallpaper
    SOURCES src/mpvitem.h src/mpvitem.cpp
)

target_link_libraries(mpvwallpaper PRIVATE Qt6::Gui Qt6::Quick Qt6::OpenGL PkgConfig::MPV)

# The generated type registration includes <mpvitem.h> by bare name.
target_include_directories(mpvwallpaper PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
