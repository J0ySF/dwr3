cmake_minimum_required(VERSION 3.17)
project(dwr3 VERSION 0.0.0 LANGUAGES C CXX CUDA)

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif ()
set(CMAKE_CUDA_SEPARABLE_COMPILATION ON)
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)

find_package(CUDAToolkit REQUIRED)
add_subdirectory(third_party)

add_subdirectory(lib)

option(DWR3_BUILD_CLI_TOOL "Build the Command Line Interface tool" ON)
if (DWR3_BUILD_CLI_TOOL)
    add_subdirectory(cli_tool)
endif ()

option(DWR3_BUILD_BENCHMARKS "Build the benchmarks" ON)
if (DWR3_BUILD_BENCHMARKS)
    add_subdirectory(benchmark)
endif ()

option(DWR3_BUILD_DAW_PLUGIN "Build the DAW plugin" ON)
if (DWR3_BUILD_DAW_PLUGIN)
    add_subdirectory(plugin)
endif ()