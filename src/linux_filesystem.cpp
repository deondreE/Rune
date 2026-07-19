#include "filesystem.hpp"
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>

FileHandle FileSystem::open_file(const char* path) {
    FileHandle handle;
    // open() returns an int (file descriptor)
    int fd = open(path, O_RDONLY);
    handle.native_handle = (void*)(intptr_t)fd;
    return handle;
}

void FileSystem::close_file(FileHandle& handle) {
    if (handle.is_valid()) {
        int fd = (int)(intptr_t)handle.native_handle;
        close(fd);
        handle.native_handle = (void*)-1;
    }
}

size_t FileSystem::read_file(FileHandle handle, void* buffer, size_t size) {
    if (!handle.is_valid()) return 0;
    int fd = (int)(intptr_t)handle.native_handle;
    ssize_t bytes_read = read(fd, buffer, size);
    return (bytes_read < 0) ? 0 : (size_t)bytes_read;
}

u64 FileSystem::get_file_size(FileHandle handle) {
    if (!handle.is_valid()) return 0;
    int fd = (int)(intptr_t)handle.native_handle;
    struct stat st;
    if (fstat(fd, &st) == 0) {
        return (u64)st.st_size;
    }
    return 0;
}

static char g_root_path_buffer[4] = "/";

const char* FileSystem::get_file_root(FileHandle handle)
{
    if (!handle.is_valid()) return nullptr;
    return g_root_path_buffer;
}

std::string FileSystem::get_absolute_path(const char* relative)
{
    char actualpath[PATH_MAX];
    char* ptr = realpath(relative, actualpath);
    return ptr ? std::string(ptr) : std::string(relative);
}
