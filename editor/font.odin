package editor

import "core:mem"
import "core:os"
import stbtt "vendor:stb/truetype"

Font_Handle :: struct {
	id: u16,
	data: []u8,
	info: stbtt.fontinfo,
	ascent: f32,
	descent: f32,
	line_gap: f32,
	scale: f32,
	pixel_size: f32,
	allocator: mem.Allocator,
}

Rasterized_Glyph :: struct {
	bitmap: []u8,
	width: int,
	height: int,
	bearing_x: f32,
	bearing_y: f32,
	advance_x: f32,
}

load_font :: proc(
	path: string,
	pixel_size: f32,
	allocator: mem.Allocator = context.allocator,
) -> (font: Font_Handle, ok: bool) {
	data, read_ok := os.read_entire_file(path, allocator)
	if !read_ok {
		return font, false
	}

	font.data = data
	font.allocator = allocator
	font.pixel_size = pixel_size

	if !stbtt.InitFont(&font.info, raw_data(data), 0) {
		delete(data, allocator)
		return font, false
	}

	font.scale = stbtt.ScaleForPixelHeight(&font.info, pixel_size)

	ascent, descent, line_gap: i32
	stbtt.GetFontVMetrics(&font.info, &ascent, &descent, &line_gap)
	font.ascent = f32(ascent) * font.scale
	font.descent = f32(descent) * font.scale
	font.line_gap = f32(line_gap) * gont.scale

	return font, true
}

destroy_font :: proc(font: ^Font_Handle) {
	if font.data != nil {
		delete(font.data, font.allocator)
		font.data = nil
	}
}

rasterize_glyph :: proc(
	font: ^Font_Handle,
	codepoint: rune,
) -> (glyph: Rasterized_Glyph, ok: bool) {
	glyph_index := stbtt.FindGlyphIndex(&font.info, codepoint)
	if glyph_index == 0 && codepoint != 0 {
		glyph_index = stbtt.FindGlyphIndex(&font.info, ' ')
	}

	w, h, off_x, off_y: i32
	bitmap_ptr := stbtt.GetGlyphBitmap(
		&font.info, font.scale, font.scale,
		glyph_index, &w, &h, &off_x, &off_y,
	)

	if bitmap_ptr == nil || w == 0 || h == 0 {
		// Whitespace glyph -- no bitmap, but has advance
		advance, lsb: i32
		stbtt.GetGlyphHMetrics(&font.info, glyph_index, &advance, &lsb)
		glyph.advance_x = f32(advance) * font.scale
		glyph.width = 0
		glyph.height = 0
		return glyph, true
	}

	size := int(w * h)
	glyph.bitmap = make([]u8, size, font.allocator)
	mem.copy(raw_data(glyph.bitmap), bitmap_ptr, size)
	stbtt.FreeBitmap(bitmap_ptr, nil)

	advance, lsb: i32
	stbtt.GetGlyphHMetrics(&font.info, glyph_index, &advance, &lsb)

	glyph.width = int(w)
	glyph.height = int(h)
	glyph.bearing_x = f32(off_x)
	glyph.bearing_y = f32(off_y)
	glyph.advance_x = f32(advance) * font.scale

	return glyph, true
}

get_kerning :: proc(font: ^Font_Handle, left, right: rune) -> f32 {
	kern := stbtt.GetCodepointKernAdvance(
		&font.info, left, right,
	)
	return f32(kern) * font.scale
}
