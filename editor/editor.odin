package editor

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
import "core:sync"
import "core:unicode/utf8"
import lsp "lsp"
import sdl "vendor:sdl3"

Editor :: struct {
	allocator:           mem.Allocator,
	window:              ^sdl.Window,
	renderer:            ^sdl.Renderer,
	text_renderer:       Text_Renderer,
	gap_buffer:          Gap_Buffer,
	cursor_logical_pos:  int,
	cursor_line_idx:     int,
	cursor_col_idx:      int,
	scroll_x:            int,
	scroll_y:            int,
	line_height:         i32,
	char_width:          f32,
	file_explorer:       File_Explorer,
	search_bar:          Search_Bar,
	context_menu:        Context_Menu,
	menu_bar:            Menu_Bar,
	status_bar:          Status_Bar,
	lsp:                 ^lsp.LSP_Thread,
	selection_start:     int,
	selection_end:       int,
	has_selection:       bool,
	mouse_down:          bool,
	mouse_dragging:      bool,
	_is_mouse_selecting: bool,
	last_click_time:     u64,
	last_click_pos:      int,
	double_click_ms:     u64,
}

clear_selection :: proc(editor: ^Editor) {
	editor.has_selection = false
}

selection_range :: proc(editor: ^Editor) -> (int, int) {
	if !editor.has_selection {
		return editor.cursor_logical_pos, editor.cursor_logical_pos
	}

	if editor.selection_start < editor.selection_end {
		return editor.selection_start, editor.selection_end
	} else {
		return editor.selection_end, editor.selection_start
	}
}

copy_selection_to_clipboard :: proc(editor: ^Editor) {
	if !editor.has_selection {
		return
	}
	start, end := selection_range(editor)
	text := get_text_segment(&editor.gap_buffer, start, end - start, editor.allocator)
	text_cstr := strings.clone_to_cstring(text, editor.allocator)
	defer delete(text, editor.allocator)
	_ = sdl.SetClipboardText(text_cstr)
}

paste_from_clipboard :: proc(editor: ^Editor) {
	cstr := sdl.GetClipboardText()
	if cstr == nil {return}
	defer sdl.free(cstr)
	text_len := 0

	// TODO: Change this.
	for cstr[text_len] != 0 {
		text_len += 1
	}
	if text_len == 0 {return}

	text_bytes := ([^]u8)(cstr)[:text_len]
	if editor.has_selection {
		delete_selection(editor)
	}

	insert_bytes(&editor.gap_buffer, text_bytes, editor.allocator)
	editor.cursor_logical_pos += len(text_bytes)
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	update_cursor_position(editor)
}

get_prev_utf8_char_start_byte_offset :: proc(gb: ^Gap_Buffer, logical_byte_pos: int) -> int {
	if logical_byte_pos <= 0 {
		return 0
	}

	pos := logical_byte_pos
	current_len := current_length(gb)
	if pos > current_len {
		pos = current_len
	}

	for i := 1; i <= 4; i += 1 {
		target := pos - i
		if target < 0 {
			break
		}

		temp_segment := get_text_segment(gb, target, 1, context.allocator)
		if len(temp_segment) > 0 && utf8.rune_start(temp_segment[0]) {
			return target
		}
	}
	return max(0, logical_byte_pos - 1)
}

get_next_utf8_char_start_byte_offset :: proc(gb: ^Gap_Buffer, logical_byte_pos: int) -> int {
	total_len := current_length(gb)
	if logical_byte_pos >= total_len {
		return total_len
	}

	temp_segment := get_text_segment(
		gb,
		logical_byte_pos,
		min(4, total_len - logical_byte_pos),
		context.allocator,
	)
	if len(temp_segment) == 0 {
		return logical_byte_pos
	}

	_, size := utf8.decode_rune(transmute([]u8)temp_segment)
	if size == 0 {
		return logical_byte_pos + 1
	}
	return logical_byte_pos + size
}

update_cursor_position :: proc(editor: ^Editor) {
	editor.cursor_line_idx, editor.cursor_col_idx = logical_pos_to_line_col(
		&editor.gap_buffer,
		editor.cursor_logical_pos,
	)
}

move_cursor_up :: proc(editor: ^Editor) {
	if editor.cursor_line_idx > 0 {
		// Try to maintain column position, but clamp to line length
		lines := get_lines(&editor.gap_buffer, editor.allocator)
		defer {
			for line in lines {
				delete(line, editor.allocator)
			}
			delete(lines, editor.allocator)
		}

		new_line := editor.cursor_line_idx - 1
		if new_line < 0 || new_line >= len(lines) {
			return
		}

		old_col := editor.cursor_col_idx
		new_col := min(old_col, len(lines[new_line]))

		editor.cursor_logical_pos = line_col_to_logical_pos(&editor.gap_buffer, new_line, new_col)

		move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
		update_cursor_position(editor)
	}
}

move_cursor_down :: proc(editor: ^Editor) {
	lines := get_lines(&editor.gap_buffer, editor.allocator)
	defer {
		for line in lines {
			delete(line, editor.allocator)
		}
		delete(lines, editor.allocator)
	}

	if editor.cursor_line_idx >= len(lines) - 1 {
		return
	}

	new_line := editor.cursor_line_idx + 1
	if new_line < 0 || new_line >= len(lines) {
		return
	}

	old_col := editor.cursor_col_idx
	new_col := min(old_col, len(lines[new_line]))

	editor.cursor_logical_pos = line_col_to_logical_pos(&editor.gap_buffer, new_line, new_col)

	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	update_cursor_position(editor)
}

move_cursor_left :: proc(editor: ^Editor) {
	if editor.cursor_logical_pos <= 0 {
		return
	}

	prev := get_prev_utf8_char_start_byte_offset(&editor.gap_buffer, editor.cursor_logical_pos)
	if prev < 0 {
		prev = 0
	}

	editor.cursor_logical_pos = prev
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	update_cursor_position(editor)
}

move_cursor_right :: proc(editor: ^Editor) {
	total_len := current_length(&editor.gap_buffer)
	if editor.cursor_logical_pos >= total_len {
		return
	}

	next := get_next_utf8_char_start_byte_offset(&editor.gap_buffer, editor.cursor_logical_pos)
	editor.cursor_logical_pos = clamp(next, 0, total_len)
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	update_cursor_position(editor)
}

insert_char :: proc(editor: ^Editor, r: rune) {
	fmt.printf("insert_char called with rune: %d (char: '%c')\n", r, r)
	if editor.has_selection {
		// Maybe you don't want to just delete the selection here.
		delete_selection(editor)
	}

	temp_str := utf8.runes_to_string({r}, editor.allocator)
	defer delete(temp_str, editor.allocator)

	fmt.printf("Encoded to %d bytes: %v\n", len(temp_str), transmute([]u8)temp_str)

	insert_bytes(&editor.gap_buffer, transmute([]u8)temp_str, editor.allocator)
	editor.cursor_logical_pos += len(temp_str)

	update_cursor_position(editor)
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
}

init_editor :: proc(
	window: ^sdl.Window,
	renderer: ^sdl.Renderer,
	allocator: mem.Allocator = context.allocator,
) -> Editor {
	editor: Editor
	editor.allocator = allocator
	editor.window = window
	editor.renderer = renderer

	text_renderer, ok := init_text_renderer("assets/fonts/MapleMono-Regular.ttf", 16, allocator)
	if !ok {
		fmt.println("Failed to initialize text renderer")
	}
	editor.text_renderer = text_renderer
	editor.double_click_ms = 300
	editor.status_bar = init_status_bar()
	editor.gap_buffer = init_gap_buffer(allocator)
	editor.cursor_logical_pos = 0
	editor.cursor_line_idx = 0
	editor.cursor_col_idx = 0
	editor.line_height = text_renderer.line_height
	editor.char_width = text_renderer.char_width
	editor.search_bar = init_search_bar(allocator)
	editor._is_mouse_selecting = false

	initial_text := `Hello, Deondre!
This is your Odin code editor.
Let's make some magic happen!`


	insert_bytes(&editor.gap_buffer, transmute([]u8)initial_text, editor.allocator)

	editor.cursor_logical_pos = current_length(&editor.gap_buffer)
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	editor.cursor_line_idx = strings.count(initial_text, "\n")
	last_newline_idx := strings.last_index_byte(initial_text, '\n')
	if last_newline_idx != -1 {
		editor.cursor_col_idx = len(initial_text)
	} else {
		editor.cursor_col_idx = len(initial_text)
	}

	editor.file_explorer = init_file_explorer(
		".",
		0,
		0,
		"assets/fonts/MapleMono-NF-Regular.ttf",
		16.0,
		250,
		allocator,
	)
	editor.context_menu = init_context_menu(allocator)
	editor.menu_bar = init_menu_bar(allocator)
	editor.lsp = lsp.init_lsp_thread("ols", editor.allocator)

	fmt.println("Editor initialized.")
	return editor
}

destroy_editor :: proc(editor: ^Editor) {
	destroy_search_bar(&editor.search_bar, editor.allocator)
	destroy_context_menu(&editor.context_menu)
	destroy_gap_buffer(&editor.gap_buffer, editor.allocator)
	destroy_file_explorer(&editor.file_explorer)
	destroy_text_renderer(&editor.text_renderer)
	fmt.println("Editor destroyed.")
}

update :: proc(editor: ^Editor, dt: f64) {

}

render :: proc(editor: ^Editor) {
	_ = sdl.SetRenderDrawColor(editor.renderer, 0x1E, 0x1E, 0x1E, 0xFF)
	_ = sdl.RenderClear(editor.renderer)

	window_w: i32
	window_h: i32
	_ = sdl.GetWindowSize(editor.window, &window_w, &window_h)

	menu_offset_y := f32(editor.menu_bar.height) + 10
	file_explorer_width := editor.file_explorer.is_visible ? editor.file_explorer.width : 0
	text_origin_x := f32(file_explorer_width)
	editor_area_x := file_explorer_width
	editor_area_width := f32(window_w) - file_explorer_width
	start_sel, end_sel := selection_range(editor)

	render_search_bar(
		&editor.search_bar,
		&editor.text_renderer,
		editor.renderer,
		window_w,
		window_h,
	)
	// Editor file explorer.
	if editor.file_explorer.is_visible {
		render_file_explorer(&editor.file_explorer, editor.renderer)

		// _ = sdl.SetRenderDrawBlendMode(editor.renderer, sdl.BlendMode.NONE)
		_ = sdl.SetRenderDrawColor(editor.renderer, 0x40, 0x40, 0x40, 0xFF)

		divider_rect := sdl.FRect {
			x = f32(editor.file_explorer.width) - 1.0, // align to panel’s right edge
			y = menu_offset_y,
			w = 1.0,
			h = f32(window_h) - menu_offset_y,
		}

		_ = sdl.RenderFillRect(editor.renderer, &divider_rect)
	}

	// Selection via, the ARROW KEYS.
	if editor.has_selection && start_sel != end_sel {
		r_color := sdl.Color{0x33, 0x66, 0xCC, 0x80}
		_ = sdl.SetRenderDrawColor(editor.renderer, 0x33, 0x66, 0xCC, 0x80)

		lines := get_lines(&editor.gap_buffer, editor.allocator)
		defer {
			for line in lines {delete(line, editor.allocator)}
			delete(lines, editor.allocator)
		}

		sel_line_start, sel_col_start := logical_pos_to_line_col(&editor.gap_buffer, start_sel)
		sel_line_end, sel_col_end := logical_pos_to_line_col(&editor.gap_buffer, end_sel)

		for i := sel_line_start; i <= sel_line_end && i < len(lines); i += 1 {
			y := menu_offset_y + f32(i * int(editor.line_height) - editor.scroll_y)
			line_x := f32(60) - f32(editor.scroll_x)
			line_text := lines[i]

			line_start_col := 0
			line_end_col := len(line_text)

			if i == sel_line_start {
				line_start_col = sel_col_start
			}
			if i == sel_line_end {
				line_end_col = sel_col_end
			}
			width_start := measure_text_width(&editor.text_renderer, line_text[:line_start_col])
			width_end := measure_text_width(&editor.text_renderer, line_text[:line_end_col])

			rect := sdl.FRect {
				line_x + f32(width_start),
				y,
				f32(width_end - width_start),
				f32(editor.line_height),
			}
			to_render := rect_to_geometry(rect, r_color)
			_ = sdl.RenderGeometry(
				editor.renderer,
				to_render.texture,
				raw_data(to_render.vertices),
				i32(len(to_render.vertices)),
				raw_data(to_render.indices),
				i32(len(to_render.indices)),
			)
		}
	}

	// Core Editor text & Cursor
	lines := get_lines(&editor.gap_buffer, editor.allocator)
	defer {
		for line in lines {
			delete(line, editor.allocator)
		}
		delete(lines, editor.allocator)
	}

	gutter_width := f32(60) // Fixed width in pixels
	text_area_x := text_origin_x + gutter_width

	start_line := max(0, editor.scroll_y / int(editor.line_height))
	visible_lines := int(f32(window_h) / f32(editor.line_height)) + 2
	end_line := min(len(lines), start_line + 50)

	// Lines, numbers, and text content
	for i := start_line; i < end_line; i += 1 {
		if i < len(lines) {
			y := menu_offset_y + f32(i * int(editor.line_height) - editor.scroll_y)

			if y < -f32(editor.line_height) || y > f32(window_h) {
				continue
			}

			line_num := i + 1
			line_num_str: string
			if line_num < 10 {
				line_num_str = fmt.aprintf("   %d ", line_num)
			} else if line_num < 100 {
				line_num_str = fmt.aprintf("  %d ", line_num)
			} else if line_num < 1000 {
				line_num_str = fmt.aprintf(" %d ", line_num)
			} else {
				line_num_str = fmt.aprintf("%d ", line_num)
			}
			defer delete(line_num_str, editor.allocator)

			original_color := editor.text_renderer.color
			if i == editor.cursor_line_idx {
				editor.text_renderer.color = sdl.Color{0xFF, 0xFF, 0xFF, 0xFF}
			} else {
				editor.text_renderer.color = sdl.Color{0x60, 0x60, 0x60, 0xFF}
			}

			render_text(
				&editor.text_renderer,
				editor.renderer,
				line_num_str,
				editor_area_x + 5,
				y,
				editor.allocator,
			)

			editor.text_renderer.color = original_color

			line_x := text_area_x - f32(editor.scroll_x)
			render_text(
				&editor.text_renderer,
				editor.renderer,
				lines[i],
				line_x,
				y,
				editor.allocator,
			)
		}
	}

	cursor_x := int(gutter_width) - editor.scroll_x
	cursor_y :=
		menu_offset_y + f32(editor.cursor_line_idx * int(editor.line_height) - editor.scroll_y)
	if editor.cursor_line_idx < len(lines) && len(lines) > 0 {
		original_line := get_line(&editor.gap_buffer, editor.cursor_line_idx, editor.allocator)
		defer delete(original_line, editor.allocator)

		current_line := lines[editor.cursor_line_idx]
		cursor_pos_in_line := min(editor.cursor_col_idx, len(current_line))

		if cursor_pos_in_line > 0 {
			text_before_cursor := current_line[:cursor_pos_in_line]
			text_width := measure_text_width(&editor.text_renderer, text_before_cursor)
			cursor_x += int(text_width)
		}
	}

	cursor_rect := sdl.FRect {
		x = f32(cursor_x),
		y = f32(cursor_y),
		w = 2.0,
		h = f32(editor.line_height),
	}

	blink_interval_ms :: 500
	current_time_ms := sdl.GetTicks()
	if (current_time_ms / u64(blink_interval_ms)) % 2 == 0 {
		_ = sdl.SetRenderDrawColor(editor.renderer, 0xFF, 0xFF, 0xFF, 0xFF)
		_ = sdl.RenderFillRect(editor.renderer, &cursor_rect)
	}

	render_status_bar(
		&editor.status_bar,
		&editor.text_renderer,
		editor.renderer,
		int(window_w),
		int(window_h),
		editor.allocator,
	)
	render_context_menu(&editor.context_menu, editor.renderer, &editor.text_renderer)
	render_menu_bar(&editor.menu_bar, editor.renderer)

	sdl.RenderPresent(editor.renderer)
}

handle_backspace :: proc(editor: ^Editor) {
	if editor.has_selection {
		delete_selection(editor)
	}

	if editor.cursor_logical_pos > 0 {
		bytes_to_delete: int
		prev_pos := get_prev_utf8_char_start_byte_offset(
			&editor.gap_buffer,
			editor.cursor_logical_pos,
		)
		bytes_to_delete = editor.cursor_logical_pos - prev_pos

		delete_bytes_left(&editor.gap_buffer, bytes_to_delete)
		editor.cursor_logical_pos = prev_pos
		update_cursor_position(editor)
		move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	}
}

delete_char_from_string :: proc(s: string, index: int, allocator: mem.Allocator) -> string {
	if index > 0 || index >= len(s) {
		return s
	}

	new_str := fmt.aprintf("%s%s", s[:index], s[index + 1:])

	return new_str
}

delete_selection :: proc(editor: ^Editor) {
	if !editor.has_selection {
		return
	}

	start_sel, end_sel := selection_range(editor)
	delete_bytes_range(&editor.gap_buffer, start_sel, end_sel - start_sel)
	editor.cursor_logical_pos = start_sel
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	clear_selection(editor)
}

is_word_char :: proc(c: u8) -> bool {
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' // optional
}

move_cursor_word_left :: proc(editor: ^Editor) {
	if editor.cursor_logical_pos == 0 {
		return
	}

	data := get_text(&editor.gap_buffer, editor.allocator)

	pos := editor.cursor_logical_pos - 1
	for pos > 0 && !is_word_char(data[pos - 1]) {
		pos -= 1
	}

	for pos > 0 && is_word_char(data[pos - 1]) {
		pos -= 1
	}

	editor.cursor_logical_pos = pos
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	update_cursor_position(editor)
}

move_cursor_word_right :: proc(editor: ^Editor) {
	data := get_text(&editor.gap_buffer, editor.allocator)
	total := len(data)
	pos := editor.cursor_logical_pos

	for pos < total && !is_word_char(data[pos]) {
		pos += 1
	}

	for pos < total && is_word_char(data[pos]) {
		pos += 1
	}

	editor.cursor_logical_pos = pos
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	update_cursor_position(editor)
}

screen_to_logical_pos :: proc(editor: ^Editor, x: int, y: int) -> int {
	// Account for scroll + gutters
	menu_offset_y := f32(editor.menu_bar.height) + 10
	local_x := f32(x) + f32(editor.scroll_x) - 60
	local_y := f32(y) + f32(editor.scroll_y) - menu_offset_y

	lines := get_lines(&editor.gap_buffer, editor.allocator)
	line_index := clamp(int(local_y / f32(editor.line_height)), 0, len(lines) - 1)
	defer {
		for line in lines {delete(line, editor.allocator)}
		delete(lines, editor.allocator)
	}

	line_text := lines[line_index]
	accum_width: f32 = 0
	col_index := 0

	// find which character X lands on
	for i in 0 ..< len(line_text) {
		t_input := string(line_text[:i + 1])
		w := measure_text_width(&editor.text_renderer, t_input)
		if w > local_x {
			col_index = i
			break
		}
		accum_width = w
	}

	return line_col_to_logical_pos(&editor.gap_buffer, line_index, col_index)
}

select_word_at_pos :: proc(editor: ^Editor, pos: int) {
	data := get_text(&editor.gap_buffer, editor.allocator)
	if len(data) == 0 {
		return
	}

	start := pos
	end := pos

	// move left until non‑word
	for start > 0 && is_word_char(data[start - 1]) {
		start -= 1
	}
	// move right until non‑word
	for end < len(data) && is_word_char(data[end]) {
		end += 1
	}

	editor.selection_start = start
	editor.selection_end = end
	editor.cursor_logical_pos = end
	editor.has_selection = true

	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)
	update_cursor_position(editor)
}

handle_event :: proc(editor: ^Editor, event: ^sdl.Event) {
	menu_offset_y := f32(editor.menu_bar.height) + 10
	if handle_search_bar_event(&editor.search_bar, editor, event) {
		return
	}

	if handle_file_explorer_event(&editor.file_explorer, event) {
		return
	}

	if handle_search_bar_event(&editor.search_bar, editor, event) {
		return
	}

	#partial switch event.type {
	case .MOUSE_BUTTON_DOWN:
		if event.button.button == sdl.BUTTON_LEFT {
			now := sdl.GetTicks()
			mouse_x := event.button.x
			mouse_y := event.button.y

			pos := screen_to_logical_pos(editor, int(mouse_x), int(mouse_y))

			if (now - editor.last_click_time) <= editor.double_click_ms &&
			   abs(pos - editor.last_click_pos) < 2 { 	// small threshold
				select_word_at_pos(editor, pos)
			} else {
				// Record click position and allow dragging
				editor.cursor_logical_pos = pos
				editor.selection_start = pos
				editor.selection_end = pos
				editor.has_selection = false
				editor.mouse_down = true
			}

			editor.last_click_time = now
			editor.last_click_pos = pos
		}
	case .MOUSE_MOTION:
		if editor.mouse_down {
			mouse_x := event.motion.x
			mouse_y := event.motion.y

			view_height := 200
			text_top := menu_offset_y
			text_bottom := int(text_top) + int(view_height)

			pos: int

			if mouse_y < text_top {
				pos = 0
			} else if int(mouse_y) > int(text_bottom) {
				lines := get_lines(&editor.gap_buffer, editor.allocator)
				defer {
					for line in lines {delete(line, editor.allocator)}
					delete(lines, editor.allocator)
				}
				last_line := len(lines) - 1
				last_col := len(lines[last_line])
				pos = line_col_to_logical_pos(&editor.gap_buffer, last_line, last_col)
			} else {
				pos = screen_to_logical_pos(editor, int(mouse_x), int(mouse_y))
			}

			editor.selection_end = pos
			editor.has_selection = true
			editor.mouse_dragging = true
			editor.cursor_logical_pos = pos
			move_gap(&editor.gap_buffer, pos)
			update_cursor_position(editor)
		}
	case .MOUSE_BUTTON_UP:
		if event.button.button == sdl.BUTTON_LEFT {
			editor.mouse_down = false
			editor.mouse_dragging = false
			if editor.selection_start == editor.selection_end {
				editor.has_selection = false
			} else {
				editor.has_selection = true
			}
		} else {
			editor.has_selection = false
			editor.selection_start = editor.cursor_logical_pos
			editor.selection_end = editor.cursor_logical_pos
		}
	case sdl.EventType.KEY_DOWN:
		shift_held := event.key.mod == sdl.KMOD_LSHIFT

		if event.key.mod == sdl.KMOD_LCTRL {
			switch event.key.key {
			case 'p':
				// CTRL-P -- Search
				editor.search_bar.is_visible = !editor.search_bar.is_visible
				if editor.search_bar.is_visible {
					editor.search_bar.caret_pos = 0
				}
			case 'a':
				// CTRL-A -- Select all	
				editor.selection_start = 0
				editor.selection_end = current_length(&editor.gap_buffer)
				editor.has_selection = true
				return
			case 'c':
				// CTRL-C -- Copy
				copy_selection_to_clipboard(editor)
				return
			case 'x':
				// CTRL-X -- Cut
				copy_selection_to_clipboard(editor)
				delete_selection(editor)
				return
			case 'v':
				// CTRL-V	-- Paste
				paste_from_clipboard(editor)
				return
			case 'b':
				// CTRL-B -- FileExplorer
				editor.file_explorer.is_visible = !editor.file_explorer.is_visible
				return
			case 'i':
				prototype_run()
				return
			case 1073741903:
				// Right Arrow jump to front of word.
				move_cursor_word_right(editor)
				return
			case 1073741904:
				// Left arrow jump to end of word.
				move_cursor_word_left(editor)
				return
			}
		}

		switch event.key.key {
		case 27:
		case 9:
			// Tab
			// TODO: replace '\t' with some tab_size value.
			insert_char(editor, '\t')
			editor.cursor_logical_pos += editor.gap_buffer.tab_size
			update_cursor_position(editor)
		case 13:
			// enter
			insert_char(editor, '\n')
		case 8:
			// backspace
			handle_backspace(editor)
		case 46:
			// TODO: Implement delete_bytes_right, also consider UTF-8
			fmt.println("Delete key pressed (not yet fully implemented).")
		case 1073741904:
			// Left Arrow
			old_pos := editor.cursor_logical_pos
			move_cursor_left(editor)
			if shift_held {
				if !editor.has_selection {
					editor.selection_start = old_pos
					editor.has_selection = true
				}
				editor.selection_end = editor.cursor_logical_pos
			} else {
				clear_selection(editor)
			}
		case 1073741903:
			// Right Arrow
			old_pos := editor.cursor_logical_pos
			move_cursor_right(editor)
			if shift_held {
				if !editor.has_selection {
					editor.selection_start = old_pos
					editor.has_selection = true
				}
				editor.selection_end = editor.cursor_logical_pos
			} else {
				clear_selection(editor)
			}
		case 1073741906:
			// Up
			old_pos := editor.cursor_logical_pos
			move_cursor_up(editor)
			if shift_held {
				if !editor.has_selection {
					editor.selection_start = old_pos
					editor.has_selection = true
				}
				editor.selection_end = editor.cursor_logical_pos
			} else {
				clear_selection(editor)
			}
		case 1073741905:
			// Down
			old_pos := editor.cursor_logical_pos
			move_cursor_down(editor)
			if shift_held {
				if !editor.has_selection {
					editor.selection_start = old_pos
					editor.has_selection = true
				}
				editor.selection_end = editor.cursor_logical_pos
			} else {
				clear_selection(editor)
			}
		case 113:
			toggle_file_explorer(&editor.file_explorer)
			return
		}
	case sdl.EventType.TEXT_INPUT:
		// This event is for actual character input
		text_cstr := event.text.text
		text_len := len(string(text_cstr))
		text_input_bytes := ([^]u8)(text_cstr)[:text_len]
		insert_bytes(&editor.gap_buffer, text_input_bytes, editor.allocator)
		inserted_bytes_len := len(text_input_bytes)
		editor.cursor_logical_pos += inserted_bytes_len

		for r_idx := 0; r_idx < len(text_input_bytes); {
			size := text_len
			editor.cursor_col_idx += 1
			r_idx += size
		}
		move_gap(&editor.gap_buffer, editor.cursor_logical_pos)

		fmt.printf(
			"Text input: '%s', Current Logical Pos: %d\n",
			string(event.text.text)[:],
			editor.cursor_logical_pos,
		)
	}
}


load_text_into_editor :: proc(editor: ^Editor, text: string) {
    // Clear old buffer
    gap_buffer_clear(&editor.gap_buffer)

    // Parameters
    chunk_size := 64 * 1024 // 64 KB chunks (tune this to your use case)
    total_len  := len(text)
    offset     := 0

    for offset < total_len {
        remaining := total_len - offset
        size := math.min(chunk_size, remaining)

        // Extract chunk slice
        chunk := text[offset : offset+size]
        bytes := transmute([]u8)chunk

        // Insert the chunk into the buffer
        insert_bytes(&editor.gap_buffer, bytes, editor.allocator)

        offset += size
    }

    // After full load, reset gap position and cursor
    editor.cursor_logical_pos = 0
    move_gap(&editor.gap_buffer, 0)
    update_cursor_position(editor)
}