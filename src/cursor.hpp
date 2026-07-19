#pragma once

#include "shared.hpp"

struct Cursor
{
	size_t buffer_index = 0;
	u32 line = 0;
	u32 column = 0;

	IVec2 visual_pixel_pos;

	u8 tab_width = 4;
};