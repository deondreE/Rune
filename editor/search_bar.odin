package editor

import "core:fmt"
import "core:math"
import "core:mem"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

Search_Bar :: struct {
	is_visible: bool,
	caret_pos:  int,
	gap_buffer: Gap_Buffer,
}

init_search_bar :: proc(allocator: mem.Allocator) -> Search_Bar {
	sb: Search_Bar
	sb.gap_buffer = init_gap_buffer(allocator)
	sb.is_visible = false
	sb.caret_pos = 0
	return sb
}

handle_backspace_search :: proc(sb: ^Search_Bar) {
	if sb.caret_pos <= 0 {
		return
	}

	prev_pos := get_prev_utf8_char_start_byte_offset(&sb.gap_buffer, sb.caret_pos)
	if prev_pos < 0 {
		prev_pos = 0
	}
	bytes_to_delete := sb.caret_pos - prev_pos
	if bytes_to_delete <= 0 {
		return
	}

	delete_bytes_left(&sb.gap_buffer, bytes_to_delete)
	sb.caret_pos = prev_pos
	move_gap(&sb.gap_buffer, sb.caret_pos)
}

handle_search_bar_event :: proc(sb: ^Search_Bar, editor: ^Editor, event: ^sdl.Event) -> bool {
	if !sb.is_visible {
		return false
	}

	#partial switch event.type {
	case sdl.EventType.KEY_DOWN:
		switch event.key.key {
		case 27: // ESC
			sb.is_visible = false
		case 13: // ENTER
			query := get_text_segment(
				&sb.gap_buffer,
				0,
				current_length(&sb.gap_buffer),
				editor.allocator,
			)
			defer delete(query, editor.allocator)
			fmt.printf("Search confirmed: %s\n", query)
			sb.is_visible = false
		case 8: // BACKSPACE
			handle_backspace_search(sb)
		}
	case sdl.EventType.TEXT_INPUT:
		text_cstr := event.text.text
		text_len := len(string(text_cstr))
		if text_len > 0 {
			text_bytes := ([^]u8)(text_cstr)[:text_len]
			insert_bytes(&sb.gap_buffer, text_bytes, editor.allocator)
			sb.caret_pos += text_len
			move_gap(&sb.gap_buffer, sb.caret_pos)
		}
	}

	// return true, because the search bar handled this event
	return true
}

render_search_bar :: proc(
	sb: ^Search_Bar,
	text_renderer: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	window_w, window_h: i32,
) {
	if !sb.is_visible {
		return
	}

	bar_h := f32(text_renderer.line_height) * 1.5
	bar_y: f32 = 10.0
	bar_x := f32(300)
	bar_w := f32(window_w) - 2 * bar_x

	// Background
	_ = sdl.SetRenderDrawColor(renderer, 0x30, 0x30, 0x30, 0xFF)
	bar_rect := sdl.FRect{bar_x, bar_y, bar_w, bar_h}
	_ = sdl.RenderFillRect(renderer, &bar_rect)

	// Outline
	_ = sdl.SetRenderDrawColor(renderer, 0x80, 0x80, 0x80, 0xFF)
	_ = sdl.RenderRect(renderer, &bar_rect)

	search_text := get_text_segment(
		&sb.gap_buffer,
		0,
		current_length(&sb.gap_buffer),
		context.allocator,
	)
	defer delete(search_text, context.allocator)

	// Draw the text
	render_text(
		text_renderer,
		renderer,
		search_text,
		bar_x + 10.0,
		bar_y + (bar_h - f32(text_renderer.line_height)) / 2.0,
		context.allocator,
	)

	// Draw caret
	caret_bytes := min(sb.caret_pos, len(search_text))
	caret_slice := string(search_text[:caret_bytes])
	caret_x := bar_x + 10.0 + measure_text_width(text_renderer, caret_slice)
	caret_y := bar_y + 4.0

	caret_rect := sdl.FRect{caret_x, caret_y, 2.0, f32(text_renderer.line_height)}

	blink_interval_ms :: 500
	current_time_ms := sdl.GetTicks()
	if (current_time_ms / u64(blink_interval_ms)) % 2 == 0 {
		_ = sdl.SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF)
		_ = sdl.RenderFillRect(renderer, &caret_rect)
	}
}

destroy_search_bar :: proc(sb: ^Search_Bar, allocator: mem.Allocator) {
	destroy_gap_buffer(&sb.gap_buffer, allocator)
}
