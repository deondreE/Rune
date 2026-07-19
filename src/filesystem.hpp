#pragma once
#include "shared.hpp"

#include <string>

/// Refers to the handles required to open files within the filesystem.
class FileSystem
{
public:
	static FileHandle open_file(const char* path);

	static void close_file(FileHandle& handle);

	static size_t read_file(FileHandle handle, void* buffer, size_t size);

	static u64 get_file_size(FileHandle handle);

	static const char* get_file_root(FileHandle handle);

	static std::string get_absolute_path(const char* relative);
};