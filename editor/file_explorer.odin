package editor

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import sdl "vendor:sdl3"

File_Entry :: struct {
	name:    string,
	path:    string,
	is_dir:  bool,
	is_open: bool,
	depth:   int,
}

File_Explorer :: struct {
	allocator:      mem.Allocator,
	entries:        [dynamic]File_Entry,
	selected_index: int,
	scroll_offset:  int,
	visible_height: int,
	item_height:    i32,
	width:          f32,
	x:              f32,
	y:              f32,
	text_renderer:  Text_Renderer,
	is_visible:     bool,
	root_path:      string,
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
	tr, ok := init_text_renderer(font_path, font_size, allocator)
	if !ok {
		fmt.println("File_Explorer: Broken font renderer")
	}
	fe := File_Explorer {
		allocator      = allocator,
		root_path      = strings.clone(root_path, allocator),
		entries        = make([dynamic]File_Entry, allocator),
		selected_index = 0,
		scroll_offset  = 0,
		visible_height = 30,
		width          = width,
		x              = x,
		y              = y,
		text_renderer  = tr,
		is_visible     = false,
		item_height    = tr.line_height,
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
	for entry in fe.entries {
		delete(entry.name, fe.allocator)
		delete(entry.path, fe.allocator)
	}
	clear(&fe.entries)


	root_name := filepath.base(fe.root_path)

	root_entry := File_Entry {
		name    = strings.clone(root_name, fe.allocator),
		path    = strings.clone(fe.root_path, fe.allocator),
		is_dir  = true,
		is_open = true,
		depth   = 0,
	}
	append(&fe.entries, root_entry)

	load_directory_recursive(fe, fe.root_path, 0, true)
}

load_directory_recursive :: proc(fe: ^File_Explorer, dir_path: string, depth: int, is_open: bool) {
	if !is_open || depth > 5 {
		return
	}

	handle, err := os.open(dir_path, os.O_RDONLY)
	if err != os.ERROR_NONE {
		return
	}
	defer os.close(handle)

	file_infos, read_err := os.read_dir(handle, -1, fe.allocator)
	if read_err != os.ERROR_NONE {
		return
	}
	defer delete(file_infos, fe.allocator)

	slice.sort_by(file_infos, proc(a, b: os.File_Info) -> bool {
		if a.is_dir != b.is_dir {
			return a.is_dir
		}
		return a.name < b.name
	})

	for file_info in file_infos {
		if len(file_info.name) > 0 && file_info.name[0] == '.' {
			continue
		}

		full_path := filepath.join({dir_path, file_info.name}, fe.allocator)
		defer delete(full_path, fe.allocator)

		entry := File_Entry {
			name    = strings.clone(file_info.name, fe.allocator),
			path    = strings.clone(full_path, fe.allocator),
			is_dir  = file_info.is_dir,
			is_open = false,
			depth   = depth + 1,
		}
		append(&fe.entries, entry)

		if file_info.is_dir && depth == 0 {
			// load_directory_recursive(fe, full_path, depth + 1, true)
		}
	}
}

toggle_directory :: proc(fe: ^File_Explorer, idx: int) {
	if idx < 0 || idx >= len(fe.entries) {return}

	entry := &fe.entries[idx]
	if !entry.is_dir {return}

	if entry.is_open {
		remove_directory_contents(fe, idx)
		entry.is_open = false
	} else {
		load_directory_at_index(fe, idx)
		entry.is_open = true
	}
}

load_directory_at_index :: proc(fe: ^File_Explorer, dir_idx: int) {
	if dir_idx < 0 || dir_idx >= len(fe.entries) {return}

	dir_entry := &fe.entries[dir_idx]
	if !dir_entry.is_dir {return}

	handle, err := os.open(dir_entry.path, os.O_RDONLY)
	if err != os.ERROR_NONE {return}
	defer os.close(handle)

	file_infos, read_err := os.read_dir(handle, -1, fe.allocator)
	if read_err != os.ERROR_NONE {return}
	defer delete(file_infos, fe.allocator)

	slice.sort_by(file_infos, proc(a, b: os.File_Info) -> bool {
		if a.is_dir != b.is_dir {
			return a.is_dir
		}
		return a.name < b.name
	})

	// Insert after dir
	insert_idx := dir_idx + 1
	for file_info in file_infos {
		if len(file_info.name) > 0 && file_info.name[0] == '.' {
			continue
		}

		full_path := filepath.join({dir_entry.path, file_info.name}, fe.allocator)
		defer delete(full_path, fe.allocator)

		entry := File_Entry {
			name    = strings.clone(file_info.name, fe.allocator),
			path    = strings.clone(full_path, fe.allocator),
			is_dir  = file_info.is_dir,
			is_open = false,
			depth   = dir_entry.depth + 1,
		}

		inject_at(&fe.entries, insert_idx, entry)
		insert_idx += 1
	}
}

remove_directory_contents :: proc(fe: ^File_Explorer, dir_idx: int) {
	if dir_idx < 0 || dir_idx >= len(fe.entries) {return}

	dir_depth := fe.entries[dir_idx].depth

	i := dir_idx + 1
	for i < len(fe.entries) {
		if fe.entries[i].depth <= dir_depth {
			break
		}

		delete(fe.entries[i].name, fe.allocator)
		delete(fe.entries[i].path, fe.allocator)

		ordered_remove(&fe.entries, i)
		continue
	}
}

render_file_explorer :: proc(fe: ^File_Explorer, renderer: ^sdl.Renderer) {
	if !fe.is_visible {return}
	if len(fe.entries) == 0 {return}

	bg_rect := sdl.FRect {
		x = fe.x,
		y = fe.y,
		w = fe.width,
		h = f32(fe.visible_height) * f32(fe.item_height),
	}
	_ = sdl.SetRenderDrawColor(renderer, 0x25, 0x25, 0x25, 0xFF)
	_ = sdl.RenderFillRect(renderer, &bg_rect)
	
	clip_rect := sdl.Rect {
	    x = i32(bg_rect.x),
		y = i32(bg_rect.y),
		w = i32(bg_rect.w),
		h = i32(bg_rect.h),
	}
	sdl.SetRenderClipRect(renderer, &clip_rect)

	start_idx := fe.scroll_offset
	end_idx := min(len(fe.entries), start_idx + fe.visible_height)

	for i := start_idx; i < end_idx; i += 1 {
		if i == fe.selected_index {
			y := fe.y + f32(i - start_idx) * f32(fe.item_height)
			highlight := sdl.FRect {
				x = fe.x,
				y = y,
				w = fe.width,
				h = f32(fe.item_height),
			}
			_ = sdl.SetRenderDrawColor(renderer, 0x40, 0x40, 0x60, 0xFF)
			_ = sdl.RenderFillRect(renderer, &highlight)
		}
	}
	original_color := fe.text_renderer.color
	for i := start_idx; i < end_idx; i += 1 {
		entry := &fe.entries[i]
		y := fe.y + f32(i - start_idx) * f32(fe.item_height)

		indent := f32(entry.depth * 20)
		x := fe.x + indent + 5

		icon := entry.is_dir ? (entry.is_open ? "↓" : "»") : "°"
		render_text(&fe.text_renderer, renderer, icon, x, y, fe.allocator)
		if (renderer == nil) {fmt.println("Test brokey")}

		filename_x := x + 25
		if entry.is_dir {
			fe.text_renderer.color = sdl.Color{0x80, 0xC0, 0xFF, 0xFF}
		} else {
			fe.text_renderer.color = sdl.Color{0xC0, 0xC0, 0xC0, 0xFF}
		}

		render_text(&fe.text_renderer, renderer, entry.name, filename_x, y, fe.allocator)
	}
	fe.text_renderer.color = original_color

	// 4. Border (optional, above background but below text feels fine too)
	_ = sdl.SetRenderDrawColor(renderer, 0x40, 0x40, 0x40, 0xFF)
	_ = sdl.RenderRect(renderer, &bg_rect)
}

handle_file_explorer_event :: proc(fe: ^File_Explorer, event: ^sdl.Event) -> bool {
	if !fe.is_visible {
		return false
	}

	#partial switch event.type {
	case sdl.EventType.KEY_DOWN:
		switch event.key.key {
		case 13:
			// enter
			if fe.selected_index >= 0 && fe.selected_index < len(fe.entries) {
				entry := &fe.entries[fe.selected_index]
				if entry.is_dir {
					toggle_directory(fe, fe.selected_index)
				} else {
					return true
				}
			}
		}
	case sdl.EventType.MOUSE_BUTTON_DOWN:
		if event.button.button == 1 {
			mouse_x := f32(event.button.x)
			mouse_y := f32(event.button.y)

			fmt.printf("Fe%d:SDLM:%d\n", fe.x, mouse_x)
			in_x_bounds := mouse_x >= fe.x && mouse_x <= fe.x + fe.width
			in_y_bounds :=
				mouse_y >= fe.y && mouse_y <= fe.y + f32(fe.visible_height * int(fe.item_height))

			if in_x_bounds && in_y_bounds {
				relative_y := mouse_y - fe.y
				clicked_idx := fe.scroll_offset + int(relative_y / f32(fe.item_height))

				if clicked_idx >= 0 && clicked_idx < len(fe.entries) {
					fe.selected_index = clicked_idx
					entry := &fe.entries[clicked_idx]

					if entry.is_dir {
						toggle_directory(fe, clicked_idx)
					}
				}
			}
		}
	}

	return false
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
