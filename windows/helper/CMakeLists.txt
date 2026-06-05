cmake_minimum_required(VERSION 3.14)
project(sdwan_windows_helper LANGUAGES CXX)

add_executable(sdwan_windows_helper
  "sdwan_windows_helper.cpp"
)

apply_standard_settings(sdwan_windows_helper)
target_compile_definitions(sdwan_windows_helper PRIVATE "NOMINMAX" "WIN32_LEAN_AND_MEAN")
target_compile_options(sdwan_windows_helper PRIVATE /utf-8 /wd"4189" /wd"4505")
target_link_options(sdwan_windows_helper PRIVATE /SUBSYSTEM:CONSOLE /ENTRY:wmainCRTStartup)
target_include_directories(sdwan_windows_helper PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(sdwan_windows_helper PRIVATE
  "advapi32.lib"
  "iphlpapi.lib"
  "ws2_32.lib"
)

install(TARGETS sdwan_windows_helper RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
