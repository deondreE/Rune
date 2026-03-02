package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:unicode/utf8"
import "core:math"

return_file_contents :: proc(filename: string) -> string {
	data: string = ""

	abs_path, ok := filepath.abs(filename, context.temp_allocator)
	if !ok {
		fmt.printf("Failed to resolve absolute path for '%s'\n", filename)
		return data
	}

	contents, err := os.read_entire_file(abs_path)
	delete(abs_path)
	if err {
		fmt.printf("Failed to read file '%s' (error: %v)\n", filename, err)
		return data
	}

	data = string(contents)
	delete(contents)
	return data
}

is_word_char :: proc(c: u8) -> bool {
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' // optional
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

load_text_into_editor :: proc(editor: ^Editor, text: string) {
	gap_buffer_clear(&editor.gap_buffer)

	chunk_size := 64 * 1024 // This could be larger
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
	update_cursor_position(editor)
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