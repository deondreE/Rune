package editor

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

CACHE_CAPACITY :: 4096
GLYPH_ATLAS_SIZE :: 1024
MAX_GLYPHS :: 256

Glyph_Info :: struct {
	texture_x: i32,
	texture_y: i32,
	width:     i32,
	height:    i32,
	advance:   i32,
}

Glyph_Atlas :: struct {
	texture: ^sdl.Texture,
	glyphs:  [256]Glyph_Info,
	ready:   bool,
}

Text_Entry :: struct {
	hash:      u64,
	text:      string,
	texture:   ^sdl.Texture,
	width:     f32,
	height:    f32,
	last_used: u64,
}

Text_Renderer :: struct {
	font:            ^ttf.Font,
	font_size:       f32,
	line_height:     i32,
	char_width:      f32,
	color:           sdl.Color,
	text_cache:      map[u64]Text_Entry,
	cache_allocator: mem.Allocator,
	frame_counter:   u64,
	glyph_atlas:     Glyph_Atlas,
	renderer:        ^sdl.Renderer,
}

init_text_renderer :: proc(
	font_path: string,
	font_size: f32,
	renderer: ^sdl.Renderer,
	allocator: mem.Allocator = context.allocator,
) -> (
	Text_Renderer,
	bool,
) {
	if ttf.WasInit() == 0 {
		if !ttf.Init() {
			fmt.printf("Failed to init SDL_ttf: %s\n")
			return {}, false
		}
	}

	font: ^ttf.Font = nil
	font_path_cstr := strings.clone_to_cstring(font_path, allocator)
	defer delete(font_path_cstr, allocator)

	font = ttf.OpenFont(font_path_cstr, font_size)

	if font == nil {
		fallback_fonts := []string {
			"C:/Windows/Fonts/consola.ttf",
			"C:/Windows/Fonts/cour.ttf", // Courier New
			"C:/Windows/Fonts/lucon.ttf", // Lucida Console
			"C:/Windows/Fonts/calibri.ttf", // Non-monospace fallback
			"C:/Windows/Fonts/arial.ttf", // Last resort
		}

		for fallback_path in fallback_fonts {
			fallback_cstr := strings.clone_to_cstring(fallback_path, allocator)
			defer delete(fallback_cstr, allocator)

			font = ttf.OpenFont(fallback_cstr, font_size)
			if font != nil {
				fmt.printf("Using fallback font: %s\n", fallback_path)
				break
			}
		}

		if font == nil {
			fmt.printf("All font loading attempts failed. Text rendering will be minimal.\n")
			text_renderer := Text_Renderer {
				font        = nil,
				font_size   = font_size,
				line_height = i32(font_size * 1.2),
				char_width  = font_size * 0.6,
				color       = {255, 255, 255, 255},
			}
			return text_renderer, true
		}
	}
	fmt.printf("Successfully loaded font: %s\n", font_path)

	char_width: f32
	line_height := ttf.GetFontHeight(font)
	char_width_measured: i32
	if ttf.GetStringSize(
		font,
		strings.clone_to_cstring("M", allocator),
		1,
		&char_width_measured,
		nil,
	) {
		char_width = f32(char_width_measured)
	} else {
		char_width = font_size * 0.6
	}

	cache_arena := context.allocator
	text_cache := make(map[u64]Text_Entry, CACHE_CAPACITY, cache_arena)

	text_renderer := Text_Renderer {
		font            = font,
		font_size       = font_size,
		line_height     = line_height,
		char_width      = char_width,
		color           = {255, 255, 255, 255},
		text_cache      = text_cache,
		cache_allocator = cache_arena,
		frame_counter   = 0,
		renderer        = renderer,
	}

	build_glyph_atlas(&text_renderer)

	return text_renderer, true
}

build_glyph_atlas :: proc(tr: ^Text_Renderer) {
	if tr.font == nil || tr.renderer == nil {
		return
	}

	atlas_surface := sdl.CreateSurface(GLYPH_ATLAS_SIZE, GLYPH_ATLAS_SIZE, .RGBA8888)
	if atlas_surface == nil {
		fmt.printf("Failed to create glyph atlas surface\n")
		return
	}
	defer sdl.DestroySurface(atlas_surface)

	sdl.FillSurfaceRect(atlas_surface, nil, sdl.MapSurfaceRGBA(atlas_surface, 0, 0, 0, 0))

	current_x: i32 = 0
	current_y: i32 = 0
	row_height: i32 = 0

	for i: i32 = 32; i < 127; i += 1 {
		char_str := [2]u8{u8(i), 0}

		glyph_surface := ttf.RenderGlyph_Blended(tr.font, u32(i), {255, 255, 255, 255})
		if glyph_surface == nil {
			continue
		}

		glyph_w := glyph_surface.w
		glyph_h := glyph_surface.h

		// Check if we need to move to next row
		if current_x + glyph_w > GLYPH_ATLAS_SIZE {
			current_x = 0
			current_y += row_height
			row_height = 0
		}

		// Check if we have space
		if current_y + glyph_h > GLYPH_ATLAS_SIZE {
			sdl.DestroySurface(glyph_surface)
			break
		}

		// Blit glyph onto atlas
		src_rect := sdl.Rect{0, 0, glyph_w, glyph_h}
		dst_rect := sdl.Rect{current_x, current_y, glyph_w, glyph_h}
		sdl.BlitSurface(glyph_surface, &src_rect, atlas_surface, &dst_rect)

		advance: i32
		ttf.GetGlyphMetrics(tr.font, u32(i), nil, nil, nil, nil, &advance)

		tr.glyph_atlas.glyphs[i] = Glyph_Info {
			texture_x = current_x,
			texture_y = current_y,
			width     = glyph_w,
			height    = glyph_h,
			advance   = advance,
		}

		current_x += glyph_w + 2
		row_height = max(row_height, glyph_h)

		sdl.DestroySurface(glyph_surface)
	}

	tr.glyph_atlas.texture = sdl.CreateTextureFromSurface(tr.renderer, atlas_surface)
	if tr.glyph_atlas.texture == nil {
		fmt.printf("Failed to create glyph atlas texture\n")
		return
	}

	sdl.SetTextureBlendMode(tr.glyph_atlas.texture, {.BLEND})
	tr.glyph_atlas.ready = true
	fmt.printf("Glyph atlas built successfully\n")
}

destroy_text_renderer :: proc(tr: ^Text_Renderer) {
	if tr.font != nil {
		ttf.CloseFont(tr.font)
		tr.font = nil
	}

	for _, entry in tr.text_cache {
		if entry.texture != nil {
			sdl.DestroyTexture(entry.texture)
		}
	}
	delete(tr.text_cache)

	if tr.glyph_atlas.texture != nil {
		sdl.DestroyTexture(tr.glyph_atlas.texture)
	}
}

set_text_color :: proc(tr: ^Text_Renderer, color: sdl.Color) {
	tr.color = color

	if tr.glyph_atlas.texture != nil {
		sdl.SetTextureColorMod(tr.glyph_atlas.texture, color.r, color.g, color.b)
		sdl.SetTextureAlphaMod(tr.glyph_atlas.texture, color.a)
	}
}

@(private)
hash_string :: proc(s: string) -> u64 {
	prime :: 1099511628211
	offset_basis :: 14695981039346656037
	hash: u64 = offset_basis
	for b in s {
		hash = hash ~ u64(b)
		hash = hash * prime
	}
	return hash
}

@(private)
hash_string_color :: proc(s: string, color: sdl.Color) -> u64 {
	h := hash_string(s)
	h = h ~ (u64(color.r) << 24 | u64(color.g) << 16 | u64(color.b) << 8 | u64(color.a))
	return h
}

render_text_fast :: proc(
	tr: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	text: string,
	x, y: f32,
	color: sdl.Color,
) -> bool {
	if !tr.glyph_atlas.ready || len(text) == 0 {
		return false
	}

	if !is_valid_text(text) {
		return false
	}

	sdl.SetTextureColorMod(tr.glyph_atlas.texture, color.r, color.g, color.b)
	sdl.SetTextureAlphaMod(tr.glyph_atlas.texture, color.a)

	current_x := x

	for char in text {
		if char >= 32 && char < 127 {
			glyph := tr.glyph_atlas.glyphs[char]

			if glyph.width > 0 && glyph.height > 0 {
				src_rect := sdl.FRect {
					x = f32(glyph.texture_x),
					y = f32(glyph.texture_y),
					w = f32(glyph.width),
					h = f32(glyph.height),
				}

				dst_rect := sdl.FRect {
					x = current_x,
					y = y,
					w = f32(glyph.width),
					h = f32(glyph.height),
				}

				sdl.RenderTexture(renderer, tr.glyph_atlas.texture, &src_rect, &dst_rect)
			}

			current_x += f32(glyph.advance)
		} else if char == '\t' {
			current_x += tr.char_width * 4
		} else {
			current_x += tr.char_width
		}
	}

	return true
}

is_valid_text :: proc(text: string) -> bool {
	if len(text) == 0 {
		return true
	}

	// Check for null bytes which indicate corrupted data
	for b in text {
		if b == 0 {
			return false
		}
	}

	// Validate UTF-8
	valid := utf8.valid_string(text)
	return valid
}

get_cached_text_texture :: proc(
	tr: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	text: string,
	color: sdl.Color,
) -> (
	^sdl.Texture,
	f32,
	f32,
	bool,
) {
	if tr.font == nil || len(text) == 0 {
		return nil, 0, 0, false
	}

	text_hash := hash_string_color(text, color)

	if entry, ok := tr.text_cache[text_hash]; ok {
		entry.last_used = tr.frame_counter
		tr.text_cache[text_hash] = entry
		return entry.texture, entry.width, entry.height, true
	}

	text_cstr := strings.clone_to_cstring(text, tr.cache_allocator)
	surface := ttf.RenderText_Blended(tr.font, text_cstr, len(text_cstr), color)
	if surface == nil {
		delete(text_cstr, tr.cache_allocator)
		return nil, 0, 0, false
	}
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		return nil, 0, 0, false
	}

	w, h: f32
	if !sdl.GetTextureSize(texture, &w, &h) {
		sdl.DestroyTexture(texture)
		return nil, 0, 0, false
	}

	if len(tr.text_cache) >= CACHE_CAPACITY {
		lru_hash: u64
		min_last_used: u64 = 0xFFFFFFFFFFFFFFFF
		is_first := true

		for current_hash, entry in tr.text_cache {
			if is_first || entry.last_used < min_last_used {
				min_last_used = entry.last_used
				lru_hash = current_hash
				is_first = false
			}
		}

		if old_entry, ok := tr.text_cache[lru_hash]; ok {
			sdl.DestroyTexture(old_entry.texture)
		}
	}

	cloned_text := strings.clone(text, tr.cache_allocator)
	tr.text_cache[text_hash] = Text_Entry {
		hash      = text_hash,
		text      = cloned_text,
		texture   = texture,
		width     = w,
		height    = h,
		last_used = tr.frame_counter,
	}

	return texture, w, h, true
}

render_text :: proc(
	tr: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	text: string,
	x, y: f32,
	allocator: mem.Allocator = context.allocator,
	color: sdl.Color,
) -> bool {
	// Use fast atlas rendering for ASCII text
	is_ascii := true
	for char in text {
		if char < 32 || char >= 127 {
			is_ascii = false
			break
		}
	}

	if is_ascii && tr.glyph_atlas.ready {
		return render_text_fast(tr, renderer, text, x, y, color)
	}

	// Fallback to texture rendering for non-ASCII
	if tr.font == nil || len(text) == 0 {
		return false
	}

	text_cstr := strings.clone_to_cstring(text, allocator)
	defer delete(text_cstr, allocator)

	surface := ttf.RenderText_Blended(tr.font, text_cstr, len(text_cstr), color)
	if surface == nil {
		return false
	}
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		return false
	}
	defer sdl.DestroyTexture(texture)

	w, h: f32
	if !sdl.GetTextureSize(texture, &w, &h) {
		return false
	}

	dst_rect := sdl.FRect {
		x = x,
		y = y,
		w = w,
		h = h,
	}

	if !sdl.RenderTexture(renderer, texture, nil, &dst_rect) {
		return false
	}

	return true
}

// Optimized line rendering - only renders visible lines
render_text_lines :: proc(
	tr: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	text: string,
	start_x, start_y: f32,
	scroll_x, scroll_y: int,
	viewport_height: f32,
	allocator: mem.Allocator = context.allocator,
) {
	if len(text) == 0 {
		return
	}

	tr.frame_counter += 1

	// Calculate visible line range
	first_visible_line := max(0, scroll_y / int(tr.line_height))
	last_visible_line := (scroll_y + int(viewport_height)) / int(tr.line_height) + 1

	lines := strings.split_lines(text, allocator)
	defer delete(lines, allocator)

	// Only process visible lines
	for line_idx := first_visible_line;
	    line_idx < min(last_visible_line, len(lines));
	    line_idx += 1 {
		line := lines[line_idx]
		current_y := start_y + f32(line_idx * int(tr.line_height)) - f32(scroll_y)

		// Skip if line is outside viewport
		line_top := current_y
		line_bottom := current_y + f32(tr.line_height)
		if line_bottom < 0 || line_top > viewport_height {
			continue
		}

		current_x := start_x - f32(scroll_x)

		if len(line) > 0 {
			render_text_fast(tr, renderer, line, current_x, current_y, tr.color)
		}
	}
}

render_text_lines_batched :: proc(
	tr: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	lines: []string,
	start_x, start_y: f32,
	scroll_x, scroll_y: int,
	viewport_height: f32,
	color: sdl.Color,
) {
	if len(lines) == 0 || !tr.glyph_atlas.ready {
		return
	}

	tr.frame_counter += 1

	// Calculate visible line range
	first_visible_line := max(0, scroll_y / int(tr.line_height))
	last_visible_line := min(
		(scroll_y + int(viewport_height)) / int(tr.line_height) + 1,
		len(lines),
	)

	// Set color once for entire batch
	sdl.SetTextureColorMod(tr.glyph_atlas.texture, color.r, color.g, color.b)
	sdl.SetTextureAlphaMod(tr.glyph_atlas.texture, color.a)

	// Render only visible lines
	for line_idx := first_visible_line; line_idx < last_visible_line; line_idx += 1 {
		line := lines[line_idx]
		current_y := start_y + f32(line_idx * int(tr.line_height)) - f32(scroll_y)

		if len(line) == 0 {
			continue
		}

		current_x := start_x - f32(scroll_x)

		// Render each character from atlas
		for char in line {
			if char >= 32 && char < 127 {
				glyph := tr.glyph_atlas.glyphs[char]

				if glyph.width > 0 && glyph.height > 0 {
					src_rect := sdl.FRect {
						x = f32(glyph.texture_x),
						y = f32(glyph.texture_y),
						w = f32(glyph.width),
						h = f32(glyph.height),
					}

					dst_rect := sdl.FRect {
						x = current_x,
						y = current_y,
						w = f32(glyph.width),
						h = f32(glyph.height),
					}

					sdl.RenderTexture(renderer, tr.glyph_atlas.texture, &src_rect, &dst_rect)
				}

				current_x += f32(glyph.advance)
			} else if char == '\t' {
				current_x += tr.char_width * 4
			} else {
				current_x += tr.char_width
			}
		}
	}
}

measure_text_width :: proc(tr: ^Text_Renderer, text: string) -> f32 {
	if tr.font == nil || len(text) == 0 {
		return 0
	}

	// Fast measurement for ASCII using atlas
	if tr.glyph_atlas.ready {
		width: f32 = 0
		for char in text {
			if char >= 32 && char < 127 {
				width += f32(tr.glyph_atlas.glyphs[char].advance)
			} else if char == '\t' {
				width += tr.char_width * 4
			} else {
				width += tr.char_width
			}
		}
		return width
	}

	text_cstr := strings.clone_to_cstring(text, context.allocator)
	defer delete(text_cstr, context.allocator)

	w, h: i32
	if ttf.GetStringSize(tr.font, text_cstr, len(text_cstr), &w, &h) {
		return f32(w)
	}

	return 0
}
