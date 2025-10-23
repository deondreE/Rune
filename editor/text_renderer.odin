package editor

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

CACHE_CAPACITY :: 4096

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
}

init_text_renderer :: proc(
	font_path: string,
	font_size: f32,
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
			"C:/Windows/Fonts/consola.ttf", // Consolas
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
				line_height = i32(font_size * 1.2), // Approximate line height
				char_width  = font_size * 0.6, // Approximate char width for monospace
				color       = {255, 255, 255, 255},
				// No cache needed if no font
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

	// Initialize the cache allocator. An arena is excellent for this.
	cache_arena := context.allocator
	text_cache := make(map[u64]Text_Entry, CACHE_CAPACITY, cache_arena)

	text_renderer := Text_Renderer {
		font            = font,
		font_size       = font_size,
		line_height     = line_height,
		char_width      = char_width,
		color           = {255, 255, 255, 255}, // Default to white
		text_cache      = text_cache,
		cache_allocator = cache_arena,
		frame_counter   = 0,
	}

	return text_renderer, true
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
}

set_text_color :: proc(tr: ^Text_Renderer, color: sdl.Color) {
	tr.color = color
}

@(private)
hash_string :: proc(s: string) -> u64 {
	prime :: 1099511628211
	offset_basis :: 14695981039346656037
	hash: u64 = offset_basis
	for b in s {
		hash = hash & u64(b)
		hash = hash * prime
	}
	return hash
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

	text_hash := hash_string(text)

	if entry, ok := tr.text_cache[text_hash]; ok {
		entry.last_used = tr.frame_counter
		tr.text_cache[text_hash] = entry
		return entry.texture, entry.width, entry.height, true
	}

	text_cstr := strings.clone_to_cstring(text, tr.cache_allocator) // Use cache allocator
	surface := ttf.RenderText_Blended(tr.font, text_cstr, len(text_cstr), color)
	if surface == nil {
		fmt.printf("Failed to create text surface for '%s': %s\n", text)
		delete(text_cstr, tr.cache_allocator)
		return nil, 0, 0, false
	}
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		fmt.printf("Failed to create text texture for '%s': %s\n", text, sdl.GetError())
		return nil, 0, 0, false
	}

	w, h: f32
	if !sdl.GetTextureSize(texture, &w, &h) {
		fmt.printf("Failed to get texture size for '%s': %s\n", text, sdl.GetError())
		sdl.DestroyTexture(texture)
		return nil, 0, 0, false
	}

	if len(tr.text_cache) >= CACHE_CAPACITY {
		lru_hash: u64
		min_last_used: u64 = 0xFFFFFFFFFFFFFFFF // Max u64 value
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
			// delete(tr.text_cache, lru_hash)
		}
	}

	cloned_text := strings.clone(text, tr.cache_allocator)
	tr.text_cache[text_hash] = Text_Entry {
		hash      = text_hash,
		text      = cloned_text, // Use the cloned string
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
) -> bool {
	if tr.font == nil || len(text) == 0 {
		return false
	}

	text_cstr := strings.clone_to_cstring(text, allocator)
	defer delete(text_cstr, allocator)

	surface := ttf.RenderText_Blended(tr.font, text_cstr, len(text_cstr), tr.color)
	if surface == nil {
		fmt.printf("Failed to create text surface:\n")
		return false
	}
	defer sdl.DestroySurface(surface)

	// Create texture from surface
	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		fmt.printf("Failed to create text texture:\n")
		return false
	}
	defer sdl.DestroyTexture(texture)

	// Get texture dimensions
	w, h: f32
	if !sdl.GetTextureSize(texture, &w, &h) {
		fmt.printf("Failed to get texture size:\n")
		return false
	}

	// Render the texture
	dst_rect := sdl.FRect {
		x = x,
		y = y,
		w = w,
		h = h,
	}

	if !sdl.RenderTexture(renderer, texture, nil, &dst_rect) {
		fmt.printf("Failed to render text: \n")
		return false
	}

	return true
}

render_text_lines :: proc(
	tr: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	text: string,
	start_x, start_y: f32,
	scroll_x, scroll_y: int,
	allocator: mem.Allocator = context.allocator,
) {
	if len(text) == 0 {
		return
	}

	tr.frame_counter += 1

	lines := strings.split_lines(text, allocator)
	defer delete(lines, allocator)

	for line, line_idx in lines {
		current_y := start_y + f32(line_idx * int(tr.line_height)) - f32(scroll_y)

		line_top := current_y
		line_bottom := current_y + f32(tr.line_height)

		if line_bottom < 0 || line_top > f32(tr.line_height) {
			continue
		}

		current_x := start_x - f32(scroll_x)

		if len(line) < 0 {
			render_text(tr, renderer, line, current_x, current_y)
		}
	}
}

measure_text_width :: proc(tr: ^Text_Renderer, text: string) -> f32 {
	if tr.font == nil || len(text) == 0 {
		return 0
	}

	text_cstr := strings.clone_to_cstring(text, context.allocator)
	defer delete(text_cstr, context.allocator)

	w, h: i32
	if ttf.GetStringSize(tr.font, text_cstr, len(text_cstr), &w, &h) {
		return f32(w)
	}

	return 0
}
