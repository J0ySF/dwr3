cmake_minimum_required(VERSION 3.17)

# Function to ease the benchmarking process, each benchmark may alter some definitions thus needing a different binary
# to be built, see benchmark/CMakeLists.txt
function(dwr3_variant suffix)
    set(DWR3_SOURCE ${CMAKE_SOURCE_DIR}/lib/src/dwr3.cu ${CMAKE_SOURCE_DIR}/lib/src/gen/boundary_filters.c)
    set(DWR3_INCLUDE ${CMAKE_SOURCE_DIR}/lib/include)
    set(DWR3_VARIANT_NAME "dwr3${suffix}")
    add_library(${DWR3_VARIANT_NAME} STATIC ${DWR3_SOURCE})
    target_include_directories(${DWR3_VARIANT_NAME} PUBLIC ${DWR3_INCLUDE})
    target_link_libraries(${DWR3_VARIANT_NAME} PUBLIC m)
    set_property(TARGET ${DWR3_VARIANT_NAME} PROPERTY C_STANDARD 23)
    set_property(TARGET ${DWR3_VARIANT_NAME} PROPERTY CXX_STANDARD 23)
    set_property(TARGET ${DWR3_VARIANT_NAME} PROPERTY CUDA_STANDARD 23)
    target_compile_options(${DWR3_VARIANT_NAME} PRIVATE $<$<COMPILE_LANGUAGE:C>:-Wall>)
    target_compile_options(${DWR3_VARIANT_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Wall -fno-rtti -fno-exceptions>)
    target_compile_options(${DWR3_VARIANT_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-Wall -fno-rtti -fno-exceptions>)
    target_compile_options(${DWR3_VARIANT_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:
            $<$<CONFIG:Debug>:-O0 -lineinfo>
            $<$<CONFIG:RelWithDebInfo>:-O3 -lineinfo>
            $<$<CONFIG:Release>:-O3>
            $<$<CONFIG:MinSizeRel>:-O3>>)
endfunction()

# Default build without any redefinitions
dwr3_variant("")
