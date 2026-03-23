package main

import "base:runtime"
import "core:unicode/utf8"
import editor "editor"
import "vendor:glfw"

// ---------------------------------------------------------------------------
// Cursor sync
// ---------------------------------------------------------------------------

// Recomputes line/col/visual_col from cursor_pos and writes them into the
// cursor layer.  Does NOT touch preferred_col so that up/down movement can
// keep the column sticky across short lines.
sync_cursor :: proc(state: ^Editor_State) {
	line, col := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	state.cursor_data.line = line
	state.cursor_data.col = col
	state.cursor_data.visual_col = editor.get_visual_col(
		&state.buffer,
		line,
		col,
		state.layer_ctx.tab_size,
	)
}

// Call after any horizontal movement or edit to anchor preferred_col to the
// current visual column.  Up/down movement intentionally skips this so the
// column stays sticky.
set_preferred_col :: proc(state: ^Editor_State) {
	state.preferred_col = state.cursor_data.visual_col
}

// ---------------------------------------------------------------------------
// Editing operations
// ---------------------------------------------------------------------------

// Insert raw bytes at the cursor and advance it.
insert_bytes_at_cursor :: proc(state: ^Editor_State, data: []u8) {
	if len(data) == 0 {return}
	editor.move_gap(&state.buffer, state.cursor_pos)
	editor.insert_bytes(&state.buffer, data)
	state.cursor_pos += len(data)
	sync_cursor(state)
	set_preferred_col(state)
}

// Insert a single Unicode codepoint at the cursor.
insert_rune_at_cursor :: proc(state: ^Editor_State, r: rune) {
	buf, n := utf8.encode_rune(r)
	insert_bytes_at_cursor(state, buf[:n])
}

// Backspace: delete the codepoint immediately before the cursor.
delete_before_cursor :: proc(state: ^Editor_State) {
	if state.cursor_pos == 0 {return}
	// Walk back over any UTF-8 continuation bytes to find codepoint start.
	pos := state.cursor_pos - 1
	for pos > 0 && (editor.char_at(&state.buffer, pos) & 0xC0) == 0x80 {
		pos -= 1
	}
	editor.delete_bytes_range(&state.buffer, pos, state.cursor_pos - pos)
	state.cursor_pos = pos
	sync_cursor(state)
	set_preferred_col(state)
}

// Delete key: delete the codepoint immediately after the cursor.
delete_after_cursor :: proc(state: ^Editor_State) {
	total := editor.current_length(&state.buffer)
	if state.cursor_pos >= total {return}
	first := editor.char_at(&state.buffer, state.cursor_pos)
	char_len: int
	switch {
	case first < 0x80:
		char_len = 1
	case first < 0xE0:
		char_len = 2
	case first < 0xF0:
		char_len = 3
	case:
		char_len = 4
	}
	editor.delete_bytes_range(&state.buffer, state.cursor_pos, char_len)
	sync_cursor(state)
	set_preferred_col(state)
}

// ---------------------------------------------------------------------------
// Cursor movement
// ---------------------------------------------------------------------------

// Move one codepoint to the left.
move_cursor_left :: proc(state: ^Editor_State) {
	if state.cursor_pos == 0 {return}
	pos := state.cursor_pos - 1
	for pos > 0 && (editor.char_at(&state.buffer, pos) & 0xC0) == 0x80 {
		pos -= 1
	}
	state.cursor_pos = pos
	sync_cursor(state)
	set_preferred_col(state)
}

// Move one codepoint to the right.
move_cursor_right :: proc(state: ^Editor_State) {
	total := editor.current_length(&state.buffer)
	if state.cursor_pos >= total {return}
	first := editor.char_at(&state.buffer, state.cursor_pos)
	char_len: int
	switch {
	case first < 0x80:
		char_len = 1
	case first < 0xE0:
		char_len = 2
	case first < 0xF0:
		char_len = 3
	case:
		char_len = 4
	}
	state.cursor_pos = min(total, state.cursor_pos + char_len)
	sync_cursor(state)
	set_preferred_col(state)
}

// Move up one line, landing on the byte column closest to preferred_col.
// Tabs are snapped to their start position.
move_cursor_up :: proc(state: ^Editor_State) {
	line, _ := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	if line == 0 {return}
	new_line := line - 1
	byte_col := editor.visual_col_to_byte_col(
		&state.buffer,
		new_line,
		state.preferred_col,
		state.layer_ctx.tab_size,
	)
	state.cursor_pos = editor.line_col_to_logical_pos(&state.buffer, new_line, byte_col)
	sync_cursor(state)
	// preferred_col intentionally NOT updated – keeps column sticky.
}

// Move down one line, landing on the byte column closest to preferred_col.
move_cursor_down :: proc(state: ^Editor_State) {
	line, _ := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	line_count := editor.get_line_count(&state.buffer)
	if line >= line_count - 1 {return}
	new_line := line + 1
	byte_col := editor.visual_col_to_byte_col(
		&state.buffer,
		new_line,
		state.preferred_col,
		state.layer_ctx.tab_size,
	)
	state.cursor_pos = editor.line_col_to_logical_pos(&state.buffer, new_line, byte_col)
	sync_cursor(state)
	// preferred_col intentionally NOT updated.
}

// Move to the first byte of the current line.
move_cursor_home :: proc(state: ^Editor_State) {
	line, _ := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	state.cursor_pos = editor.line_col_to_logical_pos(&state.buffer, line, 0)
	sync_cursor(state)
	set_preferred_col(state)
}

// Move to the last byte of the current line.
move_cursor_end :: proc(state: ^Editor_State) {
	line, _ := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	end_col := editor.get_line_length(&state.buffer, line)
	state.cursor_pos = editor.line_col_to_logical_pos(&state.buffer, line, end_col)
	sync_cursor(state)
	set_preferred_col(state)
}

// ---------------------------------------------------------------------------
// GLFW callbacks
// ---------------------------------------------------------------------------

// Fires for every printable Unicode character typed.
// GLFW does not fire this for Tab, so Tab is handled in key_callback.
char_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	context = runtime.default_context()
	state := cast(^Editor_State)glfw.GetWindowUserPointer(window)
	if state == nil {return}
	insert_rune_at_cursor(state, codepoint)
}

// Fires for special keys (and repeats while held).
key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()
	if action != glfw.PRESS && action != glfw.REPEAT {return}

	state := cast(^Editor_State)glfw.GetWindowUserPointer(window)
	if state == nil {return}

	ctrl := (mods & glfw.MOD_CONTROL) != 0

	switch key {
	case glfw.KEY_BACKSPACE:
		delete_before_cursor(state)

	case glfw.KEY_DELETE:
		delete_after_cursor(state)

	case glfw.KEY_ENTER, glfw.KEY_KP_ENTER:
		insert_bytes_at_cursor(state, []u8{'\n'})

	case glfw.KEY_TAB:
		// Store a real '\t'; the text and cursor layers expand it visually.
		insert_bytes_at_cursor(state, []u8{'\t'})

	case glfw.KEY_LEFT:
		move_cursor_left(state)

	case glfw.KEY_RIGHT:
		move_cursor_right(state)

	case glfw.KEY_UP:
		move_cursor_up(state)

	case glfw.KEY_DOWN:
		move_cursor_down(state)

	case glfw.KEY_HOME:
		if ctrl {
			// Ctrl+Home → top of file
			state.cursor_pos = 0
			sync_cursor(state)
			set_preferred_col(state)
		} else {
			move_cursor_home(state)
		}

	case glfw.KEY_END:
		if ctrl {
			// Ctrl+End → end of file
			state.cursor_pos = editor.current_length(&state.buffer)
			sync_cursor(state)
			set_preferred_col(state)
		} else {
			move_cursor_end(state)
		}
	}
}
