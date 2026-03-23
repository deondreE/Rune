package main

import "base:runtime"
import "core:unicode/utf8"
import editor "editor"
import "vendor:glfw"

// Sync the visual cursor (line, col) from the logical buffer position.
sync_cursor :: proc(state: ^Editor_State) {
	line, col := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	state.cursor_data.line = line
	state.cursor_data.col = col
}

// Insert raw bytes at the cursor position.
insert_bytes_at_cursor :: proc(state: ^Editor_State, data: []u8) {
	if len(data) == 0 {return}
	editor.move_gap(&state.buffer, state.cursor_pos)
	editor.insert_bytes(&state.buffer, data)
	state.cursor_pos += len(data)
	sync_cursor(state)
}

// Insert a single Unicode codepoint at the cursor position.
insert_rune_at_cursor :: proc(state: ^Editor_State, r: rune) {
	buf, n := utf8.encode_rune(r)
	insert_bytes_at_cursor(state, buf[:n])
}

// Delete the character before the cursor (Backspace).
delete_before_cursor :: proc(state: ^Editor_State) {
	if state.cursor_pos == 0 {return}
	// Walk back over UTF-8 continuation bytes to find the codepoint start.
	pos := state.cursor_pos - 1
	for pos > 0 && (editor.char_at(&state.buffer, pos) & 0xC0) == 0x80 {
		pos -= 1
	}
	count := state.cursor_pos - pos
	editor.delete_bytes_range(&state.buffer, pos, count)
	state.cursor_pos = pos
	sync_cursor(state)
}

// Delete the character after the cursor (Delete key).
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
}

// Move cursor one codepoint to the left.
move_cursor_left :: proc(state: ^Editor_State) {
	if state.cursor_pos == 0 {return}
	pos := state.cursor_pos - 1
	for pos > 0 && (editor.char_at(&state.buffer, pos) & 0xC0) == 0x80 {
		pos -= 1
	}
	state.cursor_pos = pos
	sync_cursor(state)
}

// Move cursor one codepoint to the right.
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
}

// Move cursor up one line, preserving column where possible.
move_cursor_up :: proc(state: ^Editor_State) {
	line, col := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	if line == 0 {return}
	new_line := line - 1
	new_col := min(col, editor.get_line_length(&state.buffer, new_line))
	state.cursor_pos = editor.line_col_to_logical_pos(&state.buffer, new_line, new_col)
	sync_cursor(state)
}

// Move cursor down one line, preserving column where possible.
move_cursor_down :: proc(state: ^Editor_State) {
	line, col := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	line_count := editor.get_line_count(&state.buffer)
	if line >= line_count - 1 {return}
	new_line := line + 1
	new_col := min(col, editor.get_line_length(&state.buffer, new_line))
	state.cursor_pos = editor.line_col_to_logical_pos(&state.buffer, new_line, new_col)
	sync_cursor(state)
}

// Move cursor to the beginning of the current line.
move_cursor_home :: proc(state: ^Editor_State) {
	line, _ := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	state.cursor_pos = editor.line_col_to_logical_pos(&state.buffer, line, 0)
	sync_cursor(state)
}

// Move cursor to the end of the current line.
move_cursor_end :: proc(state: ^Editor_State) {
	line, _ := editor.logical_pos_to_line_col(&state.buffer, state.cursor_pos)
	end_col := editor.get_line_length(&state.buffer, line)
	state.cursor_pos = editor.line_col_to_logical_pos(&state.buffer, line, end_col)
	sync_cursor(state)
}

// ──────────────────────────────────────────────────────────────────────────────
// GLFW callbacks
// ──────────────────────────────────────────────────────────────────────────────

// char_callback fires for every printable Unicode character the user types.
// GLFW does NOT fire this for Tab, so Tab is handled in key_callback.
char_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	context = runtime.default_context()
	state := cast(^Editor_State)glfw.GetWindowUserPointer(window)
	if state == nil {return}
	insert_rune_at_cursor(state, codepoint)
}

// key_callback fires for special keys (arrows, backspace, enter, tab, …)
// and also repeats while a key is held.
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
		// Insert a real tab character; layers already expand it visually.
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
			state.cursor_pos = 0
			sync_cursor(state)
		} else {
			move_cursor_home(state)
		}

	case glfw.KEY_END:
		if ctrl {
			state.cursor_pos = editor.current_length(&state.buffer)
			sync_cursor(state)
		} else {
			move_cursor_end(state)
		}
	}
}
