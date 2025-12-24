package editor

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:thread"
import sdl "vendor:sdl3"
import sdl_image "vendor:sdl3/image"
import "vendor:windows/GameInput"

Top_Menu_Item :: struct {
	label: string,
	id:    string,
	width: f32,
}

Resize_Edge :: enum {
	None,
	Left,
	Right,
	Top,
	Bottom,
	TopLeft,
	TopRight,
	BottomLeft,
	BottomRight,
}

Window_Button :: enum {
	None,
	Minimize,
	Maximize,
	Close,
}

Menu_Bar :: struct {
	items:              [dynamic]Top_Menu_Item,
	height:             i32,
	background:         sdl.Color,
	hover_index:        int,
	is_visible:         bool,
	text_renderer:      Text_Renderer,
	renderer:           ^sdl.Renderer,
	allocator:          mem.Allocator,
	is_dragging_window: bool,
	drag_offset_x:      i32,
	drag_offset_y:      i32,
	drag_area:          sdl.FRect,
	icon_texture:       ^sdl.Texture,
	window_title:       string,
	editor:             ^Editor,
	is_resizing:        bool,
	resize_edge:        Resize_Edge,
	resize_start_x:     i32,
	resize_start_y:     i32,
	resize_start_w:     i32,
	resize_start_h:     i32,
	resize_threshold:   i32,
	hover_button:       Window_Button,
	button_size:        f32,
	is_maximized:       bool,
}

init_menu_bar :: proc(
	allocator: mem.Allocator,
	font_path: string = "assets/fonts/MapleMono-Regular.ttf",
	font_size: f32 = 10,
	renderer: ^sdl.Renderer,
	editor: ^Editor,
) -> Menu_Bar {
	bar: Menu_Bar
	bar.items = make([dynamic]Top_Menu_Item, allocator)
	bar.height = 28
	bar.editor = editor
	bar.background = editor.theme.menu_bg
	bar.hover_index = -1
	bar.is_visible = true
	bar.allocator = allocator
	bar.window_title = "Rune"
	bar.resize_threshold = 0
	bar.resize_edge = .None
	bar.hover_button = .None
	bar.button_size = f32(bar.height)
	bar.is_maximized = false
	tr, ok := init_text_renderer(font_path, font_size, renderer, allocator)
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
	assert(bar.icon_texture != nil)

	append(&bar.items, Top_Menu_Item{"File", "file", 35})
	append(&bar.items, Top_Menu_Item{"Edit", "edit", 35})
	append(&bar.items, Top_Menu_Item{"View", "view", 35})
	append(&bar.items, Top_Menu_Item{"Help", "help", 35})
	// append(&bar.items, Top_Menu_Item{"—", "-", 50})
	// append(&bar.items, Top_Menu_Item{"□", "O", 50})
	// append(&bar.items, Top_Menu_Item{"✕", "X", 50})
	return bar
}

destroy_menu_bar :: proc(bar: ^Menu_Bar) {
	destroy_text_renderer(&bar.text_renderer)
	delete(bar.items)
}

get_window_button_at_pos :: proc(bar: ^Menu_Bar, x, y: f32, window_w: i32) -> Window_Button {
	if y >= f32(bar.height) {
		return .None
	}

	button_width := bar.button_size

	close_x := f32(window_w) - button_width
	if x >= close_x && x < f32(window_w) {
		return .Close
	}

	maximize_x := close_x - button_width
	if x >= close_x && x < f32(window_w) {
		return .Close
	}

	minimize_x := maximize_x - button_width
	if x >= minimize_x && x < minimize_x {
		return .Minimize
	}

	return .None
}

draw_window_button :: proc(
	bar: ^Menu_Bar,
	renderer: ^sdl.Renderer,
	button: Window_Button,
	x, y: f32,
	is_hovered: bool,
) {
	button_rect := sdl.FRect {
		x = x,
		y = y,
		w = bar.button_size,
		h = f32(bar.height),
	}

	if is_hovered {
		if button == .Close {
			_ = sdl.SetRenderDrawColor(renderer, 0xE8, 0x1E, 0x23, 0xFF)
		} else {
			_ = sdl.SetRenderDrawColor(renderer, 0x50, 0x50, 0x50, 0xFF)
		}
		_ = sdl.RenderFillRect(renderer, &button_rect)
	}

	icon_color: sdl.Color
	if is_hovered && button == .Close {
		icon_color = {255, 255, 255, 255}
	} else {
		icon_color = {200, 200, 200, 255}
	}

	_ = sdl.SetRenderDrawColor(renderer, icon_color.r, icon_color.g, icon_color.b, icon_color.a)

	center_x := x + bar.button_size / 2
	center_y := f32(bar.height) / 2
	icon_size := f32(10)

	switch button {
	case .Minimize:
		line_y := center_y + icon_size / 2
		_ = sdl.RenderLine(
			renderer,
			center_x - icon_size / 2,
			line_y,
			center_x + icon_size / 2,
			line_y,
		)
	case .Maximize:
		if bar.is_maximized {
			small_size := icon_size * 0.7
			offset := icon_size * 0.2

			back_rect := sdl.FRect {
				x = center_x - small_size / 2 + offset,
				y = center_y - small_size / 2 - offset,
				w = small_size,
				h = small_size,
			}
			_ = sdl.RenderRect(renderer, &back_rect)

			front_rect := sdl.FRect {
				x = center_x - small_size / 2 - offset,
				y = center_y - small_size / 2 + offset,
				w = small_size,
				h = small_size,
			}
			_ = sdl.RenderFillRect(renderer, &front_rect)
			_ = sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
			_ = sdl.RenderRect(renderer, &front_rect)
		} else {
			square_rect := sdl.FRect {
				x = center_x - icon_size / 2,
				y = center_y - icon_size / 2,
				w = icon_size,
				h = icon_size,
			}
			_ = sdl.RenderRect(renderer, &square_rect)
		}
	case .Close:
		half := icon_size / 2
		_ = sdl.RenderLine(
			renderer,
			center_x - half,
			center_y - half,
			center_x + half,
			center_y + half,
		)
		_ = sdl.RenderLine(
			renderer,
			center_x + half,
			center_y - half,
			center_x - half,
			center_y + half,
		)
	case .None:
	}
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
		icon_rect := sdl.FRect {
			x = x_offset,
			y = (f32(bar.height) - icon_size) / 2.0,
			w = icon_size,
			h = icon_size,
		}
		_ = sdl.RenderTexture(renderer, bar.icon_texture, nil, &icon_rect)
		x_offset += icon_size + 6
	}

	if len(bar.window_title) > 0 {
		render_text(
			&bar.text_renderer,
			renderer,
			bar.window_title,
			x_offset,
			center_y,
			bar.allocator,
			{0xFF, 0xFF, 0xFF, 0xFF},
		)
		title_width := measure_text_width(&bar.text_renderer, bar.window_title)
		x_offset += title_width + 20
	}

	for item, idx in bar.items {
		text_x := x_offset + 6
		text_y := (f32(bar.height) - f32(bar.text_renderer.line_height)) / 2.0

		// Hover highlight
		if idx == bar.hover_index {
			h_rect := sdl.FRect{x_offset, 0, item.width, f32(bar.height)}
			_ = sdl.SetRenderDrawColor(
				renderer,
				bar.editor.theme.menu_hover.r,
				bar.editor.theme.menu_hover.g,
				bar.editor.theme.menu_hover.b,
				bar.editor.theme.menu_hover.a,
			)

			_ = sdl.RenderFillRect(renderer, &h_rect)
		}

		// Draw menu label
		render_text(
			&bar.text_renderer,
			renderer,
			item.label,
			text_x,
			text_y,
			bar.allocator,
			{0xFF, 0xFF, 0xFF, 0xFF},
		)
		x_offset += item.width
	}

	// Window control buttons right side
	button_width := bar.button_size
	button_start_x := f32(window_w) - (button_width * 3)

	draw_window_button(bar, renderer, .Minimize, button_start_x, 0, bar.hover_button == .Minimize)
	draw_window_button(
		bar,
		renderer,
		.Maximize,
		button_start_x + button_width,
		0,
		bar.hover_button == .Maximize,
	)
	draw_window_button(
		bar,
		renderer,
		.Close,
		button_start_x + button_width * 2,
		0,
		bar.hover_button == .Close,
	)


	_ = sdl.SetRenderDrawColor(renderer, 0x45, 0x45, 0x45, 0xFF)
	line_rect := sdl.FRect{0, f32(bar.height - 1), 9999, 1}
	_ = sdl.RenderFillRect(renderer, &line_rect)
}

get_resize_edge :: proc(
	bar: ^Menu_Bar,
	window: ^sdl.Window,
	mouse_x, mouse_y: i32,
) -> Resize_Edge {
	window_w: i32
	window_h: i32
	sdl.GetWindowSize(window, &window_w, &window_h)

	threshold := bar.resize_threshold
	at_left := mouse_x <= threshold
	at_right := mouse_x >= window_w - threshold
	at_top := mouse_y <= threshold
	at_bottom := mouse_y >= window_h - threshold

	if at_top && at_left {
		return .TopLeft
	}
	if at_top && at_right {
		return .TopRight
	}
	if at_bottom && at_left {
		return .BottomLeft
	}
	if at_bottom && at_right {
		return .BottomLeft
	}

	if at_left {
		return .Left
	}
	if at_right {
		return .Right
	}
	if at_bottom {
		return .Bottom
	}
	if at_top {
		return .Top
	}

	return .None
}

update_cursor_for_resize :: proc(edge: Resize_Edge) {
	cursor: sdl.SystemCursor

	switch (edge) {
	case .None:
		cursor = .DEFAULT
	case .Left, .Right:
		cursor = .EW_RESIZE
	case .Top, .Bottom:
		cursor = .NS_RESIZE
	case .TopLeft, .BottomRight:
		cursor = .NS_RESIZE
	case .TopRight, .BottomLeft:
		cursor = .NESW_RESIZE
	}

	sdl_cursor := sdl.CreateSystemCursor(cursor)
	if sdl_cursor != nil {
		b := sdl.SetCursor(sdl_cursor)
		if !b {
			fmt.print("Broken cursor set")
		}
	}
}

handle_window_resize :: proc(bar: ^Menu_Bar, window: ^sdl.Window, mouse_x, mouse_y: i32) {
	if !bar.is_resizing {
		return
	}

	window_x: i32
	window_y: i32
	sdl.GetWindowPosition(window, &window_x, &window_y)

	delta_x := mouse_x - bar.resize_start_x
	delta_y := mouse_y - bar.resize_start_y

	new_x := window_x
	new_y := window_y
	new_w := bar.resize_start_w
	new_h := bar.resize_start_h

	min_width := i32(400)
	min_height := i32(300)

	switch bar.resize_edge {
	case .Left:
		new_w = bar.resize_start_w - delta_x
		if new_w >= min_width {
			new_x = window_x + delta_x
		} else {
			new_w = min_width
		}

	case .Right:
		new_w = bar.resize_start_w + delta_x
		if new_w < min_width {
			new_w = min_width
		}

	case .Top:
		new_h = bar.resize_start_h - delta_y
		if new_h >= min_height {
			new_y = window_y + delta_y
		} else {
			new_h = min_height
		}

	case .Bottom:
		new_h = bar.resize_start_h + delta_y
		if new_h < min_height {
			new_h = min_height
		}

	case .TopLeft:
		new_w = bar.resize_start_w - delta_x
		new_h = bar.resize_start_h - delta_y
		if new_w >= min_width {
			new_x = window_x + delta_x
		} else {
			new_w = min_width
		}
		if new_h >= min_height {
			new_y = window_y + delta_y
		} else {
			new_h = min_height
		}

	case .TopRight:
		new_w = bar.resize_start_w + delta_x
		new_h = bar.resize_start_h - delta_y
		if new_w < min_width {
			new_w = min_width
		}
		if new_h >= min_height {
			new_y = window_y + delta_y
		} else {
			new_h = min_height
		}

	case .BottomLeft:
		new_w = bar.resize_start_w - delta_x
		new_h = bar.resize_start_h + delta_y
		if new_w >= min_width {
			new_x = window_x + delta_x
		} else {
			new_w = min_width
		}
		if new_h < min_height {
			new_h = min_height
		}

	case .BottomRight:
		new_w = bar.resize_start_w + delta_x
		new_h = bar.resize_start_h + delta_y
		if new_w < min_width {
			new_w = min_width
		}
		if new_h < min_height {
			new_h = min_height
		}

	case .None:
		return
	}

	// Apply changes
	if new_x != window_x || new_y != window_y {
		sdl.SetWindowSize(window, new_x, new_y)
	}
	if new_w != bar.resize_start_w || new_h != bar.resize_start_h {
		sdl.SetWindowSize(window, new_w, new_h)
	}
}

handle_menu_bar_event :: proc(bar: ^Menu_Bar, event: ^sdl.Event, window: ^sdl.Window) -> bool {
	if !bar.is_visible {
		return false
	}

	window_w: i32
	window_h: i32
	sdl.GetWindowSize(window, &window_w, &window_h)

	current_mouse_x: f32 = 0
	current_mouse_y: f32 = 0

	#partial switch event.type {
	case .MOUSE_MOTION:
		current_mouse_x = event.motion.x
		current_mouse_y = event.motion.y
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		current_mouse_x = event.button.x
		current_mouse_y = event.button.y
	}

	mouse_x_f32 := f32(current_mouse_x)
	mouse_y_f32 := f32(current_mouse_y)
	mouse_x_i32 := i32(current_mouse_x)
	mouse_y_i32 := i32(current_mouse_y)

	// Check if mouse is over window buttons
	hovered_button := get_window_button_at_pos(bar, mouse_x_f32, mouse_y_f32, window_w)
	bar.hover_button = hovered_button

	// Check if mouse is over menu items
	is_over_menu_item_area := false
	x_offset_items_check: f32 = 10
	if mouse_y_f32 < f32(bar.height) {
		for item in bar.items {
			if mouse_x_f32 >= x_offset_items_check &&
			   mouse_x_f32 < x_offset_items_check + item.width {
				is_over_menu_item_area = true
				break
			}
			x_offset_items_check += item.width + 10
		}
	}

	#partial switch event.type {
	case sdl.EventType.MOUSE_MOTION:
		// Handle active window resize
		if bar.is_resizing {
			handle_window_resize(bar, window, mouse_x_i32, mouse_y_i32)
			return true
		}

		// Handle active window dragging
		if bar.is_dragging_window {
			window_x: i32
			window_y: i32
			sdl.GetWindowPosition(window, &window_x, &window_y)

			new_x := window_x + i32(event.motion.x) - bar.drag_offset_x
			new_y := window_y + i32(event.motion.y) - bar.drag_offset_y

			sdl.SetWindowPosition(window, new_x, new_y)
			return true
		}

		// Update cursor for resize detection (only if not over window buttons)
		if hovered_button == .None {
			edge := get_resize_edge(bar, window, mouse_x_i32, mouse_y_i32)
			bar.resize_edge = edge
			update_cursor_for_resize(edge)
		}

		// Handle menu item hover
		if mouse_y_f32 < f32(bar.height) && hovered_button == .None {
			x_offset: f32 = 10
			new_hover_index := -1

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

			bar.hover_index = new_hover_index
		} else {
			bar.hover_index = -1
		}
		return false

	case sdl.EventType.MOUSE_BUTTON_DOWN:
		if event.button.button == sdl.BUTTON_LEFT {
			// Handle window button clicks
			if hovered_button != .None {
				switch hovered_button {
				case .Minimize:
					sdl.MinimizeWindow(window)
					fmt.println("Window minimized")

				case .Maximize:
					if bar.is_maximized {
						sdl.RestoreWindow(window)
						bar.is_maximized = false
						fmt.println("Window restored")
					} else {
						sdl.MaximizeWindow(window)
						bar.is_maximized = true
						fmt.println("Window maximized")
					}

				case .Close:
					fmt.println("Close button clicked - sending quit event")
					quit_event := sdl.Event{}
					quit_event.type = .QUIT
					b := sdl.PushEvent(&quit_event)

				case .None:
				}
				return true
			}

			edge := get_resize_edge(bar, window, mouse_x_i32, mouse_y_i32)
			if edge != .None {
				bar.is_resizing = true
				bar.resize_edge = edge
				bar.resize_start_x = mouse_x_i32
				bar.resize_start_y = mouse_y_i32

				sdl.GetWindowSize(window, &bar.resize_start_w, &bar.resize_start_h)
				return true
			}

			if mouse_y_f32 < f32(bar.height) {
				if !is_over_menu_item_area {
					bar.is_dragging_window = true
					bar.drag_offset_x = mouse_x_i32
					bar.drag_offset_y = mouse_y_i32
					return true
				} else {
					x_offset_click: f32 = 10
					for it, i in bar.items {
						if mouse_x_f32 >= x_offset_click &&
						   mouse_x_f32 < x_offset_click + it.width {
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
			bar.is_resizing = false
			bar.resize_edge = .None

			update_cursor_for_resize(.None)
		}
		return false
	}

	return false
}
