package editor

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import "treesitter"
import sdl "vendor:sdl3"

UI_Focus_Target :: enum {
	Editor,
	FileExplorer,
	SearchBar,
	None,
}

Editor :: struct {
	allocator:             mem.Allocator,
	window:                ^sdl.Window,
	renderer:              ^sdl.Renderer,
	batch_renderer:        Batch_Renderer,
	text_renderer:         Text_Renderer,
	gap_buffer:            Gap_Buffer,
	minimap:               Minimap,
	cursor_logical_pos:    int,
	cursor_line_idx:       int,
	cursor_col_idx:        int,
	scroll_x:              int,
	scroll_y:              int,
	line_height:           i32,
	char_width:            f32,
	file_explorer:         File_Explorer,
	theme:                 Theme,
	search_bar:            Search_Bar,
	context_menu:          Context_Menu,
	menu_bar:              Menu_Bar,
	status_bar:            Status_Bar,
	selection_start:       int,
	selection_end:         int,
	has_selection:         bool,
	mouse_down:            bool,
	mouse_dragging:        bool,
	_is_mouse_selecting:   bool,
	last_click_time:       u64,
	last_click_pos:        int,
	double_click_ms:       u64,
	default_white_texture: ^sdl.Texture,
	treesitter:            treesitter.Treesitter,
	focus_target:          UI_Focus_Target,
	lsp_client:            ^LSP_Client,
	lsp_enabled:           bool,
	tab_bar: Tab_Bar,
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

	if editor.lsp_enabled && editor.lsp_client != nil {
		editor_notify_lsp_change(editor, editor.lsp_client)
	}

	if tab := get_active_tab(&editor.tab_bar); tab != nil {
		mark_tab_modified(tab)
	}
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
		delete_selection(editor)
	}

	temp_str := utf8.runes_to_string({r}, editor.allocator)
	defer delete(temp_str, editor.allocator)

	fmt.printf("Encoded to %d bytes: %v\n", len(temp_str), transmute([]u8)temp_str)

	insert_bytes(&editor.gap_buffer, transmute([]u8)temp_str, editor.allocator)
	editor.cursor_logical_pos += len(temp_str)

	update_cursor_position(editor)
	move_gap(&editor.gap_buffer, editor.cursor_logical_pos)

	update_parse_tree(editor)

	if editor.lsp_enabled && editor.lsp_client != nil {
		editor_notify_lsp_change(editor, editor.lsp_client)
	}

	if tab := get_active_tab(&editor.tab_bar); tab != nil {
		mark_tab_modified(tab)
	}
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
	theme, _ := load_user_theme("assets/settings/theme.json", allocator)
	editor.theme = theme

	text_renderer, ok := init_text_renderer(
		"assets/fonts/MapleMono-NF-Regular.ttf",
		16,
		renderer,
		allocator,
	)
	if !ok {
		fmt.println("Failed to initialize text renderer")
	}
	editor.text_renderer = text_renderer
	editor.minimap = init_minimap()
	editor.double_click_ms = 300
	editor.status_bar = init_status_bar()
	editor.gap_buffer = init_gap_buffer(allocator)
	editor.cursor_logical_pos = 0
	editor.batch_renderer = init_batch_renderer(editor.renderer, allocator)
	editor.cursor_line_idx = 0
	editor.cursor_col_idx = 0
	editor.line_height = text_renderer.line_height
	editor.char_width = text_renderer.char_width
	editor.search_bar = init_search_bar(allocator)
	editor._is_mouse_selecting = false
	editor.focus_target = .Editor
	editor.tab_bar = init_tab_bar(allocator)

	initial_text := `Hello, Deondre!
This is your Odin code editor.
Let's make some magic happen!`

	tab_idx := create_tab(&editor.tab_bar, "Untitled")
	editor.tab_bar.active_tab_idx = tab_idx


    if tab := get_active_tab(&editor.tab_bar); tab != nil {
        insert_bytes(&tab.gap_buffer, transmute([]u8)initial_text, editor.allocator)
        load_tab_state_to_editor(&editor, tab)
    }


	white_surface := sdl.CreateSurface(1, 1, sdl.PixelFormat.RGBA32)
	if white_surface == nil {
		fmt.eprintln("Failed to create white surface:", sdl.GetError())
	}
	_ = sdl.FillSurfaceRect(white_surface, nil, 0xFFFFFFFF)

	editor.default_white_texture = sdl.CreateTextureFromSurface(editor.renderer, white_surface)
	if editor.default_white_texture == nil {
		fmt.eprintln("Failed to create default white texture", sdl.GetError())
	}
	sdl.DestroySurface(white_surface)

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

	// TODO: Look into making this process more efficient.
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
	editor.menu_bar = init_menu_bar(
		allocator,
		"assets/fonts/MapleMono-NF-Regular.ttf",
		10,
		renderer,
		&editor,
	)

	editor.lsp_enabled = true
	if editor.lsp_enabled {
		lsp, success := editor_init_lsp(&editor, "ols", "odin")
		if !success {
			fmt.println("LSP initialization failed, continuing without LSP")
			editor.lsp_enabled = false
		}
		editor.lsp_client = lsp
	}

	fmt.println("Editor initialized.")
	return editor
}

update_parse_tree :: proc(editor: ^Editor) {
	code := get_text(&editor.gap_buffer, editor.allocator)
	ast := treesitter.parse_source(&editor.treesitter, code, editor.allocator)

	fmt.println("Tree-Sitter AST (first 200 chars):")
	if len(ast) > 200 {
		fmt.println(ast[:200], "...")
	} else {
		fmt.println(ast)
	}
}

destroy_editor :: proc(editor: ^Editor) {
	destroy_search_bar(&editor.search_bar, editor.allocator)
	destroy_context_menu(&editor.context_menu)
	destroy_gap_buffer(&editor.gap_buffer, editor.allocator)
	destroy_file_explorer(&editor.file_explorer)
	destroy_text_renderer(&editor.text_renderer)
	destroy_batch_renderer(&editor.batch_renderer)

	if editor.default_white_texture != nil {
		sdl.DestroyTexture(editor.default_white_texture)
	}

	destroy_tab_bar(&editor.tab_bar)
	
	if editor.lsp_client != nil {
		lsp_client_shutdown(editor.lsp_client)
		free(editor.lsp_client, editor.allocator)
	}

	fmt.println("Editor destroyed.")
}

update :: proc(editor: ^Editor, dt: f64) {}

render_diagnostics :: proc(editor: ^Editor) {
	if !editor.lsp_enabled || editor.lsp_client == nil {
		return
	}

	lines := get_lines(&editor.gap_buffer, editor.allocator)
	defer {
		for line in lines {
			delete(line, editor.allocator)
		}
		delete(lines, editor.allocator)
	}
	menu_offset_y := f32(editor.menu_bar.height) + 10
	file_explorer_width := editor.file_explorer.is_visible ? editor.file_explorer.width : 0
	text_origin_x := f32(file_explorer_width)
	gutter_width := f32(60)

	// renders diagnostic squiggles
	for diagnostic in editor.lsp_client.diagnostics {
		line_idx := diagnostic.range.start.line
		if line_idx < 0 || line_idx >= len(lines) {
			continue
		}

		y := menu_offset_y + f32(line_idx * int(editor.line_height) - editor.scroll_y)
		line_text := lines[line_idx]

		start_col := diagnostic.range.start.character
		end_col := diagnostic.range.end.character

		start_col = clamp(start_col, 0, len(line_text))
		end_col = clamp(end_col, 0, len(line_text))

		width_start := measure_text_width(&editor.text_renderer, line_text[:start_col])
		width_end := measure_text_width(&editor.text_renderer, line_text[:end_col])

		x_start := text_origin_x + gutter_width + width_start - f32(editor.scroll_x)
		x_end := text_origin_x + gutter_width + width_end - f32(editor.scroll_x)

		color: sdl.Color
		switch diagnostic.severity {
		case .Error:
			color = {255, 0, 0, 255} // Red
		case .Warning:
			color = {255, 165, 0, 255} // Orange
		case .Information:
			color = {0, 191, 255, 255} // Light blue
		case .Hint:
			color = {200, 200, 200, 255} // Gray
		}

		_ = sdl.SetRenderDrawColor(editor.renderer, color.r, color.g, color.b, color.a)

		squiggle_y := y + f32(editor.line_height) - 2
		step := f32(3)
		current_x := x_start

		for current_x < x_end {
			next_x := min(current_x + step, x_end)
			wave_offset := f32(2) * ((int(current_x / step) % 2 == 0) ? f32(1) : f32(-1))

			_ = sdl.RenderLine(
				editor.renderer,
				current_x,
				squiggle_y + wave_offset,
				next_x,
				squiggle_y - wave_offset,
			)

			current_x = next_x
		}
	}
}

render :: proc(editor: ^Editor) {
	_ = sdl.SetRenderDrawColor(
		editor.renderer,
		editor.theme.background.r,
		editor.theme.background.g,
		editor.theme.background.b,
		editor.theme.background.a,
	)
	_ = sdl.RenderClear(editor.renderer)

	window_w: i32
	window_h: i32
	_ = sdl.GetWindowSize(editor.window, &window_w, &window_h)

	menu_offset_y := f32(editor.menu_bar.height) + 10
	tab_bar_y := menu_offset_y
	content_offset_y := menu_offset_y + f32(editor.tab_bar.height)
	file_explorer_width := editor.file_explorer.is_visible ? editor.file_explorer.width : 0
	text_origin_x := f32(file_explorer_width)
	editor_area_x := f32(file_explorer_width)
	start_sel, end_sel := selection_range(editor)

	begin_frame(&editor.batch_renderer)

	render_tab_bar(
    &editor.tab_bar,
    editor.renderer,
    &editor.text_renderer,  
    editor.allocator,       
    window_w,
	window_h - i32(editor.status_bar.height)
    )			
	
	render_search_bar(
		&editor.search_bar,
		&editor.text_renderer,
		editor.renderer,
		editor,
		window_w,
		window_h,
	)

	if editor.file_explorer.is_visible {
		render_file_explorer(&editor.file_explorer, editor.renderer, editor)

		_ = sdl.SetRenderDrawColor(editor.renderer, 0x40, 0x40, 0x40, 0xFF)
		divider_rect := sdl.FRect {
			x = f32(editor.file_explorer.width) - 1.0,
			y = menu_offset_y,
			w = 1.0,
			h = f32(window_h) - menu_offset_y,
		}
		_ = sdl.RenderFillRect(editor.renderer, &divider_rect)
	}

	lines := get_lines(&editor.gap_buffer, editor.allocator)
	defer {
		for line in lines {
			delete(line, editor.allocator)
		}
		delete(lines, editor.allocator)
	}

	if len(lines) == 0 {
		render_status_bar(
			&editor.status_bar,
			&editor.text_renderer,
			editor.renderer,
			editor,
			int(window_w),
			int(window_h),
			0,
			0,
			editor.allocator,
		)
		render_context_menu(&editor.context_menu, editor.renderer, &editor.text_renderer)
		render_menu_bar(&editor.menu_bar, editor.renderer, window_w)

		render_diagnostics(editor)

		sdl.RenderPresent(editor.renderer)
		return
	}

	start_line := max(0, editor.scroll_y / int(editor.line_height))
	visible_lines := int(f32(window_h) / f32(editor.line_height)) + 2
	end_line := min(len(lines), start_line + visible_lines)

	start_line = clamp(start_line, 0, len(lines))
	end_line = clamp(end_line, 0, len(lines))

	if editor.has_selection && start_sel != end_sel {
		r_color := editor.theme.selection_bg

		sel_line_start, sel_col_start := logical_pos_to_line_col(&editor.gap_buffer, start_sel)
		sel_line_end, sel_col_end := logical_pos_to_line_col(&editor.gap_buffer, end_sel)

		// Clamp selection lines to visible range for performance
		render_start := max(sel_line_start, start_line)
		render_end := min(sel_line_end + 1, end_line)

		for i := render_start; i < render_end && i < len(lines); i += 1 {
			y := menu_offset_y + f32(i * int(editor.line_height) - editor.scroll_y)

			// Skip off-screen
			if y < -f32(editor.line_height) || y > f32(window_h) {
				continue
			}

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

			// Clamp columns to line length
			line_start_col = clamp(line_start_col, 0, len(line_text))
			line_end_col = clamp(line_end_col, 0, len(line_text))

			width_start := measure_text_width(&editor.text_renderer, line_text[:line_start_col])
			width_end := measure_text_width(&editor.text_renderer, line_text[:line_end_col])

			rect := sdl.FRect {
				x = line_x + text_origin_x + f32(width_start),
				y = y,
				w = f32(width_end - width_start),
				h = f32(editor.line_height),
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

	flush_batches(&editor.batch_renderer)

	// Core Editor Text & Cursor
	gutter_width := f32(60)
	text_area_x := text_origin_x + gutter_width

	// Obtain syntax tokens once per frame
	full_source := get_text(&editor.gap_buffer, editor.allocator)
	defer delete(full_source, editor.allocator)

	tokens, count := treesitter.get_hightlight_tokens(
		full_source,
		editor.treesitter.lang,
		context.temp_allocator,
	)
	defer if count > 0 {
		treesitter.ts_free_tokens(&tokens[0], count)
	}

	// Pre-calculate line offsets for syntax highlighting
	line_offsets := make([dynamic]int, len(lines), context.temp_allocator)
	defer delete(line_offsets)

	current_offset := 0
	for line, i in lines {
		line_offsets[i] = current_offset
		// Account for line content + newline character (except last line)
		current_offset += len(line)
		if i < len(lines) - 1 {
			current_offset += 1 // newline
		}
	}

	// Render visible lines only
	for i := start_line; i < end_line; i += 1 {
		y := menu_offset_y + f32(i * int(editor.line_height) - editor.scroll_y)

		if y < -f32(editor.line_height) || y > f32(window_h) {
			continue
		}

		// Line numbers
		line_num := i + 1
		line_num_str := fmt.aprintf("%d", line_num)
		defer delete(line_num_str, editor.allocator)

		line_num_color := editor.theme.text
		if i == editor.cursor_line_idx {
			line_num_color = editor.theme.line_number_text
		}

		render_text(
			&editor.text_renderer,
			editor.renderer,
			line_num_str,
			text_origin_x + 5,
			y,
			editor.allocator,
			line_num_color,
		)

		// Syntax highlighted text
		if i < len(lines) && i < len(line_offsets) {
			line_offset := line_offsets[i]
			render_syntax_text(editor, lines[i], line_offset, y, tokens, text_area_x)
		}
	}

	// Cursor rendering
	cursor_x := text_origin_x + gutter_width - f32(editor.scroll_x)
	cursor_y :=
		menu_offset_y + f32(editor.cursor_line_idx * int(editor.line_height) - editor.scroll_y)

	// Calculate cursor X position
	if editor.cursor_line_idx >= 0 && editor.cursor_line_idx < len(lines) {
		current_line := lines[editor.cursor_line_idx]
		cursor_pos_in_line := clamp(editor.cursor_col_idx, 0, len(current_line))

		if cursor_pos_in_line > 0 {
			text_before_cursor := current_line[:cursor_pos_in_line]
			text_width := measure_text_width(&editor.text_renderer, text_before_cursor)
			cursor_x += text_width
		}
	}

	// Blink cursor
	cursor_rect := sdl.FRect {
		x = cursor_x,
		y = cursor_y,
		w = 2.0,
		h = f32(editor.line_height),
	}

	blink_interval_ms :: 500
	current_time_ms := sdl.GetTicks()
	if (current_time_ms / u64(blink_interval_ms)) % 2 == 0 {
		_ = sdl.SetRenderDrawColor(editor.renderer, 0xFF, 0xFF, 0xFF, 0xFF)
		_ = sdl.RenderFillRect(editor.renderer, &cursor_rect)
	}

	// Status bars and menus
	render_status_bar(
		&editor.status_bar,
		&editor.text_renderer,
		editor.renderer,
		editor,
		int(window_w),
		int(window_h),
		editor.cursor_line_idx,
		editor.cursor_col_idx,
		editor.allocator,
	)
	render_context_menu(&editor.context_menu, editor.renderer, &editor.text_renderer)
	render_menu_bar(&editor.menu_bar, editor.renderer, window_w)

	// Minimap (if enabled)
	if true {
		render_minimap(&editor.minimap, editor, editor.renderer, window_w, window_h)
	}

	sdl.RenderPresent(editor.renderer)
}

// Helper to ensure render_syntax_text handles bounds properly
render_syntax_text :: proc(
	editor: ^Editor,
	line_text: string,
	line_offset: int,
	y: f32,
	tokens: []treesitter.Token,
	line_x: f32,
) {
	if len(line_text) == 0 {
		return
	}

	// Validate line_text
	if !is_valid_text(line_text) {
		return
	}

	current_x := line_x - f32(editor.scroll_x)
	last_end := 0

	for token in tokens {
		// Skip tokens that don't overlap this line
		if int(token.end) <= line_offset || int(token.start) >= line_offset + len(line_text) {
			continue
		}

		// Calculate token position relative to current line
		token_start := max(0, int(token.start) - line_offset)
		token_end := min(len(line_text), int(token.end) - line_offset)

		// Render any plain text before this token
		if token_start > last_end {
			plain_text := line_text[last_end:token_start]
			if len(plain_text) > 0 {
				render_text(
					&editor.text_renderer,
					editor.renderer,
					plain_text,
					current_x,
					y,
					editor.allocator,
					editor.theme.text,
				)
				width := measure_text_width(&editor.text_renderer, plain_text)
				current_x += width
			}
		}

		// Render the token with syntax color
		if token_start < token_end {
			fragment := line_text[token_start:token_end]
			if len(fragment) > 0 {
				color := map_to_color(token.kind, editor.theme)
				render_text(
					&editor.text_renderer,
					editor.renderer,
					fragment,
					current_x,
					y,
					editor.allocator,
					color,
				)
				width := measure_text_width(&editor.text_renderer, fragment)
				current_x += width
			}
			last_end = token_end
		}
	}

	// Render any remaining plain text after the last token
	if last_end < len(line_text) {
		remaining_text := line_text[last_end:]
		if len(remaining_text) > 0 {
			render_text(
				&editor.text_renderer,
				editor.renderer,
				remaining_text,
				current_x,
				y,
				editor.allocator,
				editor.theme.text,
			)
		}
	}
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

	update_parse_tree(editor)

	if editor.lsp_enabled && editor.lsp_client != nil {
		editor_notify_lsp_change(editor, editor.lsp_client)
	}

	if tab := get_active_tab(&editor.tab_bar); tab != nil {
		mark_tab_modified(tab)
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

	update_parse_tree(editor)
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
	window_w: i32
	window_h: i32
	_ = sdl.GetWindowSize(editor.window, &window_w, &window_h)

	// --- Focus handling section ---
	if editor.search_bar.is_visible {
		if handle_search_bar_event(&editor.search_bar, editor, event) {
			editor.focus_target = .SearchBar
			return
		}
	}

	if editor.file_explorer.is_visible {
		if handle_file_explorer_event(&editor.file_explorer, event) {
			editor.focus_target = .FileExplorer
			return
		}

		if event.type == sdl.EventType.MOUSE_BUTTON_DOWN {
			mouse_x := f32(event.button.x)
			mouse_y := f32(event.button.y)
			x_max := editor.file_explorer.x + editor.file_explorer.width
			y_max :=
				editor.file_explorer.y +
				f32(editor.file_explorer.visible_height * int(editor.file_explorer.item_height))

			in_explorer :=
				mouse_x >= editor.file_explorer.x &&
				mouse_x <= x_max &&
				mouse_y >= editor.file_explorer.y &&
				mouse_y <= y_max

			if !in_explorer {
				editor.focus_target = .Editor
			}
		}
	}

	if handle_tab_bar_event(&editor.tab_bar, event, window_h) {
		if prev_tab := get_active_tab(&editor.tab_bar); prev_tab != nil {
			load_tab_state_to_editor(editor, prev_tab)
		}
	
		if new_tab := get_active_tab(&editor.tab_bar); new_tab != nil {
			load_tab_state_to_editor(editor, new_tab)
		}

		return 
	}

	switch editor.focus_target {
	case .FileExplorer:
		_ = handle_file_explorer_event(&editor.file_explorer, event)
		return
	case .SearchBar:
		if handle_search_bar_event(&editor.search_bar, editor, event) {
			return
		}
	case .Editor:
		// continue below for normal editor input handling
		handle_menu_bar_event(&editor.menu_bar, event, editor.window)
	case .None:
		return
	}

	// --- EDITOR MOUSE & KEYBOARD HANDLING ---
	#partial switch event.type {
	case .MOUSE_WHEEL:
		scroll_delta := int(event.wheel.y) * int(editor.line_height)
		editor.scroll_y -= int(scroll_delta)

		lines := get_lines(&editor.gap_buffer, editor.allocator)
		total_lines := len(lines)
		defer {
			for line in lines {delete(line, editor.allocator)}
			delete(lines, editor.allocator)
		}
		max_scroll := max(0, total_lines * int(editor.line_height) - 400)
		editor.scroll_y = clamp(editor.scroll_y, 0, max_scroll)

	case .MOUSE_BUTTON_DOWN:
		if event.button.button == sdl.BUTTON_LEFT {
			now := sdl.GetTicks()
			mouse_x := event.button.x
			mouse_y := event.button.y

			pos := screen_to_logical_pos(editor, int(mouse_x), int(mouse_y))

			if (handle_minimap_click(&editor.minimap, editor, mouse_x, mouse_y, window_w, window_h)) 
			{
				break
			}

			// Double-click to select word
			if (now - editor.last_click_time) <= editor.double_click_ms &&
			   abs(pos - editor.last_click_pos) < 2 {
				select_word_at_pos(editor, pos)
			} else {
				editor.cursor_logical_pos = pos
				editor.selection_start = pos
				editor.selection_end = pos
				editor.has_selection = false
				editor.mouse_down = true
			}

			editor.focus_target = .Editor
			editor.last_click_time = now
			editor.last_click_pos = pos
		}

		if event.button.button == sdl.BUTTON_RIGHT {
			show_context_menu(&editor.context_menu, f32(event.button.x), f32(event.button.y))
			handle_context_menu_event(&editor.context_menu, event)
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

		if event.key.mod == sdl.KMOD_LCTRL ||
		   event.key.mod == sdl.KMOD_LALT ||
		   event.key.mod == sdl.KMOD_LGUI {
			switch event.key.key {
			case ' ':
				fmt.print("Testing")
				if editor.lsp_enabled && editor.lsp_client != nil {
					editor_request_completion(editor, editor.lsp_client)
				}
			case 'p':
				// CTRL+P → Toggle Search
				editor.search_bar.is_visible = !editor.search_bar.is_visible
				if editor.search_bar.is_visible {
					editor.focus_target = .SearchBar
					editor.search_bar.caret_pos = 0
				} else {
					editor.focus_target = .Editor
				}
				return

			case 'a':
				// CTRL+A
				editor.selection_start = 0
				editor.selection_end = current_length(&editor.gap_buffer)
				editor.has_selection = true
				return

			case 'w':
				if len(editor.tab_bar.tabs) > 0 {
					old_idx := editor.tab_bar.active_tab_idx
					close_tab(&editor.tab_bar, old_idx)
					
					// Load new active tab
					if tab := get_active_tab(&editor.tab_bar); tab != nil {
						load_tab_state_to_editor(editor, tab)
					} else {
						// No tabs left, create a new one
						tab_idx := create_tab(&editor.tab_bar, "Untitled")
						editor.tab_bar.active_tab_idx = tab_idx
						if new_tab := get_active_tab(&editor.tab_bar); new_tab != nil {
							load_tab_state_to_editor(editor, new_tab)
						}
					}
				}
				return
			case 's':
				if tab := get_active_tab(&editor.tab_bar); tab != nil {
					save_editor_state_to_tab(editor, tab)
					if len(tab.file_path) == 0 {
						// TODO: Show save dialog
						fmt.println("Save as... (not implemented)")
					} else {
						save_tab(tab)
					}
				}
				return
			case 'o':
				// TODO: Show file picker dialog
				fmt.println("Open file... (not implemented)")
				return
			case 'c':
				copy_selection_to_clipboard(editor)
				return

			case 'x':
				copy_selection_to_clipboard(editor)
				delete_selection(editor)
				return
			case 'v':
				paste_from_clipboard(editor)
				return

			case 'b':
				editor.file_explorer.is_visible = !editor.file_explorer.is_visible
				editor.focus_target = editor.file_explorer.is_visible ? .FileExplorer : .Editor
				return

			case 'i':
				prototype_run()
				return

			case ',':
				load_settings_file(editor)
				return

			case 1073741903:
				// Ctrl + →
				move_cursor_word_right(editor)
				return

			case 1073741904:
				// Ctrl + ←
				move_cursor_word_left(editor)
				return
			}
		}

		// --- Normal keypresses ---
		switch event.key.key {
		case 27:
			editor.focus_target = .Editor
			clear_selection(editor)

		case 9:
			// Tab
			insert_char(editor, '\t')
			editor.cursor_logical_pos += editor.gap_buffer.tab_size
			update_cursor_position(editor)

		case 13:
			insert_char(editor, '\n')

		case 8:
			handle_backspace(editor)

		case 46:
			fmt.println("Delete key pressed (not yet implemented).")

		case 1073741904:
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
			editor.focus_target = editor.file_explorer.is_visible ? .FileExplorer : .Editor
			return
		}

	case sdl.EventType.TEXT_INPUT:
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
	gap_buffer_clear(&editor.gap_buffer)

	chunk_size := 64 * 1024 // 64 KB chunks (tune this to your use case)
	total_len := len(text)
	offset := 0

	for offset < total_len {
		remaining := total_len - offset
		size := math.min(chunk_size, remaining)

		chunk := text[offset:offset + size]
		bytes := transmute([]u8)chunk

		insert_bytes(&editor.gap_buffer, bytes, editor.allocator)

		offset += size
	}

	editor.cursor_logical_pos = 0
	move_gap(&editor.gap_buffer, 0)
	update_cursor_position(editor)
}
