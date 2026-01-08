package editor

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import sdl "vendor:sdl3"

File_Entry :: struct {
	name:     string,
	path:     string,
	is_dir:   bool,
	is_open:  bool,
	depth:    int,
	children: int, // Number of direct children (for display)
}

File_Explorer :: struct {
	allocator:       mem.Allocator,
	entries:         [dynamic]File_Entry,
	selected_index:  int,
	scroll_offset:   f32,
	scroll_target:   f32,
	scroll_velocity: f32, // For inertial scrolling
	visible_height:  int,
	item_height:     i32,
	width:           f32,
	x:               f32,
	y:               f32,
	text_renderer:   Text_Renderer,
	is_visible:      bool,
	root_path:       string,
	hover_index:     int, // Track which item is being hovered
	max_depth:       int, // Maximum recursion depth
}

init_file_explorer :: proc(
	root_path: string,
	x: f32 = 0,
	y: f32 = 0,
	font_path: string = "assets/fonts/MapleMono-Regular.ttf",
	font_size: f32 = 16,
	width: f32 = 250,
	allocator: mem.Allocator = context.allocator,
) -> File_Explorer {
	tr, ok := init_text_renderer(font_path, font_size, nil, allocator)
	if !ok {
		fmt.println("File_Explorer: Failed to initialize font renderer")
	}

	fe := File_Explorer {
		allocator       = allocator,
		root_path       = strings.clone(root_path, allocator),
		entries         = make([dynamic]File_Entry, allocator),
		selected_index  = -1,
		scroll_offset   = 0,
		scroll_target   = 0,
		scroll_velocity = 0,
		visible_height  = 30,
		width           = width,
		x               = x,
		y               = y,
		text_renderer   = tr,
		is_visible      = false,
		item_height     = tr.line_height,
		hover_index     = -1,
		max_depth       = 10,
	}

	refresh_file_explorer(&fe)
	return fe
}

destroy_file_explorer :: proc(fe: ^File_Explorer) {
	for entry in fe.entries {
		delete(entry.name, fe.allocator)
		delete(entry.path, fe.allocator)
	}
	delete(fe.entries)
	delete(fe.root_path, fe.allocator)
	destroy_text_renderer(&fe.text_renderer)
}

refresh_file_explorer :: proc(fe: ^File_Explorer) {
	// Clean up existing entries
	for entry in fe.entries {
		delete(entry.name, fe.allocator)
		delete(entry.path, fe.allocator)
	}
	clear(&fe.entries)

	// Add root directory
	root_name := filepath.base(fe.root_path)
	root_entry := File_Entry {
		name     = strings.clone(root_name, fe.allocator),
		path     = strings.clone(fe.root_path, fe.allocator),
		is_dir   = true,
		is_open  = true,
		depth    = 0,
		children = 0,
	}
	append(&fe.entries, root_entry)

	// Load root contents
	load_directory_recursive(fe, fe.root_path, 0, true)

	// Update children count for root
	if len(fe.entries) > 0 {
		fe.entries[0].children = count_direct_children(fe, 0)
	}
}

count_direct_children :: proc(fe: ^File_Explorer, parent_idx: int) -> int {
	if parent_idx < 0 || parent_idx >= len(fe.entries) {
		return 0
	}

	parent_depth := fe.entries[parent_idx].depth
	count := 0

	for i := parent_idx + 1; i < len(fe.entries); i += 1 {
		if fe.entries[i].depth <= parent_depth {
			break
		}
		if fe.entries[i].depth == parent_depth + 1 {
			count += 1
		}
	}

	return count
}

load_directory_recursive :: proc(fe: ^File_Explorer, dir_path: string, depth: int, is_open: bool) {
	if !is_open || depth >= fe.max_depth {
		return
	}

	handle, err := os.open(dir_path, os.O_RDONLY)
	if err != os.ERROR_NONE {
		fmt.printf("Failed to open directory: %s\n", dir_path)
		return
	}
	defer os.close(handle)

	file_infos, read_err := os.read_dir(handle, -1, fe.allocator)
	if read_err != os.ERROR_NONE {
		fmt.printf("Failed to read directory: %s\n", dir_path)
		return
	}
	defer delete(file_infos, fe.allocator)

	// Sort: directories first, then alphabetically
	slice.sort_by(file_infos, proc(a, b: os.File_Info) -> bool {
		if a.is_dir != b.is_dir {
			return a.is_dir
		}
		return strings.compare(a.name, b.name) < 0
	})

	for file_info in file_infos {
		// Skip hidden files
		if len(file_info.name) > 0 && file_info.name[0] == '.' {
			continue
		}

		full_path := filepath.join({dir_path, file_info.name}, fe.allocator)
		defer delete(full_path, fe.allocator)

		entry := File_Entry {
			name     = strings.clone(file_info.name, fe.allocator),
			path     = strings.clone(full_path, fe.allocator),
			is_dir   = file_info.is_dir,
			is_open  = false,
			depth    = depth + 1,
			children = 0,
		}
		append(&fe.entries, entry)
	}
}

toggle_directory :: proc(fe: ^File_Explorer, idx: int) {
	if idx < 0 || idx >= len(fe.entries) {
		return
	}

	entry := &fe.entries[idx]
	if !entry.is_dir {
		return
	}

	if entry.is_open {
		remove_directory_contents(fe, idx)
		entry.is_open = false
	} else {
		load_directory_at_index(fe, idx)
		entry.is_open = true
	}

	// Update children count
	entry.children = count_direct_children(fe, idx)
}

load_directory_at_index :: proc(fe: ^File_Explorer, dir_idx: int) {
	if dir_idx < 0 || dir_idx >= len(fe.entries) {
		return
	}

	dir_entry := &fe.entries[dir_idx]
	if !dir_entry.is_dir {
		return
	}

	handle, err := os.open(dir_entry.path, os.O_RDONLY)
	if err != os.ERROR_NONE {
		fmt.printf("Failed to open directory: %s\n", dir_entry.path)
		return
	}
	defer os.close(handle)

	file_infos, read_err := os.read_dir(handle, -1, fe.allocator)
	if read_err != os.ERROR_NONE {
		return
	}
	defer delete(file_infos, fe.allocator)

	// Sort: directories first, then alphabetically
	slice.sort_by(file_infos, proc(a, b: os.File_Info) -> bool {
		if a.is_dir != b.is_dir {
			return a.is_dir
		}
		return strings.compare(a.name, b.name) < 0
	})

	// Insert entries after parent directory
	insert_idx := dir_idx + 1
	for file_info in file_infos {
		if len(file_info.name) > 0 && file_info.name[0] == '.' {
			continue
		}

		full_path := filepath.join({dir_entry.path, file_info.name}, fe.allocator)
		defer delete(full_path, fe.allocator)

		entry := File_Entry {
			name     = strings.clone(file_info.name, fe.allocator),
			path     = strings.clone(full_path, fe.allocator),
			is_dir   = file_info.is_dir,
			is_open  = false,
			depth    = dir_entry.depth + 1,
			children = 0,
		}

		inject_at(&fe.entries, insert_idx, entry)
		insert_idx += 1
	}
}

remove_directory_contents :: proc(fe: ^File_Explorer, dir_idx: int) {
	if dir_idx < 0 || dir_idx >= len(fe.entries) {
		return
	}

	dir_depth := fe.entries[dir_idx].depth

	// Remove all children (entries with greater depth)
	for i := dir_idx + 1; i < len(fe.entries); {
		if fe.entries[i].depth <= dir_depth {
			break
		}

		delete(fe.entries[i].name, fe.allocator)
		delete(fe.entries[i].path, fe.allocator)
		ordered_remove(&fe.entries, i)
	}
}

update_file_explorer :: proc(fe: ^File_Explorer, dt: f32) {
	// Smooth scrolling with easing
	scroll_speed: f32 = 15.0
	scroll_diff := fe.scroll_target - fe.scroll_offset

	if abs(scroll_diff) > 0.1 {
		fe.scroll_offset += scroll_diff * scroll_speed * dt
	} else {
		fe.scroll_offset = fe.scroll_target
	}

	// Apply velocity-based scrolling (for trackpad inertia)
	if abs(fe.scroll_velocity) > 0.01 {
		fe.scroll_target += fe.scroll_velocity * dt
		fe.scroll_velocity *= 0.92 // Friction/damping
	} else {
		fe.scroll_velocity = 0
	}

	// Clamp scroll to valid range
	max_scroll := f32(max(0, len(fe.entries) - fe.visible_height))
	fe.scroll_offset = f32(clamp(int(fe.scroll_offset), 0, int(max_scroll)))
	fe.scroll_target = f32(clamp(int(fe.scroll_target), 0, int(max_scroll)))
}

render_file_explorer :: proc(fe: ^File_Explorer, renderer: ^sdl.Renderer, editor: ^Editor) {
	if !fe.is_visible {
		return
	}
	if len(fe.entries) == 0 {
		return
	}

	// Background
	bg_rect := sdl.FRect {
		x = fe.x,
		y = fe.y,
		w = fe.width,
		h = f32(fe.visible_height) * f32(fe.item_height),
	}
	_ = sdl.SetRenderDrawColor(
		renderer,
		editor.theme.explorer_bg.r,
		editor.theme.explorer_bg.g,
		editor.theme.explorer_bg.b,
		editor.theme.explorer_bg.a,
	)
	_ = sdl.RenderFillRect(renderer, &bg_rect)

	// Set clip rect
	clip_rect := sdl.Rect {
		x = i32(bg_rect.x),
		y = i32(bg_rect.y),
		w = i32(bg_rect.w),
		h = i32(bg_rect.h),
	}
	sdl.SetRenderClipRect(renderer, &clip_rect)

	// Calculate visible range with smooth scrolling offset
	fractional_offset := fe.scroll_offset - f32(int(fe.scroll_offset))
	start_idx := int(fe.scroll_offset)
	end_idx := min(len(fe.entries), start_idx + fe.visible_height + 2)

	// Render selection highlight
	if fe.selected_index >= start_idx && fe.selected_index < end_idx {
		y := fe.y + (f32(fe.selected_index) - fe.scroll_offset) * f32(fe.item_height)
		highlight := sdl.FRect {
			x = fe.x,
			y = y,
			w = fe.width,
			h = f32(fe.item_height),
		}
		_ = sdl.SetRenderDrawColor(
			renderer,
			editor.theme.explorer_select.r,
			editor.theme.explorer_select.g,
			editor.theme.explorer_select.b,
			editor.theme.explorer_select.a,
		)
		_ = sdl.RenderFillRect(renderer, &highlight)
	}

	// Render hover highlight
	if fe.hover_index >= start_idx &&
	   fe.hover_index < end_idx &&
	   fe.hover_index != fe.selected_index {
		y := fe.y + (f32(fe.hover_index) - fe.scroll_offset) * f32(fe.item_height)
		hover_rect := sdl.FRect {
			x = fe.x,
			y = y,
			w = fe.width,
			h = f32(fe.item_height),
		}
		hover_color := editor.theme.explorer_select
		hover_color.a = 50 // Semi-transparent
		_ = sdl.SetRenderDrawColor(
			renderer,
			hover_color.r,
			hover_color.g,
			hover_color.b,
			hover_color.a,
		)
		_ = sdl.RenderFillRect(renderer, &hover_rect)
	}

	// Render entries
	original_color := fe.text_renderer.color
	defer fe.text_renderer.color = original_color

	for i := start_idx; i < end_idx; i += 1 {
		entry := &fe.entries[i]
		y := fe.y + (f32(i) - fe.scroll_offset) * f32(fe.item_height)

		indent := f32(entry.depth * 16)
		x := fe.x + indent + 8

		// Choose icon based on type and state
		icon: string
		if entry.is_dir {
			icon = entry.is_open ? "▼" : "▶"
		} else {
			// File extension icons
			ext := filepath.ext(entry.name)
			switch ext {
			case ".odin":
				icon = "<>"
			case ".txt":
				icon = "..."
			case ".md":
				icon = "."
			case ".json":
				icon = "{ }"
			case ".png", ".jpg", ".jpeg":
				icon = "[]"
			case:
				icon = "?"
			}
		}

		// Render icon
		icon_color := entry.is_dir ? editor.theme.explorer_dir : editor.theme.explorer_text
		render_text(&fe.text_renderer, renderer, icon, x, y, fe.allocator, icon_color)

		// Render filename
		filename_x := x + 20
		text_color := entry.is_dir ? editor.theme.explorer_dir : editor.theme.explorer_text

		render_text(
			&fe.text_renderer,
			renderer,
			entry.name,
			filename_x,
			y,
			fe.allocator,
			text_color,
		)
	}

	// Border
	_ = sdl.SetRenderDrawColor(
		renderer,
		editor.theme.explorer_bg.r / 2,
		editor.theme.explorer_bg.g / 2,
		editor.theme.explorer_bg.b / 2,
		255,
	)
	_ = sdl.RenderRect(renderer, &bg_rect)

	_ = sdl.SetRenderClipRect(renderer, nil)
}

handle_file_explorer_event :: proc(fe: ^File_Explorer, event: ^sdl.Event) -> bool {
	if !fe.is_visible {
		return false
	}

	#partial switch event.type {
	case .KEY_DOWN:
		switch event.key.key {
		case sdl.K_RETURN:
			if fe.selected_index >= 0 && fe.selected_index < len(fe.entries) {
				entry := &fe.entries[fe.selected_index]
				if entry.is_dir {
					toggle_directory(fe, fe.selected_index)
				} else {
					return true // Signal file selection
				}
			}
		case sdl.K_UP:
			fe.selected_index = max(0, fe.selected_index - 1)
			ensure_visible(fe)
		case sdl.K_DOWN:
			fe.selected_index = min(len(fe.entries) - 1, fe.selected_index + 1)
			ensure_visible(fe)
		}

	case .MOUSE_BUTTON_DOWN:
		if event.button.button == 1 {
			mouse_x := f32(event.button.x)
			mouse_y := f32(event.button.y)

			in_bounds := point_in_rect(
				mouse_x,
				mouse_y,
				fe.x,
				fe.y,
				fe.width,
				f32(fe.visible_height * int(fe.item_height)),
			)

			if in_bounds {
				relative_y := mouse_y - fe.y
				clicked_idx := int(fe.scroll_offset + (relative_y / f32(fe.item_height)))

				if clicked_idx >= 0 && clicked_idx < len(fe.entries) {
					fe.selected_index = clicked_idx
					entry := &fe.entries[clicked_idx]

					if entry.is_dir {
						toggle_directory(fe, clicked_idx)
					} else {
						return true // Signal file selection
					}
				}
				return true
			}
		}

	case .MOUSE_MOTION:
		mouse_x := f32(event.motion.x)
		mouse_y := f32(event.motion.y)

		in_bounds := point_in_rect(
			mouse_x,
			mouse_y,
			fe.x,
			fe.y,
			fe.width,
			f32(fe.visible_height * int(fe.item_height)),
		)

		if in_bounds {
			relative_y := mouse_y - fe.y
			hover_idx := int(fe.scroll_offset + (relative_y / f32(fe.item_height)))

			if hover_idx >= 0 && hover_idx < len(fe.entries) {
				fe.hover_index = hover_idx
			} else {
				fe.hover_index = -1
			}
		} else {
			fe.hover_index = -1
		}

	case .MOUSE_WHEEL:
		mouse_x := f32(event.wheel.mouse_x)
		mouse_y := f32(event.wheel.mouse_y)

		in_bounds := point_in_rect(
			mouse_x,
			mouse_y,
			fe.x,
			fe.y,
			fe.width,
			f32(fe.visible_height * int(fe.item_height)),
		)

		if in_bounds {
			scroll_amount: f32 = 3.0
			fe.scroll_target = f32(clamp(
				int(fe.scroll_target - f32(event.wheel.y) * scroll_amount),
				0,
				int(f32(max(0, len(fe.entries) - fe.visible_height))),
			))
		}
	}

	return false
}

ensure_visible :: proc(fe: ^File_Explorer) {
	if fe.selected_index < int(fe.scroll_offset) {
		fe.scroll_target = f32(fe.selected_index)
	} else if fe.selected_index >= int(fe.scroll_offset) + fe.visible_height {
		fe.scroll_target = f32(fe.selected_index - fe.visible_height + 1)
	}
}

point_in_rect :: proc(x, y, rect_x, rect_y, rect_w, rect_h: f32) -> bool {
	return x >= rect_x && x <= rect_x + rect_w && y >= rect_y && y <= rect_y + rect_h
}

toggle_file_explorer :: proc(fe: ^File_Explorer) {
	fe.is_visible = !fe.is_visible
}

get_selected_file :: proc(fe: ^File_Explorer) -> string {
	if fe.selected_index >= 0 && fe.selected_index < len(fe.entries) {
		entry := &fe.entries[fe.selected_index]
		if !entry.is_dir {
			return entry.path
		}
	}
	return ""
}
