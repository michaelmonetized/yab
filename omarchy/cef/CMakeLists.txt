# Qi (CEF): the Chromium Embedded Framework engine for Qi.
# Run ./fetch-cef.sh first; it points third_party/cef at the pinned CEF.
cmake_minimum_required(VERSION 3.21)
set(CMAKE_CONFIGURATION_TYPES Release CACHE STRING "" FORCE)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
project(qi_cef CXX C)
if(NOT DEFINED PROJECT_ARCH)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(PROJECT_ARCH "arm64")
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "armv7l|armv7")
    set(PROJECT_ARCH "arm")
  endif()
endif()

set(CEF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/cef")
if(NOT EXISTS "${CEF_ROOT}/cmake/FindCEF.cmake")
  message(FATAL_ERROR "CEF not found. Run ./fetch-cef.sh first.")
endif()
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CEF_ROOT}/cmake")
find_package(CEF REQUIRED)
find_package(SQLite3 REQUIRED)
add_subdirectory(${CEF_LIBCEF_DLL_WRAPPER_PATH} libcef_dll_wrapper)

set(QI_SRCS
  src/main.cc
  src/app.cc
  src/client.cc
  src/window.cc
  src/shell.cc
  src/profiles.cc
  src/theme.cc
  src/safety.cc
  src/keys.cc
  src/features.cc
  )

set(CEF_TARGET qi-cef)
SET_CEF_TARGET_OUT_DIR()
ADD_LOGICAL_TARGET("libcef_lib" "${CEF_LIB_DEBUG}" "${CEF_LIB_RELEASE}")
add_executable(${CEF_TARGET} ${QI_SRCS})
SET_EXECUTABLE_TARGET_PROPERTIES(${CEF_TARGET})
target_include_directories(${CEF_TARGET} PRIVATE "${CEF_ROOT}")
add_dependencies(${CEF_TARGET} libcef_dll_wrapper)
target_link_libraries(${CEF_TARGET} libcef_lib libcef_dll_wrapper ${CEF_STANDARD_LIBS} SQLite3::SQLite3)

add_executable(qi-check src/qi_check.cc src/keys.cc src/features.cc)
target_compile_features(qi-check PRIVATE cxx_std_17)
set_target_properties(${CEF_TARGET} PROPERTIES INSTALL_RPATH "$ORIGIN" BUILD_WITH_INSTALL_RPATH TRUE)

COPY_FILES("${CEF_TARGET}" "${CEF_BINARY_FILES}" "${CEF_BINARY_DIR}" "${CEF_TARGET_OUT_DIR}")
COPY_FILES("${CEF_TARGET}" "${CEF_RESOURCE_FILES}" "${CEF_RESOURCE_DIR}" "${CEF_TARGET_OUT_DIR}")
