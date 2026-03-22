package editor

import "core:fmt"
import "core:mem"

ATLAS_SIZE :: 1024

Glyph_Key :: struct {
	codepoint: rune,
}

Glyph_Info :: struct {
	uv_min:    [2]f32,
	uv_max:    [2]f32,
	size:      [2]f32,
	bearing:   [2]f32,
	advance_x: f32,
}

Atlas_Shelf :: struct {
	y:      u32,
	height: u32,
	x_used: u32,
}

Glyph_Atlas :: struct {
	image:      GPU_Image,
	width:      u32,
	height:     u32,
	shelves:    [dynamic]Atlas_Shelf,
	glyphs:     map[Glyph_Key]Glyph_Info,
	staging:    []u8,
	dirty:      bool,
	dirty_rect: [4]u32,
	allocator:  mem.Allocator,
}

init_glyph_atlas :: proc(
	ctx: ^Render_Context,
	allocator: mem.Allocator = context.Allocator,
) -> (
	atlas: Glyph_Atlas,
	ok: bool,
) {
	atlas.width = ATLAS_SIZE
	atlas.height = ATLAS_SIZE
	atlas.allocator = allocator
	atlas.staging = make([]u8, ATLAS_SIZE * ATLAS_SIZE, allocator)
	atlas.glyphs = make(map[Glyph_Key]Glyph_Info, 256, allocator)
	atlas.shelves = make([dynamic]Atlas_Shelf, allocator)

	mem.zero_slice(atlas.staging)

	atlas.image, ok := create_gpu_image(ctx, ATLAS_SIZE, ATLAS_SIZE, .R8_UNORM)
	if !ok {
		return atlas, false
	}

	return atlas, true
}

destory_glyph_atlas :: proc(ctx: ^Render_Context, atlas: ^Glyph_Atlas) {
	destroy_gpu_image(ctx, &atlas.image)
	delete(atlas.staging, atlas.allocator)
	delete(atlas.glyphs)
	delete(atlas.shelves)
}

get_glyph :: proc(atlas: ^Glyph_Atlas, font: ^Font_Handle, codepoint: rune) -> Glyph_Info {
	key := Glyph_Key{codepoint}

	if info, found := atlas.glyphs[key]; found {
		return info
	}

	return cache_glyph(atlas, font, codepoint)
}

flush_atlas :: proc(ctx: ^Render_Context, atlas: ^Glyph_Atlas) {
	if !atlas.dirty {
		return
	}

	rx := atlas.dirty_rect[0]
	ry := atlas.dirty_rect[1]
	rw := atlas.dirty_rect[2] - atlas.dirty_rect[0]
	rh := atlas.dirty_rect[3] - atlas.dirty_rect[1]

	if rw == 0 || rh == 0 {
		atlas.dirty = false
		return
	}

	// Extract the dirty sub-region into a contiguous buffer
	region_pixels := make([]u8, rw * rh, atlas.allocator)
	defer delete(region_pixels, atlas.allocator)

	for row in 0 ..< rh {
		src_offset := (ry + row) * atlas.width + rx
		dst_offset := row * rw
		copy(region_pixels[dst_offset:dst_offset + rw], atlas.staging[src_offset:src_offset + rw])
	}

	upload_image_data(ctx, &atlas.image, region_pixels, rx, ry, rw, rh)

	atlas.dirty = false
	atlas.dirty_rect = {0, 0, 0, 0}
}

precache_ascii :: proc(atlas: ^Glyph_Atlas, font: ^Font_Handle) {
	for cp in rune(32) ..= rune(126) {
		get_glyph(atlas, font, cp)
	}
}

@(private = "file")
cache_glyph :: proc(atlas: ^Glyph_Atlas, font: ^Font_Handle, codepoint: rune) -> Glyph_Info {
	key := Glyph_Key{codepoint}

	rast, ok := rasterize_glyph(font, codepoint)
	if !ok {
		info := Glyph_Info{}
		atlas.glyphs[key] = info
		return info
	}
	defer if rast.bitmap != nil {
		delete(rast.bitmap, font.allocator)
	}

	info := Glyph_Info {
		size      = {f32(rast.width), f32(rast.height)},
		bearing   = {rast.bearing_x, rast.bearing_y},
		advance_x = rast.advance_x,
	}

	// If glyph has a bitmap, pack it into the atlas
	if rast.width > 0 && rast.height > 0 {
		region, packed := shelf_pack(atlas, u32(rast.width), u32(rast.height))
		if packed {
			for row in 0 ..< u32(rast.height) {
				dst_offset := (region.y + row) * atlas.width + region.x
				src_offset := row * u32(rast.width)
				copy(
					atlas.staging[dst_offset:dst_offset + u32(rast.width)],
					rast.bitmap[src_offset:src_offset + u32(rast.width)],
				)
			}

			// Update dirty rect
			expand_dirty_rect(
				atlas,
				region.x,
				region.y,
				region.x + u32(rast.width),
				region.y + u32(rast.height),
			)
			atlas.dirty = true

			// Compute UVs
			inv_w := 1.0 / f32(atlas.width)
			inv_h := 1.0 / f32(atlas.height)
			info.uv_min = {f32(region.x) * inv_w, f32(region.y) * inv_h}
			info.uv_max = {
				f32(region.x + u32(rast.width)) * inv_w,
				f32(region.y + u32(rast.height)) * inv_h,
			}
		}
	}

	atlas.glyphs[key] = info
	return info
}

Atlas_Region :: struct {
	x, y: u32,
}

@(private = "file")
shelf_pack :: proc(atlas: ^Glyph_Atlas, w, h: u32) -> (region: Atlas_Region, ok: bool) {
	padding: u32 = 1

	for &shelf in atlas.shelves {
		if h <= shelf.height && shelf.x_used + w + padding <= atlas.width {
			region = Atlas_Region{shelf.x_used, shelf.y}
			shelf.x_used += w + padding
			return region, true
		}
	}

	y_start: u32 = 0
	if len(atlas.shelves) > 0 {
		last := atlas.shelves[len(atlas.shelves) - 1]
		y_start = last.y + last.height + padding
	}

	if y_start + h > atlas.height {
		fmt.eprintln("Atlas full!")
		return region, false
	}

	append(&atlas.shelves, Atlas_Shelf{y = y_start, height = h, x_used = w + padding})

	return Atlas_Region{0, y_start}, true
}

@(private = "file")
expand_dirty_rect :: proc(atlas: ^Glyph_Atlas, x0, y0, x1, y1: u32) {
	if !atlas.dirty {
		atlas.dirty_rect = {x0, y0, x1, y1}
	} else {
		atlas.dirty_rect[0] = min(atlas.dirty_rect[0], x0)
		atlas.dirty_rect[1] = min(atlas.dirty_rect[1], y0)
		atlas.dirty_rect[2] = max(atlas.dirty_rect[2], x1)
		atlas.dirty_rect[3] = max(atlas.dirty_rect[3], y1)
	}
}
