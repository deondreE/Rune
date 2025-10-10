package editor

import "core:fmt"
import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"

Top_Menu_Item :: struct {
	label: string,
	id:    string,
	width: f32,
}

Menu_Bar :: struct {
	items:       [dynamic]Top_Menu_Item,
	height:      i32,
	background:  sdl.Color,
	hover_index: int,
	is_visible:  bool,
	text_renderer: Text_Renderer,
	allocator:   mem.Allocator,
}

init_menu_bar :: proc(allocator: mem.Allocator, font_path: string = "assets/fonts/MapleMono-Regular.ttf", font_size: f32 = 10) -> Menu_Bar {
	bar: Menu_Bar
	bar.items = make([dynamic]Top_Menu_Item, allocator)
	bar.height = 28
	bar.background = sdl.Color{0x2C, 0x2C, 0x2C, 0xFF}
	bar.hover_index = -1
	bar.is_visible = true
	bar.allocator = allocator
	tr, ok := init_text_renderer(font_path, font_size, allocator)
	if !ok {
		fmt.println("Menu_Bar: Broken text renderer")
	}
	bar.text_renderer = tr

	append(&bar.items, Top_Menu_Item{"File", "file", 35})
	append(&bar.items, Top_Menu_Item{"Edit", "edit", 35})
	append(&bar.items, Top_Menu_Item{"View", "view", 35})
	append(&bar.items, Top_Menu_Item{"Help", "help", 35})
	return bar
}

destroy_menu_bar :: proc(bar: ^Menu_Bar) {
	delete(bar.items)
}

render_menu_bar :: proc(bar: ^Menu_Bar, renderer: ^sdl.Renderer) {
	if !bar.is_visible {return}

	_ = sdl.SetRenderDrawColor(
		renderer,
		bar.background.r,
		bar.background.g,
		bar.background.b,
		bar.background.a,
	)
	rect := sdl.FRect{0, 0, 9999, f32(bar.height)}
	_ = sdl.RenderFillRect(renderer, &rect)

	x_offset: f32 = 10
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
