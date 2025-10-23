package editor

import "core:fmt"
import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"
import sdl_image "vendor:sdl3/image"

Top_Menu_Item :: struct {
	label: string,
	id:    string,
	width: f32,
}

Menu_Bar :: struct {
	items:              [dynamic]Top_Menu_Item,
	height:             i32,
	background:         sdl.Color,
	hover_index:        int,
	is_visible:         bool,
	text_renderer:      Text_Renderer,
	renderer: ^sdl.Renderer,
	allocator:          mem.Allocator,
	is_dragging_window: bool,
	drag_offset_x:      i32,
	drag_offset_y:      i32,
	drag_area:          sdl.FRect,
	
	icon_texture: ^sdl.Texture,
	window_title: string,
}

init_menu_bar :: proc(
	allocator: mem.Allocator,
	font_path: string = "assets/fonts/MapleMono-Regular.ttf",
	font_size: f32 = 10,
	renderer: ^sdl.Renderer,
) -> Menu_Bar {
	bar: Menu_Bar
	bar.items = make([dynamic]Top_Menu_Item, allocator)
	bar.height = 28
	bar.background = sdl.Color{0x2C, 0x2C, 0x2C, 0xFF}
	bar.hover_index = -1
	bar.is_visible = true
	bar.allocator = allocator
	bar.window_title = "Rune"
	tr, ok := init_text_renderer(font_path, font_size, allocator)
	if !ok {
		fmt.println("Menu_Bar: Broken text renderer")
	}
	bar.text_renderer = tr
	bar.drag_area = sdl.FRect {
		x = 0,
		y = 0,
		w = 99999,
		h = f32(bar.height),
	}
	
	icon_path := "assets/icon/icon.png"
	icon_surface := sdl_image.Load(strings.clone_to_cstring(icon_path))
	if icon_surface == nil {
	    fmt.eprintln("Menu_Bar: Failed to load image")
	} else {
	    bar.icon_texture = sdl.CreateTextureFromSurface(renderer, icon_surface)
		sdl.DestroySurface(icon_surface)
	}
	assert(bar.icon_texture!=nil)
	
	append(&bar.items, Top_Menu_Item{"File", "file", 35})
	append(&bar.items, Top_Menu_Item{"Edit", "edit", 35})
	append(&bar.items, Top_Menu_Item{"View", "view", 35})
	append(&bar.items, Top_Menu_Item{"Help", "help", 35})
	return bar
}

destroy_menu_bar :: proc(bar: ^Menu_Bar) {
	destroy_text_renderer(&bar.text_renderer)
	delete(bar.items)
}

render_menu_bar :: proc(bar: ^Menu_Bar, renderer: ^sdl.Renderer, window_w: i32) {
	if !bar.is_visible {return}

	_ = sdl.SetRenderDrawColor(
		renderer,
		bar.background.r,
		bar.background.g,
		bar.background.b,
		bar.background.a,
	)
	rect := sdl.FRect{0, 0, f32(window_w), f32(bar.height)}
	_ = sdl.RenderFillRect(renderer, &rect)
	
	x_offset: f32 = 10
	center_y := (f32(bar.height) - f32(bar.text_renderer.line_height)) / 2.0
	
	if bar.icon_texture != nil {
	    
        icon_size := f32(bar.height - 6)
		icon_rect := sdl.FRect{
		    x = x_offset,
			y = (f32(bar.height) - icon_size) / 2.0,
			w = icon_size,
			h = icon_size,
		}
		_ = sdl.RenderTexture(renderer, bar.icon_texture, nil, &icon_rect)
		x_offset += icon_size + 6
	}
	
	if len(bar.window_title) > 0 {
	    render_text(&bar.text_renderer, renderer, bar.window_title, x_offset, center_y, bar.allocator)
		title_width := measure_text_width(&bar.text_renderer, bar.window_title)
		x_offset += title_width + 20
	}
	
	for item, idx in bar.items {
		text_x := x_offset + 6
		text_y := (f32(bar.height) - f32(bar.text_renderer.line_height)) / 2.0

		// Hover highlight
		if idx == bar.hover_index {
			h_rect := sdl.FRect{x_offset, 0, item.width, f32(bar.height)}
			_ = sdl.SetRenderDrawColor(renderer, 0x50, 0x50, 0x70, 0xFF)
			_ = sdl.RenderFillRect(renderer, &h_rect)
		}

		// Draw menu label
		render_text(&bar.text_renderer, renderer, item.label, text_x, text_y, bar.allocator)
		x_offset += item.width
	}

	_ = sdl.SetRenderDrawColor(renderer, 0x45, 0x45, 0x45, 0xFF)
	line_rect := sdl.FRect{0, f32(bar.height - 1), 9999, 1}
	_ = sdl.RenderFillRect(renderer, &line_rect)
}

handle_menu_bar_event :: proc(bar: ^Menu_Bar, event: ^sdl.Event, window: ^sdl.Window) -> bool {
	if !bar.is_visible {return false}

	current_mouse_x: f32 = 0
	current_mouse_y: f32 = 0
	#partial switch event.type {
	case .MOUSE_MOTION:
		current_mouse_x = event.motion.x
		current_mouse_y = event.motion.y
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		current_mouse_x = event.button.x
		current_mouse_y = event.button.y
	case: // For other event types, we might not have mouse coords, or don't care.
	}
	mouse_x_f32 := f32(current_mouse_x)
	mouse_y_f32 := f32(current_mouse_y)

	is_over_menu_item_area := false // Renamed for clarity to avoid confusion with `is_in_menu_area` from your code
	x_offset_items_check: f32 = 10
	if mouse_y_f32 < f32(bar.height) { 	// Only check if mouse is within the top bar height
		for item in bar.items {
			// Check if mouse_x is within item's bounds (including its padding)
			if mouse_x_f32 >= x_offset_items_check &&
			   mouse_x_f32 < x_offset_items_check + item.width {
				is_over_menu_item_area = true
				break
			}
			x_offset_items_check += item.width + 10 // Match render_menu_bar's spacing
		}
	}

	#partial switch event.type {
	case sdl.EventType.MOUSE_MOTION:
		if bar.is_dragging_window {
			window_x: i32
			window_y: i32
			sdl.GetWindowPosition(window, &window_x, &window_y)
			// calculate the changing pos
			new_x := window_x + i32(event.motion.x) - bar.drag_offset_x
			new_y := window_y + i32(event.motion.y) - bar.drag_offset_y

			sdl.SetWindowPosition(window, new_x, new_y)
			return true
		}

		if mouse_y_f32 < f32(bar.height) {
			x_offset: f32 = 10
			new_hover_index := 0
			
			found_hover := false
			for it, idx in bar.items {
			    pad := f32(5)
			    left := x_offset - pad
				right := x_offset + it.width + pad
				
				if mouse_x_f32 >= left && mouse_x_f32 < right {
                    new_hover_index = idx
                    break
				}
				
				x_offset += it.width + 10
			}
			if new_hover_index != bar.hover_index {
				bar.hover_index = new_hover_index
			}
		} else {
    		if bar.hover_index != -1 {
    		    bar.hover_index = -1   	
    		}
		}
		return false
	case sdl.EventType.MOUSE_BUTTON_DOWN:
		if event.button.button == sdl.BUTTON_LEFT {
			if mouse_y_f32 < f32(bar.height) {
			    if !is_over_menu_item_area {
					fmt.println("Menu item clicked: ", bar.items[bar.hover_index].label)
					bar.is_dragging_window = true
                    bar.drag_offset_x = i32(mouse_x_f32)
                    bar.drag_offset_y = i32(mouse_y_f32)
					return true
				} else {
    				x_offset_click: f32 = 10
    				for it, i in bar.items {
        				if mouse_x_f32 >= x_offset_click && mouse_x_f32 < x_offset_click + it.width {
                            fmt.println("Menu item clicked:", it.label, "(", it.id, ")")
                            return true
                        }
                        x_offset_click += it.width + 10
    				}
                    return true
				}
			} 
		}
		return false
	case sdl.EventType.MOUSE_BUTTON_UP:
		if event.button.button == sdl.BUTTON_LEFT {
			bar.is_dragging_window = false
		}
		return false
	}


	return false
}
