cmake_minimum_required(VERSION 3.17)

if (DWR3_BUILD_CLI_TOOL)
    # Added this way to silence warnings and avoid cluttering targets with tinywav's tests
    add_library(Tinywav tinywav/tinywav.c tinywav/tinywav.h)
    target_include_directories(Tinywav PUBLIC tinywav)
    set_source_files_properties(tinywav/tinywav.c tinywav/tinywav.h PROPERTIES COMPILE_FLAGS "-w")
    set_property(TARGET Tinywav PROPERTY C_STANDARD 99)
    target_compile_definitions(Tinywav PRIVATE TINYWAV_USE_MALLOC=1)
endif ()

if (DWR3_BUILD_DAW_PLUGIN)
    add_subdirectory(JUCE)
endif ()