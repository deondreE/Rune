#include "filesystem.hpp"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <vector>

FileHandle FileSystem::open_file(const char* path) {
	FileHandle handle;
	HANDLE hFile = CreateFileA(
		path, GENERIC_READ, FILE_SHARE_READ, NULL,
		OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
	);

	if (hFile == INVALID_HANDLE_VALUE) {
		handle.native_handle = (void*)-1;
	} else {
		handle.native_handle = (void*)hFile;
	}
	return handle;
}

void FileSystem::close_file(FileHandle& handle) {
    if (handle.is_valid()) {
        CloseHandle((HANDLE)handle.native_handle);
        handle.native_handle = (void*)-1;
    }
}

size_t FileSystem::read_file(FileHandle handle, void* buffer, size_t size) {
    if (!handle.is_valid()) return 0;
    DWORD bytesRead = 0;
    if (ReadFile((HANDLE)handle.native_handle, buffer, (DWORD)size, &bytesRead, NULL)) {
        return (size_t)bytesRead;
    }
    return 0;
}

u64 FileSystem::get_file_size(FileHandle handle) {
    if (!handle.is_valid()) return 0;
    LARGE_INTEGER size;
    if (GetFileSizeEx((HANDLE)handle.native_handle, &size)) {
        return (u64)size.QuadPart;
    }
    return 0;
}

static char g_win_root_buffer[4] = {0};

const char* FileSystem::get_file_root(FileHandle handle)
{
    if (!handle.is_valid()) return nullptr;

     char path[MAX_PATH];
    // GetFinalPathNameByHandleA returns the path with the \\?\ prefix
    DWORD length = GetFinalPathNameByHandleA((HANDLE)handle.native_handle, path, MAX_PATH, FILE_NAME_NORMALIZED);

    if (length > 0 && length < MAX_PATH) {
        // Path usually looks like "\\?\C:\Users\..."
        // We find the index of the colon
        for(int i = 0; i < (int)length; ++i) {
            if (path[i] == ':') {
                g_win_root_buffer[0] = path[i-1]; // The Drive Letter
                g_win_root_buffer[1] = ':';
                g_win_root_buffer[2] = '\\';
                g_win_root_buffer[3] = '\0';
                return g_win_root_buffer;
            }
        }
    }
    
    return nullptr;
}

std::string FileSystem::get_absolute_path(const char* relative) {
    char absolute[MAX_PATH];
    GetFullPathNameA(relative, MAX_PATH, absolute, NULL);
    return std::string(absolute);
}
