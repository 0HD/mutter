# mumble_bridge.dll — C ABI bridge between Flutter (Dart FFI) and libmumble.

cmake_minimum_required(VERSION 3.16)
project(mumble_bridge VERSION 0.0.1 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(WIN32)
    add_definitions(-DNOMINMAX -DWIN32_LEAN_AND_MEAN -D_CRT_SECURE_NO_WARNINGS)
endif()

# Locate libmumble. It lives as a git submodule at third_party/libmumble and
# should already have been configured + built by scripts/build_libmumble.ps1
# before this CMake project is configured.
set(LIBMUMBLE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libmumble"
    CACHE PATH "Path to libmumble source tree")
set(LIBMUMBLE_BUILD_DIR "${LIBMUMBLE_DIR}/build"
    CACHE PATH "Path to libmumble build tree")

if(NOT EXISTS "${LIBMUMBLE_DIR}/include/mumble/Lib.hpp")
    message(FATAL_ERROR "libmumble submodule not initialized at ${LIBMUMBLE_DIR}. "
                        "Run: git submodule update --init --recursive")
endif()

# Imported target for the prebuilt libmumble. We resolve the .dll/.lib at build
# time. The configure step doesn't require libmumble to be built yet, but the
# link step does.
add_library(libmumble_imported SHARED IMPORTED GLOBAL)
set_target_properties(libmumble_imported PROPERTIES
    IMPORTED_LOCATION         "${LIBMUMBLE_BUILD_DIR}/Release/mumble_library.dll"
    IMPORTED_IMPLIB           "${LIBMUMBLE_BUILD_DIR}/Release/mumble_library.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${LIBMUMBLE_DIR}/include"
)

# Runtime DLLs that libmumble depends on; copy these alongside our bridge.
set(LIBMUMBLE_RUNTIME_DLLS
    "${LIBMUMBLE_BUILD_DIR}/Release/mumble_library.dll"
    "${LIBMUMBLE_BUILD_DIR}/Release/boost_thread-vc143-mt-x64-1_84.dll"
    "${LIBMUMBLE_BUILD_DIR}/Release/libcrypto-3-x64.dll"
    "${LIBMUMBLE_BUILD_DIR}/Release/libssl-3-x64.dll"
    "${LIBMUMBLE_BUILD_DIR}/Release/libprotobuf.dll"
    "${LIBMUMBLE_BUILD_DIR}/Release/opus.dll"
)

# ms-gsl (libmumble headers use gsl::span in their public API).
find_package(Microsoft.GSL CONFIG REQUIRED)
# OpenSSL — we use it directly to generate the self-signed client cert.
find_package(OpenSSL REQUIRED)

# RNNoise for noise suppression (vcpkg ships it).
find_package(rnnoise CONFIG QUIET)

# Bridge DLL.
add_library(mumble_bridge SHARED
    src/bridge.cpp
    src/audio_engine.cpp
    third_party/dart_api/dart_api_dl.c
)
target_compile_definitions(mumble_bridge PRIVATE MUMBLE_BRIDGE_EXPORTS)
target_include_directories(mumble_bridge
    PUBLIC  include
    PRIVATE src third_party/dart_api
)
target_link_libraries(mumble_bridge
    PRIVATE
        libmumble_imported
        Microsoft.GSL::GSL
        OpenSSL::Crypto
        OpenSSL::SSL
)
if(TARGET rnnoise::rnnoise)
    target_link_libraries(mumble_bridge PRIVATE rnnoise::rnnoise)
    target_compile_definitions(mumble_bridge PRIVATE HAVE_RNNOISE)
endif()

if(WIN32)
    target_link_libraries(mumble_bridge PRIVATE
        ws2_32 ole32 ksuser avrt mfplat mfreadwrite mfuuid winmm
    )
endif()

# Copy libmumble and its runtime deps next to our DLL.
foreach(dll IN LISTS LIBMUMBLE_RUNTIME_DLLS)
    add_custom_command(TARGET mumble_bridge POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${dll}" "$<TARGET_FILE_DIR:mumble_bridge>"
    )
endforeach()
