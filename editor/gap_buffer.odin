package editor

import "core:fmt"
import "core:mem"

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
char_at :: #force_inline proc(gb: ^Gap_Buffer, logical_pos: int) -> u8 {
	if logical_pos < gb.gap_start {
		return gb.buffer[logical_pos]
	}
	return gb.buffer[logical_pos + gap_size(gb)]
}

// Map logical position -> physical buffer index.
@(private = "file")
logical_to_physical :: #force_inline proc(gb: ^Gap_Buffer, logical_pos: int) -> int {
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
		// Move the n bytes just before the gap to just after the gap,
		// shifting the gap leftward to `pos`.
		n := gb.gap_start - pos
		copy(gb.buffer[gb.gap_end - n:gb.gap_end], gb.buffer[pos:gb.gap_start])
		gb.gap_start = pos
		gb.gap_end -= n
	} else if pos > gb.gap_start {
		// Move the n bytes just after the gap to just before the gap,
		// shifting the gap rightward to `pos`.
		n := pos - gb.gap_start
		copy(gb.buffer[gb.gap_start:gb.gap_start + n], gb.buffer[gb.gap_end:gb.gap_end + n])
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
	gb.lines_dirty = true
}

delete_bytes_left :: proc(gb: ^Gap_Buffer, count: int) {
	if count <= 0 || gb.gap_start == 0 {
		return
	}
	gb.gap_end += min(count, gb.gap_start)
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

rebuild_line_starts :: proc(gb: ^Gap_Buffer, allocator: mem.Allocator = context.allocator) {
	clear(&gb.line_starts)
	append(&gb.line_starts, 0)

	total := current_length(gb)
	// Scan bytes before the gap
	for i in 0 ..< gb.gap_start {
		if gb.buffer[i] == '\n' {
			logical := i + 1
			append(&gb.line_starts, logical)
		}
	}

	// Scan bytes after the gap
	after_len := gb.capacity - gb.gap_end
	for i in 0 ..< after_len {
		if gb.buffer[gb.gap_end + i] == '\n' {
			logical := gb.gap_start + i + 1
			append(&gb.line_starts, logical)
		}
	}

	gb.lines_dirty = false
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

	if gb.line_starts == nil || len(gb.line_starts) == 0 {
		return ""
	}

	if line_num < 0 || line_num >= len(gb.line_starts) {
		return ""
	}

	start_pos := gb.line_starts[line_num]
	total_len := current_length(gb)

	if start_pos >= total_len && total_len > 0 {
		return ""
	}

	end_pos: int
	if line_num + 1 < len(gb.line_starts) {
		end_pos = gb.line_starts[line_num + 1] - 1
	} else {
		end_pos = total_len
	}

	length := end_pos - start_pos
	if length <= 0 do return ""

	return get_text_segment(gb, start_pos, length, allocator)
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
	_ensure_lines(gb)

	count := len(gb.line_starts)
	if count == 0 {
		return {}
	}
	lines := make([]string, count, allocator)
	for i in 0 ..< count {
		lines[i] = get_line(gb, i, allocator)
	}
	return lines
}

get_text_segment :: proc(
	gb: ^Gap_Buffer,
	start: int,
	length: int,
	allocator: mem.Allocator = context.allocator,
) -> string {
	total_len := current_length(gb)

	// Clamp inputs
	start := max(0, start)
	if start >= total_len || length <= 0 {
		return ""
	}

	end := min(start + length, total_len)
	actual_len := end - start

	result := make([]u8, actual_len, allocator)

	if end <= gb.gap_start {
		copy(result, gb.buffer[start:end])
	} else if start >= gb.gap_start {
		phys_start := start + (gb.gap_end - gb.gap_start)
		phys_end := end + (gb.gap_end - gb.gap_start)
		copy(result, gb.buffer[phys_start:phys_end])
	} else {
		before_len := gb.gap_start - start
		after_len := end - gb.gap_start

		copy(result[0:before_len], gb.buffer[start:gb.gap_start])
		copy(result[before_len:], gb.buffer[gb.gap_end:gb.gap_end + after_len])
	}

	return string(result)
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

// Returns the visual column for a given byte column on a line, expanding tabs
// to the next tab-stop grid position.  Every non-tab codepoint counts as 1.
get_visual_col :: proc(
	gb: ^Gap_Buffer,
	line_num: int,
	byte_col: int,
	tab_size: int,
	allocator: mem.Allocator = context.allocator,
) -> int {
	ts := max(tab_size, 1)
	line_str := get_line(gb, line_num, allocator)
	defer delete(line_str, allocator)

	visual := 0
	i := 0
	for i < len(line_str) && i < byte_col {
		b := line_str[i]
		if b == '\t' {
			visual = (visual / ts + 1) * ts
			i += 1
		} else {
			char_size := 1
			if b >= 0xC0 {
				switch {
				case b < 0xE0:
					char_size = 2
				case b < 0xF0:
					char_size = 3
				case:
					char_size = 4
				}
			}
			i += char_size
			visual += 1
		}
	}
	return visual
}

// Returns the byte column whose visual position is <= target_visual and is as
// close to it as possible.  When target_visual falls inside a tab the cursor
// snaps to the start of that tab (i.e. the tab's byte position is returned).
visual_col_to_byte_col :: proc(
	gb: ^Gap_Buffer,
	line_num: int,
	target_visual: int,
	tab_size: int,
	allocator: mem.Allocator = context.allocator,
) -> int {
	ts := max(tab_size, 1)
	line_str := get_line(gb, line_num, allocator)
	defer delete(line_str, allocator)

	visual := 0
	i := 0
	for i < len(line_str) {
		if visual >= target_visual {break}
		b := line_str[i]
		if b == '\t' {
			next_stop := (visual / ts + 1) * ts
			if next_stop > target_visual {
				// target falls inside this tab – snap to its start
				break
			}
			visual = next_stop
			i += 1
		} else {
			char_size := 1
			if b >= 0xC0 {
				switch {
				case b < 0xE0:
					char_size = 2
				case b < 0xF0:
					char_size = 3
				case:
					char_size = 4
				}
			}
			visual += 1
			i += char_size
		}
	}
	return i
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
	gb.lines_dirty = true
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
