cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Настройка путей к библиотекам
set(LIBRARY_PATHS
  "/usr/lib/x86_64-linux-gnu"
  "/usr/local/lib/x86_64-linux-gnu"
)

# Добавляем пути к библиотекам
link_directories(${LIBRARY_PATHS})

# Добавляем зависимости с явным указанием путей
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# Добавляем явные зависимости на библиотеки
target_link_libraries(${BINARY_NAME} PRIVATE
  -Wl,-rpath,/usr/lib/x86_64-linux-gnu
  -Wl,-rpath,/usr/local/lib/x86_64-linux-gnu
)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Устанавливаем приоритет путей к библиотекам
set_target_properties(${BINARY_NAME} PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "/usr/lib/x86_64-linux-gnu;/usr/local/lib/x86_64-linux-gnu"
)
