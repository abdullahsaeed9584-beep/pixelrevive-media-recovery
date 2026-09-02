cmake_minimum_required(VERSION 3.10.2)

project("carver")

add_library(
    carver
    SHARED
    carver.cpp
)

find_library(
    log-lib
    log
)

target_link_libraries(
    carver
    ${log-lib}
)
