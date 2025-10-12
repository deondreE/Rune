package editor

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import "core:thread"
import "core:sync/chan"
import "core:time"
import sdl "vendor:sdl3"

File_Match :: struct {
	path:  string,
	line:  string,
	index: int,
}

Search_Job :: struct {
	query: string,
	timestamp: u64,
}

Search_Result_Batch :: struct {
	matches: []File_Match,
	is_final: bool,
	query_timestamp: u64,
}

// Cache for file contents
File_Cache_Entry :: struct {
	content: string,
	lines: []string,
	last_modified: time.Time,
}

Search_Bar :: struct {
	is_visible:     bool,
	caret_pos:      int,
	gap_buffer:     Gap_Buffer,
	current_query:  string,
	lower_current_query: string,

	matches:        []File_Match,
	selected_index: int,
	allocator:      mem.Allocator,
	
	// Performance optimizations
	file_cache: map[string]File_Cache_Entry,
	last_search_time: u64,
	search_debounce_ms: u64,
	max_results: int,
}

line_contains :: proc(line, query: string) -> bool {
	return strings.contains(strings.to_lower(line), strings.to_lower(query))
}

// Fast file extension check
is_text_file :: proc(filename: string) -> bool {
	ext := filepath.ext(filename)
	text_exts := []string{".txt", ".md", ".odin", ".c", ".cpp", ".h", ".hpp", ".py", ".js", ".ts", ".go", ".rs", ".java", ".cs", ".php", ".rb", ".lua", ".sh", ".bat", ".json", ".xml", ".html", ".css", ".scss", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf"}
	
	for text_ext in text_exts {
		if ext == text_ext {
			return true
		}
	}
	return false
}

// Fast cached file reading
get_file_lines :: proc(file_path: string, sb: ^Search_Bar, allocator: mem.Allocator) -> ([]string, bool) {
	// Check if file is in cache
	if entry, exists := sb.file_cache[file_path]; exists {
		// Check if file was modified
		stat, stat_err := os.stat(file_path)
		if stat_err == os.ERROR_NONE && stat.modification_time == entry.last_modified {
			return entry.lines, true
		}
		// File was modified, remove from cache
		delete(entry.content, allocator)
		delete(entry.lines, allocator)
		delete_key(&sb.file_cache, file_path)
	}
	
	// Read file and cache it
	file_bytes, ok := os.read_entire_file_from_filename(file_path, allocator)
	if !ok {
		return nil, false
	}
	
	content := string(file_bytes)
	lines := strings.split(content, "\n", allocator)
	
	stat, stat_err := os.stat(file_path)
	last_modified := stat_err == os.ERROR_NONE ? stat.modification_time : {}
	
	// Cache the result
	sb.file_cache[strings.clone(file_path, allocator)] = File_Cache_Entry{
		content = strings.clone(content, allocator),
		lines = lines,
		last_modified = last_modified,
	}
	
	delete(file_bytes, allocator)
	return lines, true
}

// Optimized search with early termination
search_files_in_dir_fast :: proc(
	dir_path: string,
	query: string,
	sb: ^Search_Bar,
	allocator: mem.Allocator,
) -> []File_Match {
	matches: [dynamic]File_Match
	if len(query) == 0 {
		return matches[:]
	}
	
	lower_query := strings.to_lower(query, allocator)
	defer delete(lower_query, allocator)

	handle, ok := os.open(dir_path, os.O_RDONLY)
	if ok != os.ERROR_NONE {
		return matches[:]
	}
	defer os.close(handle)

	file_infos, read_err := os.read_dir(handle, -1, allocator)
	if read_err != os.ERROR_NONE {
		return matches[:]
	}
	defer delete(file_infos, allocator)

	// Process files first (they're more likely to have matches)
	files: [dynamic]os.File_Info
	dirs: [dynamic]os.File_Info

	for info in file_infos {
		if len(info.name) > 0 && info.name[0] == '.' {
			continue
		}
		
		if info.is_dir {
			append(&dirs, info)
		} else if is_text_file(info.name) {
			append(&files, info)
		}
	}

	// Search files in current directory first
	for info in files {
		if len(matches) >= sb.max_results {
			break
		}
		
		full_path := filepath.join({dir_path, info.name}, allocator)
		defer delete(full_path, allocator)
		
		lines, ok := get_file_lines(full_path, sb, allocator)
		if !ok {
			continue
		}
		
		for line, i in lines {
			if len(matches) >= sb.max_results {
				break
			}
			
			if strings.contains(strings.to_lower(line), lower_query) {
				fm := File_Match{
					path  = strings.clone(full_path, allocator),
					line  = strings.clone(strings.trim_space(line), allocator),
					index = i + 1, // 1-based line numbers
				}
				append(&matches, fm)
			}
		}
	}
	
	// Then search subdirectories
	for info in dirs {
		if len(matches) >= sb.max_results {
			break
		}
		
		full_path := filepath.join({dir_path, info.name}, allocator)
		defer delete(full_path, allocator)
		
		sub_matches := search_files_in_dir_fast(full_path, query, sb, allocator)
		for m in sub_matches {
			if len(matches) >= sb.max_results {
				break
			}
			append(&matches, m)
		}
		delete(sub_matches, allocator)
	}

	delete(files)
	delete(dirs)
	return matches[:]
}

// Debounced search update
update_search_results :: proc(sb: ^Search_Bar) {
	current_time := u64(time.duration_milliseconds(time.since({})))
	
	if current_time - sb.last_search_time < sb.search_debounce_ms {
		return
	}
	
	query := get_text_segment(
		&sb.gap_buffer,
		0,
		current_length(&sb.gap_buffer),
		sb.allocator,
	)
	defer delete(query, sb.allocator)
	
	// Clear old results
	for match in sb.matches {
		delete(match.path, sb.allocator)
		delete(match.line, sb.allocator)
	}
	delete(sb.matches, sb.allocator)
	
	// Perform new search
	if len(query) > 0 {
		sb.matches = search_files_in_dir_fast(".", query, sb, sb.allocator)
	} else {
		sb.matches = {}
	}
	
	sb.selected_index = 0
	delete(sb.current_query, sb.allocator)
	sb.current_query = strings.clone(query, sb.allocator)
	sb.last_search_time = current_time
}

init_search_bar :: proc(allocator: mem.Allocator) -> Search_Bar {
	sb: Search_Bar
	sb.gap_buffer = init_gap_buffer(allocator)
	sb.is_visible = false
	sb.allocator = allocator
	sb.caret_pos = 0
	sb.file_cache = make(map[string]File_Cache_Entry, allocator)
	sb.search_debounce_ms = 150 // 150ms debounce
	sb.max_results = 100
	return sb
}

handle_backspace_search :: proc(sb: ^Search_Bar) {
	if sb.caret_pos <= 0 {
		return
	}

	prev_pos := get_prev_utf8_char_start_byte_offset(&sb.gap_buffer, sb.caret_pos)
	if prev_pos < 0 {
		prev_pos = 0
	}
	bytes_to_delete := sb.caret_pos - prev_pos
	if bytes_to_delete <= 0 {
		return
	}

	delete_bytes_left(&sb.gap_buffer, bytes_to_delete)
	sb.caret_pos = prev_pos
	move_gap(&sb.gap_buffer, sb.caret_pos)
	
	// Trigger search update
	sb.last_search_time = 0
}

handle_search_bar_event :: proc(sb: ^Search_Bar, editor: ^Editor, event: ^sdl.Event) -> bool {
	if !sb.is_visible {
		return false
	}

	#partial switch event.type {
	case sdl.EventType.KEY_DOWN:
		switch event.key.key {
		case 27: // ESC
			sb.is_visible = false
			
		case 13: // ENTER
			if len(sb.matches) > 0 && sb.selected_index < len(sb.matches) {
				selected := sb.matches[sb.selected_index]
				fmt.printf("Opening: %s at line %d\n", selected.path, selected.index)
				// TODO: open found file in editor.
				if entry, exists := sb.file_cache[selected.path]; exists {
					load_text_into_editor(editor, entry.content)
				} else {
					 text, ok := os.read_entire_file_from_filename(selected.path, sb.allocator)
					 if ok {
					 	load_text_into_editor(editor, string(text))
					 	delete(text, sb.allocator)
					 } else {
					 	fmt.printf("Couldn't load %s\n", selected.path)
					 }
				}

				target_pos :=
            line_col_to_logical_pos(&editor.gap_buffer, selected.index - 1, 0)
        editor.cursor_logical_pos = target_pos
        move_gap(&editor.gap_buffer, target_pos)
        update_cursor_position(editor)
			}
			gap_buffer_clear(&sb.gap_buffer)
			sb.caret_pos = 0
			sb.is_visible = false
			
		case 8: // BACKSPACE
			handle_backspace_search(sb)
			
		case 1073741905: // Down
			if len(sb.matches) > 0 {
				sb.selected_index = min(sb.selected_index + 1, len(sb.matches) - 1)
			}
			return true
			
		case 1073741906: // UP
			if len(sb.matches) > 0 {
				sb.selected_index = max(sb.selected_index - 1, 0)
			}
			return true
		}
		
	case sdl.EventType.TEXT_INPUT:
		text_cstr := event.text.text
		text_len := len(string(text_cstr))
		if text_len > 0 {
			text_bytes := ([^]u8)(text_cstr)[:text_len]
			insert_bytes(&sb.gap_buffer, text_bytes, sb.allocator)
			sb.caret_pos += text_len
			move_gap(&sb.gap_buffer, sb.caret_pos)
			
			// Trigger search update
			sb.last_search_time = 0
		}
	}

	return true
}

render_search_bar :: proc(
	sb: ^Search_Bar,
	text_renderer: ^Text_Renderer,
	renderer: ^sdl.Renderer,
	window_w, window_h: i32,
) {
	if !sb.is_visible {
		return
	}
	
	// Update search results if needed
	update_search_results(sb)

	bar_h := f32(text_renderer.line_height) * 1.5
	bar_y: f32 = 10.0 + 30.0
	bar_x := f32(300)
	bar_w := f32(window_w) - 2 * bar_x

	// Background
	_ = sdl.SetRenderDrawColor(renderer, 0x30, 0x30, 0x30, 0xFF)
	bar_rect := sdl.FRect{bar_x, bar_y, bar_w, bar_h}
	_ = sdl.RenderFillRect(renderer, &bar_rect)

	// Outline
	_ = sdl.SetRenderDrawColor(renderer, 0x80, 0x80, 0x80, 0xFF)
	_ = sdl.RenderRect(renderer, &bar_rect)

	search_text := get_text_segment(
		&sb.gap_buffer,
		0,
		current_length(&sb.gap_buffer),
		sb.allocator,
	)
	defer delete(search_text, sb.allocator)

	// Draw the text with prompt
	prompt := "Search: "
	full_text := fmt.tprintf("%s%s", prompt, search_text)
	render_text(
		text_renderer,
		renderer,
		full_text,
		bar_x + 10.0,
		bar_y + (bar_h - f32(text_renderer.line_height)) / 2.0,
		sb.allocator,
	)

	// Draw caret
	caret_bytes := min(sb.caret_pos, len(search_text))
	caret_slice := string(search_text[:caret_bytes])
	prompt_width := measure_text_width(text_renderer, prompt)
	caret_x := bar_x + 10.0 + prompt_width + measure_text_width(text_renderer, caret_slice)
	caret_y := bar_y + 4.0

	caret_rect := sdl.FRect{caret_x, caret_y, 2.0, f32(text_renderer.line_height)}

	blink_interval_ms :: 500
	current_time_ms := sdl.GetTicks()
	if (current_time_ms / u64(blink_interval_ms)) % 2 == 0 {
		_ = sdl.SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF)
		_ = sdl.RenderFillRect(renderer, &caret_rect)
	}

	// Search matches
	if len(sb.matches) > 0 {
		item_x := bar_x + 10.0
		item_y := bar_y + bar_h + 8.0
		max_visible := min(10, len(sb.matches))

		for i in 0 ..< max_visible {
			m := sb.matches[i]

			item_rect := sdl.FRect{
				item_x - 5.0,
				item_y,
				bar_w - 10.0,
				f32(text_renderer.line_height) + 4.0,
			}
			
			if i == sb.selected_index {
				_ = sdl.SetRenderDrawColor(renderer, 0x40, 0x40, 0x90, 0xFF)
				_ = sdl.RenderFillRect(renderer, &item_rect)
			} else {
				_ = sdl.SetRenderDrawColor(renderer, 0x20, 0x20, 0x20, 0xFF)
				_ = sdl.RenderFillRect(renderer, &item_rect)
			}

			// Truncate long lines for display
			display_line := m.line
			if len(display_line) > 60 {
				display_line = fmt.tprintf("%s...", display_line[:57])
			}
			
			display_str := fmt.tprintf("%s:%d - %s", 
				filepath.base(m.path), m.index, display_line)
			render_text(text_renderer, renderer, display_str, item_x, item_y + 2.0, sb.allocator)

			item_y += f32(text_renderer.line_height) + 6.0
		}
		
		// Show result count
		if len(sb.matches) > max_visible {
			status_text := fmt.tprintf("Showing %d of %d matches", max_visible, len(sb.matches))
			render_text(text_renderer, renderer, status_text, item_x, item_y + 5.0, sb.allocator)
		}
	}
}

destroy_search_bar :: proc(sb: ^Search_Bar, allocator: mem.Allocator) {
	// Clear matches
	for match in sb.matches {
		delete(match.path, allocator)
		delete(match.line, allocator)
	}
	delete(sb.matches, allocator)
	
	// Clear cache
	for key, entry in sb.file_cache {
		delete(key, allocator)
		delete(entry.content, allocator)
		delete(entry.lines, allocator)
	}
	// delete(sb.file_cache, allocator)
	
	delete(sb.current_query, allocator)
	destroy_gap_buffer(&sb.gap_buffer, allocator)
}