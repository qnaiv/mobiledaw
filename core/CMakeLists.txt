cmake_minimum_required(VERSION 3.22)
project(mdaw_core LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(MDAW_BUILD_TESTS "Build the desktop test runner" OFF)

# ccache があれば使う（JUCE のコンパイルを2回目以降ほぼゼロにする）
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
    set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
endif()

include(FetchContent)

# JUCE: DSP・オーディオ基礎・ファイル形式のモジュールだけを使う（AGPLv3）。
# JUCE自体のCMake（juceaide）は使わず、モジュールのソースを直接ビルドする。
FetchContent_Declare(juce
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG        9.0.5
    GIT_SHALLOW    TRUE
    SOURCE_SUBDIR  do-not-add-subdirectory)
FetchContent_MakeAvailable(juce)

set(JUCE_MODULES_DIR ${juce_SOURCE_DIR}/modules)

add_library(mdaw_juce OBJECT
    ${JUCE_MODULES_DIR}/juce_core/juce_core.cpp
    ${JUCE_MODULES_DIR}/juce_core/juce_core_CompilationTime.cpp
    ${JUCE_MODULES_DIR}/juce_core/juce_core_zlib.c
    ${JUCE_MODULES_DIR}/juce_audio_basics/juce_audio_basics.cpp
    ${JUCE_MODULES_DIR}/juce_audio_formats/juce_audio_formats.cpp
    ${JUCE_MODULES_DIR}/juce_dsp/juce_dsp.cpp)

target_include_directories(mdaw_juce PUBLIC ${JUCE_MODULES_DIR})
target_compile_definitions(mdaw_juce PUBLIC
    JUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1
    JUCE_STANDALONE_APPLICATION=1
    JUCE_USE_CURL=0
    JUCE_WEB_BROWSER=0
    JUCE_USE_FLAC=0
    JUCE_USE_OGGVORBIS=0
    JUCE_USE_OPUS=0
    JUCE_USE_MP3AUDIOFORMAT=0
    JUCE_USE_LAME_AUDIO_FORMAT=0
    JUCE_USE_WINDOWS_MEDIA_FORMAT=0
    JUCE_MODULE_AVAILABLE_juce_core=1
    JUCE_MODULE_AVAILABLE_juce_audio_basics=1
    JUCE_MODULE_AVAILABLE_juce_audio_formats=1
    JUCE_MODULE_AVAILABLE_juce_dsp=1
    $<$<PLATFORM_ID:Android>:JUCE_ANDROID=1>)
target_compile_options(mdaw_juce PRIVATE -w)

if(ANDROID)
    # JUCE が Android で使う NDK 付属の cpufeatures
    target_sources(mdaw_juce PRIVATE ${ANDROID_NDK}/sources/android/cpufeatures/cpu-features.c)
    target_include_directories(mdaw_juce PUBLIC ${ANDROID_NDK}/sources/android/cpufeatures)
endif()

set(MDAW_CORE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/engine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/synth.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/wavetable.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/fx.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/model.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/commands.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/history.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/project_json.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/playback.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/session.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/exporter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/kit.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/sampler.cpp)

set(MDAW_WARNINGS -Wall -Wextra -Wno-unused-parameter)

if(ANDROID)
    FetchContent_Declare(oboe
        GIT_REPOSITORY https://github.com/google/oboe.git
        GIT_TAG        1.11.0
        GIT_SHALLOW    TRUE)
    FetchContent_MakeAvailable(oboe)
endif()

# Flutter（dart:ffi）から読み込む共有ライブラリ。名前は libmdaw.so。
add_library(mdaw SHARED
    ${MDAW_CORE_SOURCES}
    ${CMAKE_CURRENT_SOURCE_DIR}/src/mdaw_api.cpp
    $<TARGET_OBJECTS:mdaw_juce>)
target_include_directories(mdaw
    PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src
            $<TARGET_PROPERTY:mdaw_juce,INTERFACE_INCLUDE_DIRECTORIES>)
target_compile_definitions(mdaw PRIVATE
    MDAW_BUILDING_LIBRARY=1
    $<TARGET_PROPERTY:mdaw_juce,INTERFACE_COMPILE_DEFINITIONS>)
target_compile_options(mdaw PRIVATE ${MDAW_WARNINGS})

if(ANDROID)
    target_sources(mdaw PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src/oboe_output.cpp)
    target_compile_definitions(mdaw PRIVATE MDAW_HAS_OBOE=1)
    target_link_libraries(mdaw PRIVATE oboe log android)
elseif(UNIX AND NOT APPLE)
    target_link_libraries(mdaw PRIVATE pthread dl rt)
endif()

if(MDAW_BUILD_TESTS)
    enable_testing()
    add_executable(mdaw_tests
        ${MDAW_CORE_SOURCES}
        ${CMAKE_CURRENT_SOURCE_DIR}/src/mdaw_api.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_main.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/engine_tests.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/model_tests.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/json_tests.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/sequencer_tests.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/api_tests.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/sound_tests.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/kit_tests.cpp
        $<TARGET_OBJECTS:mdaw_juce>)
    target_include_directories(mdaw_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        $<TARGET_PROPERTY:mdaw_juce,INTERFACE_INCLUDE_DIRECTORIES>)
    target_compile_definitions(mdaw_tests PRIVATE
        $<TARGET_PROPERTY:mdaw_juce,INTERFACE_COMPILE_DEFINITIONS>)
    target_compile_options(mdaw_tests PRIVATE ${MDAW_WARNINGS})
    if(UNIX AND NOT APPLE)
        target_link_libraries(mdaw_tests PRIVATE pthread dl rt)
    endif()
    add_test(NAME mdaw_tests COMMAND mdaw_tests)

    # 音作りの確認用：project.json を wav に書き出す
    add_executable(mdaw_render
        ${MDAW_CORE_SOURCES}
        ${CMAKE_CURRENT_SOURCE_DIR}/../tools/render_project.cpp
        $<TARGET_OBJECTS:mdaw_juce>)
    target_include_directories(mdaw_render PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        $<TARGET_PROPERTY:mdaw_juce,INTERFACE_INCLUDE_DIRECTORIES>)
    target_compile_definitions(mdaw_render PRIVATE
        $<TARGET_PROPERTY:mdaw_juce,INTERFACE_COMPILE_DEFINITIONS>)
    if(UNIX AND NOT APPLE)
        target_link_libraries(mdaw_render PRIVATE pthread dl rt)
    endif()
endif()
