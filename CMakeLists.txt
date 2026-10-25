cmake_minimum_required(VERSION 3.16)

if(NOT EXISTS "$ENV{ZOS_PATH}/cmake/zos_init.cmake")
    message(FATAL_ERROR "Set ZOS_PATH to a Zeal OS checkout with the CMake toolchain, or build with zde cmake.")
endif()

set(ZOS_TOOLCHAIN z88dk)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin")
include("$ENV{ZOS_PATH}/cmake/zos_init.cmake")

project(zeal_plasma LANGUAGES ASM)

add_executable(plasma src/main.asm)
set_target_properties(plasma PROPERTIES SUFFIX ".bin")
target_compile_options(plasma PRIVATE -l -s)
target_link_options(plasma PRIVATE -m)
set_property(SOURCE src/main.asm APPEND PROPERTY OBJECT_DEPENDS
    "$ENV{ZOS_PATH}/sdk/z88dk-z80asm/zos_sys.asm"
    "$ENV{ZOS_PATH}/sdk/z88dk-z80asm/zos_video.asm")

# Each variant uses its native Zeal toolchain in a separate CMake build tree.
include(ExternalProject)
ExternalProject_Add(plasmac
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cmake/sdcc"
    BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/sdcc"
    DOWNLOAD_COMMAND ""
    UPDATE_COMMAND ""
    INSTALL_COMMAND ""
    BUILD_ALWAYS TRUE
    BUILD_BYPRODUCTS "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/plasmac.bin"
)
