cmake_minimum_required(VERSION 3.17)

# Function to ease the benchmarking process, each benchmark may alter some definitions thus needing a different binary
## to be built
function(dwr3_benchmark_variant suffix)
    set(SUFFIX "${suffix}")
    set(DWR3_BENCHMARK_VARIANT_NAME "dwr3_benchmark${suffix}")
    if (SUFFIX STREQUAL "")
    else ()
        dwr3_variant(${SUFFIX})
    endif ()
    add_executable(${DWR3_BENCHMARK_VARIANT_NAME} main.cu)
    target_link_libraries(${DWR3_BENCHMARK_VARIANT_NAME} PUBLIC "dwr3${suffix}")
    set_property(TARGET ${DWR3_BENCHMARK_VARIANT_NAME} PROPERTY CUDA_STANDARD 23)
    target_compile_options(${DWR3_BENCHMARK_VARIANT_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-Wall -fno-rtti -fno-exceptions>)
endfunction()

# Graph size benchmark #################################################################################################
dwr3_benchmark_variant("_bbs0002")
target_compile_definitions(dwr3_bbs0002 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_bbs0002 PUBLIC DWR3_BUFFER_BASE_SIZE=2)

dwr3_benchmark_variant("_bbs0004")
target_compile_definitions(dwr3_bbs0004 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_bbs0004 PUBLIC DWR3_BUFFER_BASE_SIZE=4)

dwr3_benchmark_variant("_bbs0008")
target_compile_definitions(dwr3_bbs0008 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_bbs0008 PUBLIC DWR3_BUFFER_BASE_SIZE=8)

dwr3_benchmark_variant("_bbs0016")
target_compile_definitions(dwr3_bbs0016 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_bbs0016 PUBLIC DWR3_BUFFER_BASE_SIZE=16)

dwr3_benchmark_variant("_bbs0032")
target_compile_definitions(dwr3_bbs0032 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_bbs0032 PUBLIC DWR3_BUFFER_BASE_SIZE=32)

dwr3_benchmark_variant("_bbs0064")
target_compile_definitions(dwr3_bbs0064 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_bbs0064 PUBLIC DWR3_BUFFER_BASE_SIZE=64)

dwr3_benchmark_variant("_bbs0128")
target_compile_definitions(dwr3_bbs0128 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_bbs0128 PUBLIC DWR3_BUFFER_BASE_SIZE=128)

# Center iteration size benchmark #################################################################################################
dwr3_benchmark_variant("_c02")
target_compile_definitions(dwr3_c02 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c02 PUBLIC SIM_CENTER_BLOCK_DIM_Z=2)

dwr3_benchmark_variant("_c03")
target_compile_definitions(dwr3_c03 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c03 PUBLIC SIM_CENTER_BLOCK_DIM_Z=3)

dwr3_benchmark_variant("_c04")
target_compile_definitions(dwr3_c04 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c04 PUBLIC SIM_CENTER_BLOCK_DIM_Z=4)

dwr3_benchmark_variant("_c05")
target_compile_definitions(dwr3_c05 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c05 PUBLIC SIM_CENTER_BLOCK_DIM_Z=5)

dwr3_benchmark_variant("_c06")
target_compile_definitions(dwr3_c06 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c06 PUBLIC SIM_CENTER_BLOCK_DIM_Z=6)

dwr3_benchmark_variant("_c07")
target_compile_definitions(dwr3_c07 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c07 PUBLIC SIM_CENTER_BLOCK_DIM_Z=7)

dwr3_benchmark_variant("_c08")
target_compile_definitions(dwr3_c08 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c08 PUBLIC SIM_CENTER_BLOCK_DIM_Z=8)

dwr3_benchmark_variant("_c09")
target_compile_definitions(dwr3_c09 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c09 PUBLIC SIM_CENTER_BLOCK_DIM_Z=9)

dwr3_benchmark_variant("_c10")
target_compile_definitions(dwr3_c10 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c10 PUBLIC SIM_CENTER_BLOCK_DIM_Z=10)

dwr3_benchmark_variant("_c11")
target_compile_definitions(dwr3_c11 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c11 PUBLIC SIM_CENTER_BLOCK_DIM_Z=11)

dwr3_benchmark_variant("_c12")
target_compile_definitions(dwr3_c12 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c12 PUBLIC SIM_CENTER_BLOCK_DIM_Z=12)

dwr3_benchmark_variant("_c13")
target_compile_definitions(dwr3_c13 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c13 PUBLIC SIM_CENTER_BLOCK_DIM_Z=13)

dwr3_benchmark_variant("_c14")
target_compile_definitions(dwr3_c14 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c14 PUBLIC SIM_CENTER_BLOCK_DIM_Z=14)

dwr3_benchmark_variant("_c15")
target_compile_definitions(dwr3_c15 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c15 PUBLIC SIM_CENTER_BLOCK_DIM_Z=15)

dwr3_benchmark_variant("_c16")
target_compile_definitions(dwr3_c16 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_c16 PUBLIC SIM_CENTER_BLOCK_DIM_Z=16)

# Up-Down iteration compare benchmark ##################################################################################

dwr3_benchmark_variant("_udno_dif1")
target_compile_definitions(dwr3_udno_dif1 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_udno_dif1 PUBLIC DISABLE_UPDATE_UP_DOWN_ITERATION)

dwr3_benchmark_variant("_udyes_dif1")
target_compile_definitions(dwr3_udyes_dif1 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)

dwr3_benchmark_variant("_udno_dif8")
target_compile_definitions(dwr3_udno_dif8 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=8)
target_compile_definitions(dwr3_udno_dif8 PUBLIC DISABLE_UPDATE_UP_DOWN_ITERATION)

dwr3_benchmark_variant("_udyes_dif8")
target_compile_definitions(dwr3_udyes_dif8 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=8)

# Enclosure rotation compare benchmark #################################################################################

dwr3_benchmark_variant("_rotno_dif1")
target_compile_definitions(dwr3_rotno_dif1 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_rotno_dif1 PUBLIC DISABLE_COORDS_MAPPING)
target_compile_definitions(dwr3_benchmark_rotno_dif1 PUBLIC MEASURE_ROOM)

dwr3_benchmark_variant("_rotyes_dif1")
target_compile_definitions(dwr3_rotyes_dif1 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=1)
target_compile_definitions(dwr3_benchmark_rotyes_dif1 PUBLIC MEASURE_ROOM)

dwr3_benchmark_variant("_rotno_dif8")
target_compile_definitions(dwr3_rotno_dif8 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=8)
target_compile_definitions(dwr3_rotno_dif8 PUBLIC DISABLE_COORDS_MAPPING)
target_compile_definitions(dwr3_benchmark_rotno_dif8 PUBLIC MEASURE_ROOM)

dwr3_benchmark_variant("_rotyes_dif8")
target_compile_definitions(dwr3_rotyes_dif8 PUBLIC DWR3_BOUNDARY_FILTER_ORDER=8)
target_compile_definitions(dwr3_benchmark_rotyes_dif8 PUBLIC MEASURE_ROOM)