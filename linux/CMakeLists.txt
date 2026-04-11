cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

set(BINARY_NAME "ivi_monitor")
set(APPLICATION_ID "com.agl.ivi_monitor")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

find_package(PkgConfig REQUIRED)

add_subdirectory("runner")

set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")
set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")

install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/flutter_assets\")
  file(COPY \"${PROJECT_BUILD_DIR}/flutter_assets\"
       DESTINATION \"${INSTALL_BUNDLE_DATA_DIR}\")
")

install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_LIB_DIR}\")
  file(COPY \"${PROJECT_BUILD_DIR}/\"
       DESTINATION \"${INSTALL_BUNDLE_LIB_DIR}\"
       FILES_MATCHING PATTERN \"*.so*\")
")
