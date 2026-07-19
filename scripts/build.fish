#!/usr/bin/env fish

set PROJ_NAME "rune"
set SRC_DIR "src"
set BUILD_DIR "build"
set OS (uname -s)

if pkg-config --exists freetype2
    set FREETYPE_CFLAGS (pkg-config --cflags freetype2 | string split " ")
    set FREETYPE_LIBS (pkg-config --libs freetype2 | string split " ")
else
    echo "Error: freetype2 not found via pkg-config"
    exit 1
end

if string match -q "*Darwin*" $OS
    set CXX "clang++"
    set PLATFORM_DEFS -DPLATFORM_MACOS
    set PLATFORM_SRC "$SRC_DIR/macos_entry.mm" "$SRC_DIR/linux_filesystem.cpp" "$SRC_DIR/macos_renderer.mm"
    set PLATFORM_LINKER_FLAGS -framework Cocoa -framework QuartzCore -framework AppKit -framework Metal
    echo "Platform: macOS"
else
    set CXX "clang++"
    set PLATFORM_DEFS -DPLATFORM_LINUX
    set PLATFORM_SRC "$SRC_DIR/linux_entry.cpp"
    set PLATFORM_LINKER_FLAGS -ldl -lpthread
    echo "Platform: Linux"
end

set BUILD_MODE "debug"
set MODE_FLAGS -g -O0 -DDEBUG
if contains -- --release $argv
    set BUILD_MODE "release"
    set MODE_FLAGS -O3 -DNDEBUG
end

set SHARED_SRCS (find $SRC_DIR -type f -name "*.cpp" \
    ! -name "windows_*" \
    ! -name "linux_*" \
    ! -name "macos_*")

set ALL_SRCS $SHARED_SRCS $PLATFORM_SRC

# 4. Build
set CXX_FLAGS -std=c++20 -Wall -Wextra $MODE_FLAGS $PLATFORM_DEFS -I./src $FREETYPE_CFLAGS

if not test -d $BUILD_DIR; mkdir -p $BUILD_DIR; end



echo "Compiling $PROJ_NAME ($BUILD_MODE) with $CXX..."

# It is better to put linker flags and libs at the end of the command
$CXX $CXX_FLAGS $ALL_SRCS $PLATFORM_LINKER_FLAGS $FREETYPE_LIBS -o $BUILD_DIR/$PROJ_NAME

if test $status -eq 0
    echo "Build Successful: $BUILD_DIR/$PROJ_NAME"
else
    echo "Build Failed"
    exit 1
end
