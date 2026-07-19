#pragma once

#include <stdint.h>
#include <stddef.h>

using float32 = float;
using float64 = double;
using u8 = uint8_t;
using u32 = uint32_t;
using u64 = uint64_t;
using i32 = int32_t;
using i64 = int64_t;

struct FileHandle
{
	void* native_handle = (void*)-1;

	bool is_valid() const {
		return native_handle != (void*)-1 && native_handle != nullptr;
	}
};

struct WindowHandle 
{
	void* native_handle = nullptr;

	bool is_valid() const { return native_handle != nullptr; } 
};

#if defined(PLATFORM_WINDOWS)
	typedef WindowHandle PlatformWindow;
#elif defined(PLATFORM_MACOS)
	typedef WindowHandle PlatformWindow;
#else
	typedef WindowHandle PlatformWindow;
#endif

struct IColor4 {
	IColor4() : r{0}, g{0}, b{0}, a{1} {}
	IColor4(u8 linear) : r{linear}, g{linear}, b{linear}, a{linear} {}
	IColor4(u8 r, u8 g, u8 b, u8 a) :
		r{r}, g{g}, b{b}, a{a} {}
	/// Do not provide as a string
	IColor4(u32 hex) {
        r = (hex >> 24) & 0xFF; // R
        g = (hex >> 16) & 0xFF; // G
        b = (hex >> 8) & 0xFF;  // B
        a = hex & 0xFF;         // A
    }

	u8 r;
	u8 g;
	u8 b;
	u8 a;
};

struct IVec2 
{
	float32 x;
	float32 y;
};

struct IVec3 
{
	float32 x;
	float32 y;
	float32 z;
};