package editor

import "core:fmt"
import "core:mem"
import "core:slice"
import sdl "vendor:sdl3"

Menu_Item :: struct {
	label: string,
	id:    string,
}

Context_Menu :: struct {
	is_visible:     bool,
	items:          [dynamic]Menu_Item,
	x, y:           f32,
	width:          f32,
	item_height:    i32,
	selected_index: int,
	allocator:      mem.Allocator,
}

init_context_menu :: proc(allocator: mem.Allocator) -> Context_Menu {
	menu: Context_Menu
	menu.allocator = allocator
	menu.items = make([dynamic]Menu_Item, allocator)
	menu.width = 180
	menu.item_height = 26
	menu.is_visible = false

	append(&menu.items, Menu_Item{label = "Cut", id = "edit.cut"})
	append(&menu.items, Menu_Item{label = "Copy", id = "edit.copy"})
	append(&menu.items, Menu_Item{label = "Paste", id = "edit.paste"})
	append(&menu.items, Menu_Item{label = "---", id = "seperator"})
	append(&menu.items, Menu_Item{label = "Select All", id = "edit.select_all"})
	append(&menu.items, Menu_Item{label = "Find...", id = "edit.find"})
	append(&menu.items, Menu_Item{label = "Go to Line...", id = "edit.goto_line"})
	return menu
}

destroy_context_menu :: proc(menu: ^Context_Menu) {
	// for item in menu.items {
	//   delete(item.label, menu.allocator)
	//   delete(item.id, menu.allocator)
	// }
	delete(menu.items)
}

show_context_menu :: proc(menu: ^Context_Menu, x: f32, y: f32) {
	clear(&menu.items)
	for it in menu.items {
		append(&menu.items, it)
	}
	menu.x = x
	menu.y = y
	menu.selected_index = -1
	menu.is_visible = true
}

hide_context_menu :: proc(menu: ^Context_Menu) {
	menu.is_visible = false
}

render_context_menu :: proc(menu: ^Context_Menu, renderer: ^sdl.Renderer, tr: ^Text_Renderer) {
	if !menu.is_visible || len(menu.items) == 0 {
		return
	}

	total_h := f32(len(menu.items) * int(menu.item_height))
	bg_rect := sdl.FRect {
		x = menu.x,
		y = menu.y,
		w = menu.width,
		h = total_h,
	}
	_ = sdl.SetRenderDrawColor(renderer, 0x30, 0x30, 0x30, 0xEE)
	_ = sdl.RenderFillRect(renderer, &bg_rect)
	_ = sdl.SetRenderDrawColor(renderer, 0x50, 0x50, 0x50, 0xFF)
	_ = sdl.RenderRect(renderer, &bg_rect)

	for it, idx in menu.items {
		y := menu.y + f32(idx * int(menu.item_height))
		if idx == menu.selected_index {
			highlight := sdl.FRect {
				x = menu.x,
				y = y,
				w = menu.width,
				h = f32(menu.item_height),
			}
			_ = sdl.SetRenderDrawColor(renderer, 0x55, 0x55, 0x88, 0xFF)
			_ = sdl.RenderFillRect(renderer, &highlight)
		}
		render_text(
			tr,
			renderer,
			it.label,
			menu.x + 10,
			menu.y + 3,
			menu.allocator,
			{0x55, 0x55, 0x55, 0xFF},
		)
	}
}

handle_context_menu_event :: proc(menu: ^Context_Menu, event: ^sdl.Event) -> string {
	if !menu.is_visible {
		return ""
	}

	#partial switch event.type {
	case sdl.EventType.MOUSE_MOTION:
		mouse_y := f32(event.motion.y)
		if mouse_y >= menu.y && mouse_y <= menu.y + f32(len(menu.items) * int(menu.item_height)) {
			menu.selected_index = int((mouse_y - menu.y) / f32(menu.item_height))
		}

	case sdl.EventType.MOUSE_BUTTON_DOWN:
		if event.button.button == sdl.BUTTON_LEFT && menu.selected_index >= 0 {
			id := menu.items[menu.selected_index].id
			hide_context_menu(menu)
			return id
		} else if event.button.button == sdl.BUTTON_RIGHT {
			hide_context_menu(menu)
		}
	}

	return ""
}
