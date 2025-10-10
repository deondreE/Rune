package editor

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

// Some max around 4096
GAP_BUFFER_INITIAL_CAPACITY :: 256

Gap_Buffer :: struct {
	buffer:      []u8,
	gap_start:   int,
	gap_end:     int,
	capacity:    int,
	line_starts: [dynamic]int,
	allocator:   mem.Allocator,
}

// returns the current size of the gap;
gap_size :: proc(gb: ^Gap_Buffer) -> int {
	return gb.gap_end - gb.gap_start
}

// the current number of
current_length :: proc(gb: ^Gap_Buffer) -> int {
	return gb.capacity - gap_size(gb)
}

init_gap_buffer :: proc(allocator: mem.Allocator = context.allocator) -> Gap_Buffer {
	buffer := make([]u8, GAP_BUFFER_INITIAL_CAPACITY, allocator)
	line_starts := make([dynamic]int, allocator)
	append(&line_starts, 0)

	return Gap_Buffer {
		buffer = buffer,
		gap_start = 0,
		gap_end = len(buffer),
		capacity = len(buffer),
		line_starts = line_starts,
		allocator = allocator,
	}
}

destroy_gap_buffer :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator = context.allocator) {
	if gb.buffer != nil {
		delete(gb.buffer, allocator)
		gb.buffer = nil
	}
	delete(gb.line_starts)
}

// ensure_gap_size - the gap is at least `required_size`.
ensure_gap_size :: proc(
	gb: ^Gap_Buffer,
	required_size: int,
	allocator: mem.Allocator = context.allocator,
) {
	if gap_size(gb) >= required_size {
		return // gap is already large enough
	}

	new_capacity := gb.capacity + (required_size - gap_size(gb) + GAP_BUFFER_INITIAL_CAPACITY - 1) // Grown by at least required_size.
	new_capacity = (new_capacity / GAP_BUFFER_INITIAL_CAPACITY + 1) * GAP_BUFFER_INITIAL_CAPACITY // Always grow in blocks
	if new_capacity < gb.capacity + required_size {
		new_capacity = gb.capacity + required_size + GAP_BUFFER_INITIAL_CAPACITY
	}

	new_buffer := make([]u8, new_capacity, allocator)

	copy(new_buffer[0:gb.gap_start], gb.buffer[0:gb.gap_start])

	old_data_after_gap_len := gb.capacity - gb.gap_end
	new_gap_end := new_capacity - old_data_after_gap_len
	copy(new_buffer[new_gap_end:], gb.buffer[gb.gap_end:])

	delete(gb.buffer, allocator)
	gb.buffer = new_buffer
	gb.gap_end = new_gap_end
	gb.capacity = new_capacity

	fmt.println(
		"Gap buffer resized to",
		gb.capacity,
		"bytes. Gap start:",
		gb.gap_start,
		"gap end:",
		gb.gap_end,
	)
}

// move_gap move the gap_start `new_pos`.
move_gap :: proc(gb: ^Gap_Buffer, new_logical_pos: int) {
	pos := new_logical_pos
	// set to valid range
	if pos < 0 {
		pos = 0
	}
	if pos > current_length(gb) {
		pos = current_length(gb)
	}
	if pos == gb.gap_start {
		return // Gap is already at the disired pos.
	}

	// determine the direction of movement
	if new_logical_pos < gb.gap_start {
		byes_to_move := gb.gap_start - pos
		copy(gb.buffer[gb.gap_end - byes_to_move:], gb.buffer[pos:gb.gap_start])
		gb.gap_start = pos
		gb.gap_end -= byes_to_move
	} else {
		byes_to_move := pos - gb.gap_start
		copy(gb.buffer[gb.gap_start:pos], gb.buffer[gb.gap_end:gb.gap_end + byes_to_move])
		gb.gap_start = pos
		gb.gap_end += byes_to_move
	}
}

// inserts a slice of bytes at the current gap_start pos.
insert_bytes :: proc(gb: ^Gap_Buffer, data: []u8, allocator: mem.Allocator = context.allocator) {
	if len(data) == 0 {
		return
	}
	ensure_gap_size(gb, len(data), allocator)

	// Track newlines in inserted data
	insert_pos := gb.gap_start
	for byte_val, i in data {
		if byte_val == '\n' {
			// Add new line start at position after this newline
			line_start_pos := insert_pos + i + 1
			// Insert into line_starts array at correct position
			insert_line_start(gb, line_start_pos)
		}
	}

	copy(gb.buffer[gb.gap_start:], data)
	gb.gap_start += len(data)

	// Update all line starts after insertion point
	update_line_starts_after_insert(gb, insert_pos, len(data))
}

insert_line_start :: proc(gb: ^Gap_Buffer, pos: int) {
	// Find where to insert this line start
	insert_idx := len(gb.line_starts)
	for i, line_start in gb.line_starts {
		if pos < line_start {
			insert_idx = i
			break
		}
	}

	// Insert at the found position
	inject_at(&gb.line_starts, insert_idx, pos)
}

update_line_starts_after_insert :: proc(gb: ^Gap_Buffer, insert_pos: int, insert_len: int) {
	for &line_start in gb.line_starts {
		if line_start > insert_pos {
			line_start += insert_len
		}
	}
}

// Deletes a range of bytes between [start, end]  from logical text.
delete_bytes_range :: proc (
	gb: ^Gap_Buffer,
	start: int,
	count: int,
) {
	if count <= 0 || start < 0 {
		return
	}

	total_len := current_length(gb)
	if start >= total_len {
		return
	}

	end := start + count
	if end > total_len {
		end = total_len
	}
	actual_count := end - start
	if actual_count <= 0 {
		return
	}

	move_gap(gb, start)

	bytes_after_gap := gb.capacity - gb.gap_end
	to_delete := actual_count
	if to_delete > bytes_after_gap {
		to_delete = bytes_after_gap
	}

	gb.gap_end += to_delete

	new_lines := make([dynamic]int, gb.allocator)
	for line_start in gb.line_starts {
		if line_start >= start && line_start < end {
			continue
		}
		append(&new_lines, line_start)
	}
	delete(gb.line_starts)
	gb.line_starts = new_lines
}

delete_bytes_left :: proc(gb: ^Gap_Buffer, count: int) {
	if count <= 0 || gb.gap_start == 0 {
		return
	}

	bytes_to_delete := count
	if gb.gap_start < bytes_to_delete {
		bytes_to_delete = gb.gap_start // Don't delete beyond start of buffer
	}

	gb.gap_start -= bytes_to_delete
}

delete_bytes_right :: proc(gb: ^Gap_Buffer, count: int) {
	if count <= 0 || gb.gap_end == gb.capacity {
		return
	}

	bytes_remaining_after_gap := gb.capacity - gb.gap_end
	byes_to_delete := count
	if bytes_remaining_after_gap < byes_to_delete {
		byes_to_delete = bytes_remaining_after_gap // Don't delete beyond the end of buffer
	}

	gb.gap_end += byes_to_delete
}

get_text :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator = context.allocator) -> string {
	text_len := current_length(gb)
	if text_len == 0 {
		return ""
	}

	result := make([]u8, text_len, allocator)

	// Copy data before the gap
	copy(result[0:gb.gap_start], gb.buffer[0:gb.gap_start])

	// Copy data after the gap
	copy(result[gb.gap_start:], gb.buffer[gb.gap_end:])

	return string(result)
}

get_line :: proc(
	gb: ^Gap_Buffer,
	line_num: int,
	allocator: mem.Allocator = context.allocator,
) -> string {
	if line_num < 0 || line_num >= len(gb.line_starts) {
		return ""
	}

	start_pos := gb.line_starts[line_num]

	// Find end position (either next line start or end of buffer)
	end_pos: int
	if line_num + 1 < len(gb.line_starts) {
		end_pos = gb.line_starts[line_num + 1] - 1 // -1 to exclude the newline
	} else {
		end_pos = current_length(gb)
	}

	if end_pos <= start_pos {
		return ""
	}

	return get_text_segment(gb, start_pos, end_pos - start_pos, allocator)
}

get_line_count :: proc(gb: ^Gap_Buffer) -> int {
	return len(gb.line_starts)
}

get_lines :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator = context.allocator) -> []string {
	text := get_text(gb, allocator)
	defer delete(text, allocator)

	if len(text) == 0 {
		return {}
	}

	lines := make([dynamic]string, allocator)

	line_start := 0
	for i in 0 ..< len(text) {
		char := rune(text[i])
		if char == '\n' {
			line := text[line_start:i]
			append(&lines, strings.clone(line, allocator))
			line_start = i + 1
		}
	}

	// Add the last line if it doesn't end with newline
	if line_start < len(text) {
		line := text[line_start:]
		append(&lines, strings.clone(line, allocator))
	}

	return lines[:]
}

get_text_segment :: proc(
	gb: ^Gap_Buffer,
	logical_start_param: int,
	logical_length_param: int,
	allocator: mem.Allocator = context.allocator,
) -> string {
	start := logical_start_param // Mutable local copy
	length := logical_length_param // Mutable local copy

	total_len := current_length(gb)
	if start < 0 {start = 0}
	if start >= total_len {return ""}

	logical_end := start + length
	if logical_end > total_len {logical_end = total_len}
	if logical_end <= start {return ""}

	segment_len := logical_end - start
	result := make([]u8, segment_len, allocator)
	dest_idx := 0

	// Check if the segment is entirely before the gap
	if logical_end <= gb.gap_start {
		copy(result, gb.buffer[start:logical_end])
	}
	// Check if the segment is entirely after the gap
	if start >= gb.gap_start { 	// This condition is adjusted: If logical_start is AT OR AFTER gap_start (logical text pos)
		actual_buffer_start := gb.gap_end + (start - gb.gap_start)
		actual_buffer_end := gb.gap_end + (logical_end - gb.gap_start)
		copy(result, gb.buffer[actual_buffer_start:actual_buffer_end])
	}
	// Segment spans across the gap

	// Copy part before gap
	copy(result[0:gb.gap_start - start], gb.buffer[start:gb.gap_start])
	dest_idx += (gb.gap_start - start)

	// Copy part after gap
	bytes_from_after_gap := logical_end - gb.gap_start
	copy(result[dest_idx:], gb.buffer[gb.gap_end:gb.gap_end + bytes_from_after_gap])

	return string(result)
}

get_line_number :: proc(gb: ^Gap_Buffer, logical_pos: int) -> int {
	for i := len(gb.line_starts) - 1; i >= 0; i -= 1 {
		if logical_pos >= gb.line_starts[i] {
			return i
		}
	}
	return 0
}

line_col_to_logical_pos :: proc(gb: ^Gap_Buffer, target_line: int, target_col: int) -> int {
	text := get_text(gb)
	defer delete(text)

	current_line := 0
	current_col := 0

	for char, i in text {
		if current_line == target_line && current_col == target_col {
			return i
		}

		if char == '\n' {
			if current_line == target_line {
				return i // End of requested line
			}
			current_line += 1
			current_col = 0
		} else {
			current_col += 1
		}
	}

	return len(text) // End of buffer
}

logical_pos_to_line_col :: proc(gb: ^Gap_Buffer, pos: int) -> (line: int, col: int) {
	text := get_text(gb)
	defer delete(text)

	current_line := 0
	current_col := 0

	for char, i in text {
		if i == pos {
			return current_line, current_col
		}

		if char == '\n' {
			current_line += 1
			current_col = 0
		} else {
			current_col += 1
		}
	}

	return current_line, current_col
}

debug_print_buffer :: proc(gb: ^Gap_Buffer) {
	fmt.printf("Gap_Buffer State:\n")
	fmt.printf("  Capacity: %v\n", gb.capacity)
	fmt.printf("  Gap Start: %v\n", gb.gap_start)
	fmt.printf("  Gap End: %v\n", gb.gap_end)
	fmt.printf("  Gap Size: %v\n", gap_size(gb))
	fmt.printf("  Current Length (text): %v\n", current_length(gb))

	fmt.printf("  Buffer (Hex): [")
	for i := 0; i < len(gb.buffer); i += 1 {
		fmt.printf("%02x ", gb.buffer[i])
	}
	fmt.printf("]\n")

	// Printable representation
	fmt.printf("  Buffer (ASCII/Text): \"")
	for i := 0; i < len(gb.buffer); i += 1 {
		if i >= gb.gap_start && i < gb.gap_end {
			fmt.printf("_") // Represent gap with underscores
		} else if gb.buffer[i] >= 32 && gb.buffer[i] <= 126 { 	// Printable ASCII
			fmt.printf("%c", gb.buffer[i])
		} else {
			fmt.printf(".") // Non-printable characters
		}
	}
	fmt.printf("\"\n")
	fmt.printf("  Full Text: \"%s\"\n", get_text(gb))
}
