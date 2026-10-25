cmake_minimum_required(VERSION 3.16)

set(ZOS_TOOLCHAIN sdcc)
get_filename_component(PLASMA_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PLASMA_ROOT}/bin")
include("$ENV{ZOS_PATH}/cmake/zos_init.cmake")

project(zeal_plasma_c LANGUAGES C ASM)

zos_use(zvb)
find_package(ZVB_SDK REQUIRED)
add_executable(plasmac "${PLASMA_ROOT}/src/main.c")
target_link_libraries(plasmac PRIVATE zvb)
zos_add_outputs(plasmac)
