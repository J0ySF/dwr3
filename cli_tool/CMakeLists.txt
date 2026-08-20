cmake_minimum_required(VERSION 3.17)

add_executable(dwr3_cli main.c)
target_link_libraries(dwr3_cli PUBLIC dwr3 Tinywav)
target_compile_options(dwr3_cli PRIVATE -Wall)
set_property(TARGET dwr3_cli PROPERTY C_STANDARD 23)
