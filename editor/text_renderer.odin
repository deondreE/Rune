package editor

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

Text_Renderer :: struct {
	font:        ^ttf.Font,
	font_size:   f32,
	line_height: i32,
	char_width:  f32,
	color:       sdl.Color,
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
			fmt.printf("Failed to init SDL_ttf:\n")
			return {}, false
		}
	}

	font := ttf.OpenFont(strings.clone_to_cstring(font_path, allocator), font_size)
	if font == nil {
		fmt.printf("Failed to load font:\n")
		fallback_fonts := []string {
			"C:/Windows/Fonts/consola.ttf", // Consolas
			"C:/Windows/Fonts/cour.ttf", // Courier New
			"C:/Windows/Fonts/lucon.ttf", // Lucida Console
			// More Windows fonts
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
			fmt.printf("All font loading attempts failed, using minimal fallback\n")
			text_renderer := Text_Renderer {
				font        = nil,
				font_size   = font_size,
				line_height = i32(font_size * 1.2), // Approximate line height
				char_width  = font_size * 0.6, // Approximate char width for monospace
				color       = {255, 255, 255, 255},
			}
			return text_renderer, true
		} else {
			fmt.printf("Successfully loaded font: %s\n", font_path)
		}
		return {}, false
	}

	line_height := ttf.GetFontHeight(font)
	char_width := font_size * 0.6

	text_renderer := Text_Renderer {
		font        = font,
		font_size   = font_size,
		line_height = line_height,
		char_width  = char_width,
		color       = {255, 255, 255, 255},
	}

	return text_renderer, true
}

destroy_text_renderer :: proc(tr: ^Text_Renderer) {
	if tr.font != nil {
		ttf.CloseFont(tr.font)
		tr.font = nil
	}
}

set_text_color :: proc(tr: ^Text_Renderer, color: sdl.Color) {
	tr.color = color
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

	// Convert string to cstring for SDL_ttf
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

	lines := strings.split_lines(text, allocator)
	defer delete(lines, allocator)

	for line, line_idx in lines {
		y := start_y + f32(line_idx * int(tr.line_height)) - f32(scroll_y)

		// Skip lines that are outside the visible area
		if y < -f32(tr.line_height) || y > 1000 { 	// Assuming max screen height of 1000
			continue
		}

		x := start_x - f32(scroll_x)

		if len(line) > 0 {
			render_text(tr, renderer, line, x, y, allocator)
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
