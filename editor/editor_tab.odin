package editor

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

Tab :: struct {
	id:              int,
	title:           string,
	file_path:       string,
	gap_buffer:      Gap_Buffer,
	cursor_pos:      int,
	cursor_line:     int,
	cursor_col:      int,
	scroll_x:        int,
	scroll_y:        int,
	is_modified:     bool,
	selection_start: int,
	selection_end:   int,
	has_selection:   bool,
}

Tab_Bar :: struct {
	tabs:           [dynamic]Tab,
	active_tab_idx: int,
	next_tab_id:    int,
	height:         i32,
	tab_width:      f32,
	hover_tab_idx:  int,
	hover_close:    int, // -1 = no hover, else = tab index
	allocator:      mem.Allocator,
}

init_tab_bar :: proc(allocator: mem.Allocator) -> Tab_Bar {
	bar := Tab_Bar {
		tabs           = make([dynamic]Tab, allocator),
		active_tab_idx = -1,
		next_tab_id    = 1,
		height         = 32,
		tab_width      = 180,
		hover_tab_idx  = -1,
		hover_close    = -1,
		allocator      = allocator,
	}

	return bar
}

destroy_tab_bar :: proc(bar: ^Tab_Bar) {
	for &tab in bar.tabs {
		delete(tab.title, bar.allocator)
		delete(tab.file_path, bar.allocator)
		destroy_gap_buffer(&tab.gap_buffer, bar.allocator)
	}
	delete(bar.tabs)
}

// Create a new tab
create_tab :: proc(bar: ^Tab_Bar, title: string, file_path: string = "") -> int {
	tab := Tab {
		id              = bar.next_tab_id,
		title           = strings.clone(title, bar.allocator),
		file_path       = strings.clone(file_path, bar.allocator),
		gap_buffer      = init_gap_buffer(bar.allocator),
		cursor_pos      = 0,
		cursor_line     = 0,
		cursor_col      = 0,
		scroll_x        = 0,
		scroll_y        = 0,
		is_modified     = false,
		selection_start = 0,
		selection_end   = 0,
		has_selection   = false,
	}

	bar.next_tab_id += 1
	append(&bar.tabs, tab)

	return len(bar.tabs) - 1
}

// Open a file in a new tab
open_file_in_tab :: proc(bar: ^Tab_Bar, file_path: string) -> (int, bool) {
	// Check if file is already open
	for tab, idx in bar.tabs {
		if tab.file_path == file_path {
			return idx, true
		}
	}

	// Read file
	data, ok := os.read_entire_file(file_path, bar.allocator)
	if !ok {
		fmt.printf("Failed to open file: %s\n", file_path)
		return -1, false
	}
	defer delete(data, bar.allocator)

	// Extract filename for tab title
	filename := file_path
	if last_slash := strings.last_index_byte(file_path, '/'); last_slash != -1 {
		filename = file_path[last_slash + 1:]
	}
	if last_slash := strings.last_index_byte(filename, '\\'); last_slash != -1 {
		filename = filename[last_slash + 1:]
	}

	tab_idx := create_tab(bar, filename, file_path)

	text := string(data)
	insert_bytes(&bar.tabs[tab_idx].gap_buffer, transmute([]u8)text, bar.allocator)

	return tab_idx, true
}

close_tab :: proc(bar: ^Tab_Bar, idx: int) -> bool {
	if idx < 0 || idx >= len(bar.tabs) {
		return false
	}

	// Check if modified and prompt to save (simplified version)
	tab := &bar.tabs[idx]
	if tab.is_modified {
		fmt.printf("Tab '%s' has unsaved changes\n", tab.title)
		// TODO: Show save dialog
	}

	// Cleanup tab resources
	delete(tab.title, bar.allocator)
	delete(tab.file_path, bar.allocator)
	destroy_gap_buffer(&tab.gap_buffer, bar.allocator)

	// Remove from array
	ordered_remove(&bar.tabs, idx)

	// Update active tab index
	if bar.active_tab_idx == idx {
		if len(bar.tabs) > 0 {
			bar.active_tab_idx = min(idx, len(bar.tabs) - 1)
		} else {
			bar.active_tab_idx = -1
		}
	} else if bar.active_tab_idx > idx {
		bar.active_tab_idx -= 1
	}

	return true
}

// Switch to a tab
switch_to_tab :: proc(bar: ^Tab_Bar, idx: int) {
	if idx >= 0 && idx < len(bar.tabs) {
		bar.active_tab_idx = idx
	}
}

// Get active tab
get_active_tab :: proc(bar: ^Tab_Bar) -> ^Tab {
	if bar.active_tab_idx >= 0 && bar.active_tab_idx < len(bar.tabs) {
		return &bar.tabs[bar.active_tab_idx]
	}
	return nil
}

// Save current tab state to tab
save_editor_state_to_tab :: proc(editor: ^Editor, tab: ^Tab) {
	if tab == nil {
		return
	}

	tab.cursor_pos = editor.cursor_logical_pos
	tab.cursor_line = editor.cursor_line_idx
	tab.cursor_col = editor.cursor_col_idx
	tab.scroll_x = editor.scroll_x
	tab.scroll_y = editor.scroll_y
	tab.selection_start = editor.selection_start
	tab.selection_end = editor.selection_end
	tab.has_selection = editor.has_selection
}

// Load tab state into editor
load_tab_state_to_editor :: proc(editor: ^Editor, tab: ^Tab) {
	if tab == nil {
		return
	}

	// Swap gap buffers
	temp_buffer := editor.gap_buffer
	editor.gap_buffer = tab.gap_buffer
	tab.gap_buffer = temp_buffer

	// Restore cursor and scroll
	editor.cursor_logical_pos = tab.cursor_pos
	editor.cursor_line_idx = tab.cursor_line
	editor.cursor_col_idx = tab.cursor_col
	editor.scroll_x = tab.scroll_x
	editor.scroll_y = tab.scroll_y
	editor.selection_start = tab.selection_start
	editor.selection_end = tab.selection_end
	editor.has_selection = tab.has_selection

	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
}

// Render tab bar at bottom of window
render_tab_bar :: proc(
	bar: ^Tab_Bar,
	renderer: ^sdl.Renderer,
	text_renderer: ^Text_Renderer,
	allocator: mem.Allocator,
	window_w: i32,
	window_h: i32,
) {
	if len(bar.tabs) == 0 {
		return
	}

	// Calculate position at bottom
	y_offset := f32(window_h) - f32(bar.height)

	// Background
	bg_rect := sdl.FRect {
		x = 0,
		y = y_offset,
		w = f32(window_w),
		h = f32(bar.height),
	}

	_ = sdl.SetRenderDrawColor(renderer, 0x2D, 0x2D, 0x30, 0xFF)
	_ = sdl.RenderFillRect(renderer, &bg_rect)

	x_offset: f32 = 0
	close_button_size: f32 = 16
	close_button_margin: f32 = 8

	for tab, idx in bar.tabs {
		is_active := idx == bar.active_tab_idx
		is_hovered := idx == bar.hover_tab_idx

		// Tab background
		tab_rect := sdl.FRect {
			x = x_offset,
			y = y_offset,
			w = bar.tab_width,
			h = f32(bar.height),
		}

		// Tab color
		if is_active {
			_ = sdl.SetRenderDrawColor(renderer, 0x1E, 0x1E, 0x1E, 0xFF)
		} else if is_hovered {
			_ = sdl.SetRenderDrawColor(renderer, 0x37, 0x37, 0x38, 0xFF)
		} else {
			_ = sdl.SetRenderDrawColor(renderer, 0x2D, 0x2D, 0x30, 0xFF)
		}
		_ = sdl.RenderFillRect(renderer, &tab_rect)

		// Active tab indicator at bottom
		if is_active {
			indicator_rect := sdl.FRect {
				x = x_offset,
				y = y_offset + f32(bar.height) - 2, // Bottom of tab
				w = bar.tab_width,
				h = 2,
			}
			_ = sdl.SetRenderDrawColor(renderer, 0x00, 0x7A, 0xCC, 0xFF)
			_ = sdl.RenderFillRect(renderer, &indicator_rect)
		}

		// Tab title
		title_text := tab.title
		if tab.is_modified {
			title_text = fmt.tprintf("● %s", tab.title)
		}

		text_x := x_offset + 10
		text_y := y_offset + (f32(bar.height) - f32(text_renderer.line_height)) / 2

		text_color := sdl.Color{200, 200, 200, 255}
		if is_active {
			text_color = sdl.Color{255, 255, 255, 255}
		}

		// Measure and truncate text if too long
		available_width := bar.tab_width - 20 - close_button_size - close_button_margin
		text_width := measure_text_width(text_renderer, title_text)

		display_text := title_text
		if text_width > available_width {
			// Truncate text
			truncated := title_text
			for len(truncated) > 3 {
				test_text := fmt.tprintf("%s...", truncated[:len(truncated) - 1])
				test_width := measure_text_width(text_renderer, test_text)
				if test_width <= available_width {
					display_text = test_text
					break
				}
				truncated = truncated[:len(truncated) - 1]
			}
		}

		render_text(text_renderer, renderer, display_text, text_x, text_y, allocator, text_color)

		// Close button
		close_x := x_offset + bar.tab_width - close_button_size - close_button_margin
		close_y := y_offset + (f32(bar.height) - close_button_size) / 2

		close_rect := sdl.FRect {
			x = close_x,
			y = close_y,
			w = close_button_size,
			h = close_button_size,
		}

		is_close_hovered := bar.hover_close == idx

		if is_close_hovered {
			_ = sdl.SetRenderDrawColor(renderer, 0x50, 0x50, 0x50, 0xFF)
			_ = sdl.RenderFillRect(renderer, &close_rect)
		}

		// Draw X
		close_icon_color := sdl.Color{150, 150, 150, 255}
		if is_close_hovered {
			close_icon_color = sdl.Color{255, 255, 255, 255}
		}

		_ = sdl.SetRenderDrawColor(
			renderer,
			close_icon_color.r,
			close_icon_color.g,
			close_icon_color.b,
			close_icon_color.a,
		)

		center_x := close_x + close_button_size / 2
		center_y := close_y + close_button_size / 2
		cross_size: f32 = 6

		_ = sdl.RenderLine(
			renderer,
			center_x - cross_size / 2,
			center_y - cross_size / 2,
			center_x + cross_size / 2,
			center_y + cross_size / 2,
		)
		_ = sdl.RenderLine(
			renderer,
			center_x + cross_size / 2,
			center_y - cross_size / 2,
			center_x - cross_size / 2,
			center_y + cross_size / 2,
		)

		// Tab separator
		if idx < len(bar.tabs) - 1 {
			_ = sdl.SetRenderDrawColor(renderer, 0x45, 0x45, 0x45, 0xFF)
			_ = sdl.RenderLine(
				renderer,
				x_offset + bar.tab_width,
				y_offset + 4,
				x_offset + bar.tab_width,
				y_offset + f32(bar.height) - 4,
			)
		}

		x_offset += bar.tab_width
	}

	_ = sdl.SetRenderDrawColor(renderer, 0x45, 0x45, 0x45, 0xFF)
	_ = sdl.RenderLine(
		renderer,
		0,
		y_offset, // Top border instead of bottom
		f32(window_w),
		y_offset,
	)
}

// Handle tab bar events at bottom
handle_tab_bar_event :: proc(
	bar: ^Tab_Bar,
	event: ^sdl.Event,
	window_h: i32,
) -> bool {
	if len(bar.tabs) == 0 {
		return false
	}

	// Calculate bottom position
	y_offset := f32(window_h) - f32(bar.height)

	mouse_x: f32
	mouse_y: f32

	#partial switch event.type {
	case .MOUSE_MOTION:
		mouse_x = event.motion.x
		mouse_y = event.motion.y
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		mouse_x = event.button.x
		mouse_y = event.button.y
	case:
		return false
	}

	// Check if mouse is in tab bar area
	if mouse_y < y_offset || mouse_y > y_offset + f32(bar.height) {
		bar.hover_tab_idx = -1
		bar.hover_close = -1
		return false
	}

	// Find which tab is hovered
	tab_idx := int(mouse_x / bar.tab_width)
	if tab_idx < 0 || tab_idx >= len(bar.tabs) {
		bar.hover_tab_idx = -1
		bar.hover_close = -1
		return false
	}

	bar.hover_tab_idx = tab_idx

	// Check if close button is hovered
	close_button_size: f32 = 16
	close_button_margin: f32 = 8
	tab_x := f32(tab_idx) * bar.tab_width
	close_x := tab_x + bar.tab_width - close_button_size - close_button_margin
	close_y := y_offset + (f32(bar.height) - close_button_size) / 2

	is_over_close :=
		mouse_x >= close_x &&
		mouse_x <= close_x + close_button_size &&
		mouse_y >= close_y &&
		mouse_y <= close_y + close_button_size

	if is_over_close {
		bar.hover_close = tab_idx
	} else {
		bar.hover_close = -1
	}

	// Handle clicks
	#partial switch event.type {
	case .MOUSE_BUTTON_DOWN:
		if event.button.button == sdl.BUTTON_LEFT {
			if is_over_close {
				// Close tab
				close_tab(bar, tab_idx)
				return true
			} else {
				// Switch to tab
				switch_to_tab(bar, tab_idx)
				return true
			}
		}
	}

	return false
}

// Save tab to file
save_tab :: proc(tab: ^Tab) -> bool {
	if len(tab.file_path) == 0 {
		fmt.println("Cannot save: no file path")
		return false
	}

	content := get_text(&tab.gap_buffer, context.allocator)
	defer delete(content, context.allocator)

	ok := os.write_entire_file(tab.file_path, transmute([]u8)content)
	if ok {
		tab.is_modified = false
		fmt.printf("Saved: %s\n", tab.file_path)
	} else {
		fmt.printf("Failed to save: %s\n", tab.file_path)
	}

	return ok
}

// Mark tab as modified
mark_tab_modified :: proc(tab: ^Tab) {
	tab.is_modified = true
}

// Get tab index by file path
find_tab_by_path :: proc(bar: ^Tab_Bar, file_path: string) -> int {
	for tab, idx in bar.tabs {
		if tab.file_path == file_path {
			return idx
		}
	}
	return -1
}