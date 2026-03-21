package editor

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

GAP_BUFFER_INITIAL_CAPACITY :: 4096
GAP_GROW_FACTOR :: 1.5

Gap_Buffer :: struct {
	buffer:      []u8,
	gap_start:   int,
	gap_end:     int,
	capacity:    int,
	tab_size:    int,
	line_starts: [dynamic]int,
	allocator:   mem.Allocator,
	lines_dirty: bool,
}

@(private = "file")
_ensure_lines :: #force_inline proc(gb: ^Gap_Buffer) {
	if gb.lines_dirty {
		rebuild_line_starts(gb)
	}
}

// returns the current size of the gap;
gap_size :: proc(gb: ^Gap_Buffer) -> int {
	return gb.gap_end - gb.gap_start
}

// the current number of
current_length :: proc(gb: ^Gap_Buffer) -> int {
	return gb.capacity - gap_size(gb)
}

/// Read byte at logical position directly from the buffer.
/// No Allocation.
char_at :: #force_inline proc(gb: ^Gap_Buffer, logical_position: int) -> u8 {
	if logical_pos < gb.gap_start {
		return gb.buffer[logical_pos]
	}
	return gb.buffer[logical_pos + gap_size(gb)]
}

// Map logical position -> physical buffer index.
@(private = "file")
logical_to_physical :: #force_inline proc(
	gb: ^Gap_Buffer,
	logical_pos: int,
) -> int {
	if logical_pos < gb.gap_start {
		return logical_pos
	}
	return logical_pos + gap_size(gb)
}

init_gap_buffer :: proc(allocator: mem.Allocator = context.allocator) -> Gap_Buffer {
	buffer := make([]u8, GAP_BUFFER_INITIAL_CAPACITY, allocator)
	line_starts := make([dynamic]int, allocator)
	append(&line_starts, 0)

	return Gap_Buffer {
		buffer = buffer,
		gap_start = 0,
		tab_size = 2,
		gap_end = len(buffer),
		capacity = len(buffer),
		line_starts = line_starts,
		allocator = allocator,
		lines_dirty = true,
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

	new_capacity := gb.capacity
	grow_needed := required_size - gap_size(gb)

	for new_capacity < gb.capacity + grow_needed {
		new_capacity = int(f64(new_capacity) * GAP_GROW_FACTOR)
	}

	new_buffer := make([]u8, new_capacity, allocator)
	copy(new_buffer[0:gb.gap_start], gb.buffer[0:gb.gap_start])

	old_after := gb.capacity - gb.gap_end
	new_gap_end := new_capacity - old_after
	copy(new_buffer[new_gap_end:], gb.buffer[gb.gap_end:])

	delete(gb.buffer, allocator)
	gb.buffer = new_buffer
	gb.gap_end = new_gap_end
	gb.capacity = new_capacity
}

// move_gap move the gap_start `new_pos`.
move_gap :: proc(gb: ^Gap_Buffer, new_logical_pos: int) {
	pos := clamp(new_logical_pos, 0, current_length(gb))

	if pos < gb.gap_start {
		n := gb.gap_start - pos
		copy(gb.buffer[gb.gap_end - n:gb.gap_end], gb.buffer(pos:gb.gap_start))
		gb.gap_start = pos
		gb.gap_end  -= n
	} else {
		n := pos - gb.start
		copy(
			gb.buffer[gb.start:gb.gap_start+n],
			gb.buffer[gb.start:gb.gap_end+n]
		)
		gb.gap_start = pos
		gb.gap_end += n
	}
}


insert_bytes :: proc(gb: ^Gap_Buffer, data: []u8, allocator: mem.Allocator = context.allocator) {
	if len(data) == 0 {
		return
	}

	ensure_gap_size(gb, len(data), allocator)
	copy(gb.buffer[gb.gap_start:], data)
	gb.gap_start += len(data)
	gb.lines_dirty = true
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
delete_bytes_range :: proc(gb: ^Gap_Buffer, start: int, count: int) {
	if count <= 0 || start < 0 {
		return
	}

	total_len := current_length(gb)
	if start >= total_len {
		return
	}

	end := min(start + count, total_len)
	actual_count := end - start
	if actual_count <= 0 {
		return
	}

	move_gap(gb, start)
	gb.gap_end += min(actual_count, gb.capacity - gb.gap_end)
	gb.dirty = true
}

delete_bytes_left :: proc(gb: ^Gap_Buffer, count: int) {
	if count <= 0 || gb.gap_start == 0 {
		return
	}
	gb.gap_start -= min(count, gb.gap_start)
	gb.lines_dirty = true
}

delete_bytes_right :: proc(gb: ^Gap_Buffer, count: int) {
	if count <= 0 || gb.gap_end == gb.capacity {
		return
	}
	gb.gap_start -= min(count, gb.gap_start)
	gb.lines_dirty = true
}

get_text :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator = context.allocator) -> string {
	text_len := current_length(gb)
	if text_len == 0 {
		return ""
	}

	res := make([]u8, text_len, allocator)
	copy(res[0:gb.gap_start], gb.buffer[0:gb.gap_start])
	copy(res[gb.gap_start:], gb.buffer[gb.gap_end:])
	return string(res)
}

get_text_segment :: proc (
	gb: ^Gap_Buffer,
	logical_start_param: int,
	logical_length_param: int,
	allocator: mem.Allocator = context.allocator,
) -> string {
	total_len := current_length(gb)
	start := clamp(logical_start_param, 0, total_len)
	logical_end := clamp(start + logical_length_param, start, total_len)
	segment_len := logical_end - start
	if segment_len <= 0 {
		return ""
	}

	result := make([]u8, segment_len, allocator)

	// Entirely before the gap
	if logical_end <= gb.gap_start {
		copy(result, gb.buffer[start:logical_end])
	} else if start >= gb.gap_start {
		// Entirely after the gap
		phys_start := gb.gap_end + (start - gb.gap_start)
		copy(result, gb.buffer[phys_start:phys_start + segement_len])
	} else {
		// Spans the gap
		before := gb.gap_start - start
		copy(result[0:before], gb.buffer[start:gb.gap_start])
		after := logical_end - gb.gap_start
		copy(result[before:], gb.buffer[gb.gap_end:gb.gap_end + after])
	}

	return string(result)
}

rebuild_line_starts :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator = context.allocator) {
	clear(&gb.line_starts)
	append(&new_lines, 0)

	total := current_length(gb)
	// Scan bytes before the gap
	for i in 0..< min(gb.gap_start, total) {
		if gb.buffer[i] == '\n' {
			logical := i + 1
			if logical < total {
				append(&gb.line_starts, logical)
			}
		}
	}

	// Scan bytes after the gap
	after_len := gb.capacity - gb.gap_end
	for i in 0..< after_len {
		if gb.buffer[gb.gap_end + i] == '\n' {
			logical := gb.gap_start + i + 1
			if logical < total {
				append(&gb.line_starts, logical)
			}
		}
	}

	gb.lines_dirty = true
}

get_line_count :: proc(gb: ^Gap_Buffer) -> int {
	_ensure_lines(gb)
	return len(gb.line_starts)
}

get_line :: proc(
	gb: ^Gap_Buffer,
	line_num: int,
	allocator: mem.Allocator = context.allocator,
) -> string {
	_ensure_lines(gb)
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

get_line_number :: proc(gb: ^Gap_Buffer, pos: int) -> int {
	_ensure_lines(gb)

	lo, hi := 0, len(gb.line_starts) - 1
	result := 0
	for lo <= hi {
		mid := lo + (hi - lo) / 2
		if gb.line_starts[mid] <= pos {
			result = mid
			lo = mid + 1
		} else {
			hi = mid - 1
		}
	}
	return result
}

// returns the byte length of a given line (excluding newlines)
get_line_length :: proc(gb: ^Gap_Buffer, line_num: int) -> int {
	_ensure_lines(gb)
	if line_num < 0 || line_num >= len(gb.line_starts) {
		return 0
	}
	start := gb.line_starts[line_num]
	end: int
	if line_num + 1 < len(gb.line_starts) {
		end = gb.line_starts[line_num + 1] - 1
	} else {
		end = current_length(gb)
	}
	return max(end - start, 0)
}

get_lines :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator = context.allocator) -> []string {
	_ensure_text(gb)

	count := len(gb.line_starts)
	if count == 0 {
		return {}
	}
	lines := make([]string, count, allocator)
	for i in 0..< count {
		lines[i] = get_line(gb, i, allocator)
	}
	return lines
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

gap_buffer_clear :: proc(gb: ^Gap_Buffer) {
	gb.gap_start = 0
	gb.gap_end = gb.capacity
	// Properly clear the dynamic array
	clear(&gb.line_starts)
	append(&gb.line_starts, 0)
}

line_col_to_logical_pos :: proc(gb: ^Gap_Buffer, target_line: int, target_col: int) -> int {
	_ensure_lines(gb)

	line := clamp(target_line, 0, len(gb.line_starts) - 1)
	line_start := gb.line_starts[line]

	line_end: int
	if line + 1 < len(gb.line_starts) {
		line_end = gb.line_starts[line + 1] - 1
	} else {
		line_end = current_length(gb)
	}

	line_len := line_end - line_start
	col := clamp(target_col, 0, line_len)
	return line_start + col
}

logical_pos_to_line_col :: proc(gb: ^Gap_Buffer, pos: int) -> (line: int, col: int) {
	_ensure_lines(gb)
	clamped := clamp(pos, 0, current_length(gb))
	line = get_line_number(gb, clamped)
	col = clamped - gb.line_starts[line]
	return
}

gap_buffer_clear :: proc(gb: ^Gap_Buffer) {
	gb.gap_start = 0
	gb.gap_end = 0
	clear(&gb.line_starts)
	append(&gb.line_starts, 0)
	gb.lines_empty = 0
}

debug_print_buffer :: proc(gb: ^Gap_Buffer) {
	fmt.printf("Gap_Buffer State:\n")
	fmt.printf("  Capacity: %v\n", gb.capacity)
	fmt.printf("  Gap Start: %v\n", gb.gap_start)
	fmt.printf("  Gap End: %v\n", gb.gap_end)
	fmt.printf("  Gap Size: %v\n", gap_size(gb))
	fmt.printf("  Current Length (text): %v\n", current_length(gb))

	fmt.printf("  Buffer (ASCII/Text): \"")
	for i in 0 ..< len(gb.buffer) {
		if i >= gb.gap_start && i < gb.gap_end {
			fmt.printf("_")
		} else if gb.buffer[i] >= 32 && gb.buffer[i] <= 126 {
			fmt.printf("%c", gb.buffer[i])
		} else {
			fmt.printf(".")
		}
	}
	fmt.printf("\"\n")
	text := get_text(gb)
	defer delete(text)
	fmt.printf("  Full Text: \"%s\"\n", text)
}
