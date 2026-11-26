cmake_minimum_required(VERSION 3.20)
project(cirrusretro LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
include(CTest)
include(FetchContent)

# Keep the audited engine configuration independent of GME's broad defaults.
foreach(format AY GBS GYM HES KSS NSFE SAP SPC VGM)
  set(USE_GME_${format} OFF CACHE BOOL "" FORCE)
endforeach()
set(USE_GME_NSF ON CACHE BOOL "" FORCE)
foreach(option GME_ZLIB GME_BUILD_TESTING GME_BUILD_EXAMPLES GME_BUILD_STATIC GME_BUILD_FRAMEWORK)
  set(${option} OFF CACHE BOOL "" FORCE)
endforeach()
set(GME_BUILD_SHARED ON CACHE BOOL "" FORCE)
FetchContent_Declare(game_music_emu
  GIT_REPOSITORY https://github.com/libgme/game-music-emu.git
  GIT_TAG 9e23d10f9fd2a6a2f33b10912dd8dc7153258995 # 0.6.5
  GIT_SUBMODULES "")
FetchContent_MakeAvailable(game_music_emu)

add_library(cirrus_nsf STATIC src/nsf.c)
target_include_directories(cirrus_nsf PUBLIC include)
target_link_libraries(cirrus_nsf PRIVATE gme::gme)
add_executable(nsf-to-wav src/nsf_to_wav.c)
target_link_libraries(nsf-to-wav PRIVATE cirrus_nsf)

if(BUILD_TESTING)
  find_package(Python3 3.8 REQUIRED COMPONENTS Interpreter)
  add_executable(test-api tests/api.c)
  target_link_libraries(test-api PRIVATE cirrus_nsf)
  add_test(NAME fixture COMMAND Python3::Interpreter
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixture.py ${CMAKE_CURRENT_BINARY_DIR}/pulse.nsf)
  set_tests_properties(fixture PROPERTIES FIXTURES_SETUP pulse)
  add_test(NAME c-api COMMAND test-api ${CMAKE_CURRENT_BINARY_DIR}/pulse.nsf)
  add_test(NAME wav-cli COMMAND Python3::Interpreter ${CMAKE_CURRENT_SOURCE_DIR}/tests/wav_cli.py
    $<TARGET_FILE:nsf-to-wav> ${CMAKE_CURRENT_BINARY_DIR}/pulse.nsf)
  set_tests_properties(c-api wav-cli PROPERTIES FIXTURES_REQUIRED pulse TIMEOUT 60)
endif()
