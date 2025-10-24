package editor

import "core:fmt"
import "core:mem"
import "core:time"
import tregion "core:time/timezone"
import sdl "vendor:sdl3"

Status_Bar :: struct {
	height: f32,
}

init_status_bar :: proc() -> Status_Bar {
	return Status_Bar{height = 25.0}
}

render_status_bar :: proc(
	stb: ^Status_Bar,
	text_renderer: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	editor: ^Editor,
	window_w: int,
	window_h: int,
	current_line: int,
	current_col: int,
	allocator: mem.Allocator,
) {
	// Calculate pos
	bar_y := f32(window_h) - stb.height
	bar_rect := sdl.FRect {
		x = 0,
		y = bar_y,
		w = f32(window_w),
		h = stb.height,
	}

	_ = sdl.SetRenderDrawColor(
		renderer,
		editor.theme.status_bg.r,
		editor.theme.status_bg.g,
		editor.theme.status_bg.b,
		editor.theme.status_bg.a,
	)
	_ = sdl.RenderFillRect(renderer, &bar_rect)

	now := time.now()
	buf: [50]u8
	region, _ := tregion.region_load("local", allocator)
	dt, _ := time.time_to_datetime(now)
	local_datetime, s := tregion.datetime_to_tz(dt, region)
	if !s {
		fmt.printf("%v", s)
	}

	local_time, _ := time.datetime_to_time(local_datetime)
	time_string := time.to_string_hms_12(local_time, buf[:])

	text_width := measure_text_width(text_renderer, time_string)
	text_x := f32(window_w) - text_width - 10.0 // 10px padding from right edge
	text_y := bar_y + (stb.height - f32(text_renderer.line_height)) / 2.0

	_ = sdl.SetRenderDrawColor(
		renderer,
		editor.theme.status_text.r,
		editor.theme.status_text.g,
		editor.theme.status_text.b,
		editor.theme.status_text.a,
	)
	render_text(
		text_renderer,
		renderer,
		time_string,
		text_x,
		text_y,
		allocator,
		editor.theme.status_text,
	)

	line_col_string := fmt.aprintf("Ln: %d, Col: %d", current_line + 1, current_col + 1)

	line_col_text_x := f32(10.0)
	line_col_text_y := text_y

	_ = sdl.SetRenderDrawColor(
		renderer,
		editor.theme.status_text.r,
		editor.theme.status_text.g,
		editor.theme.status_text.b,
		editor.theme.status_text.a,
	)
	render_text(
		text_renderer,
		renderer,
		line_col_string,
		line_col_text_x,
		line_col_text_y,
		editor.allocator,
		editor.theme.status_text,
	)
}

get_status_bar_height :: proc(status_bar: ^Status_Bar) -> f32 {
	return status_bar.height
}
