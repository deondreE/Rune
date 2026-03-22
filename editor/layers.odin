package editor

import "core:mem"
import "core:sort"
import vk "vendor:vulkan"

Layer_Kind :: enum u8 {
	Custom,
	Background,
	Selections,
	Cursor,
	Text,
	Decorations,
	Overlay,
}

Layer_Draw_Fn :: #type proc(
	layer: ^Layer,
	br: ^Batch_Renderer,
	atlas: ^Glyph_Atlas,
	ctx: ^Layer_Context,
)

Layer_Resize_Fn :: #type proc(layer: ^Layer)

Layer_Destroy_Fn :: #type proc(layer: ^Layer)

Layer :: struct {
	kind:       Layer_Kind,
	z_index:    int,
	enabled:    bool,
	name:       string,
	user_data:  rawptr,
	draw:       Layer_Draw_Fn,
	on_resize:  Layer_Resize_Fn,
	on_destroy: Layer_Destroy_Fn,
}

Layer_Context :: struct {
	viewport: [2]f32,
	font:     ^Font_Handle,
	scroll_x: f32,
	scroll_y: f32,
	tab_size: int,
}

Compositer :: struct {
	layers:    [dynamic]Layer,
	dirty:     bool,
	allocator: mem.Allocator,
}

init_compositor :: proc(allocator: mem.Allocator = context.allocator) -> Compositer {
	return Compositer {
		layers = make([dynamic]Layer, allocator),
		dirty = false,
		allocator = allocator,
	}
}

destroy_compositor :: proc(c: ^Compositer) {
	for &layer in c.layers {
		if layer.on_destroy != nil {
			layer.on_destroy(&layer)
		}
	}
	delete(c.layers)
}

add_layer :: proc(c: ^Compositer, layer: Layer) -> ^Layer {
	append(&c.layers, layer)
	c.dirty = true
	return &c.layers[len(c.layers) - 1]
}

remove_layer :: proc(c: ^Compositer, name: string) {
	for i in 0 ..< len(c.layers) {
		if c.layers[i].name != "" {
			c.layers[i].on_destroy(&c.layers[i])
		}
		ordered_remove(&c.layers, i)
		c.dirty = true
		return
	}
}

find_layer :: proc(c: ^Compositer, name: string) -> ^Layer {
	for &layer in c.layers {
		if layer.name == name {
			return &layer
		}
	}
	return nil
}

set_layer_enabled :: proc(c: ^Compositer, name: string, enabled: bool) {
	if l := find_layer(c, name); l != nil {
		l.enabled = enabled
	}
}

move_layer :: proc(c: ^Compositer, name: string, new_z: int) {
	if l := find_layer(c, name); l != nil {
		l.z_index = new_z
		c.dirty = true
	}
}

sort_layers_if_needed :: proc(c: ^Compositer) {
	if !c.dirty {
		return
	}

	sort.quick_sort(c.layers[:], proc(a, b: Layer) -> bool {
		return a.z_index < b.z_index
	})
	c.dirty = false
}

composite :: proc(c: ^Compositer, br: ^Batch_Renderer, atlas: ^Glyph_Atlas, lctx: ^Layer_Context) {
	sort_layers_if_needed(c)

	for &layer in c.layers {
		if !layer.enabled || layer.draw == nil {
			continue
		}

		layer.draw(&layer, br, atlas, lctx)
	}
}

notify_resize :: proc(c: ^Compositer, new_size: [2]f32) {
	for &layer in c.layers {
		if layer.on_resize != nil {
			layer.on_resize(&layer, new_size)
		}
	}
}

Background_Data :: struct {
	color: [4]f32,
}

make_background_layer :: proc(
	color: [4]f32,
	allocator: mem.Allocator = context.allocator,
) -> Layer {
	data := new(Background_Data, allocator)
	data.color = color

	return Layer {
		kind = .Background,
		z_index = -100,
		enabled = true,
		name = "background",
		user_data = data,
		draw = proc(layer: ^Layer, br: ^Batch_Renderer, atlas: ^Glyph_Atlas, ctx: ^Layer_Context) {
			d := cast(^Background_Data)layer.user_data
			push_rect(br, 0, 0, ctx.viewport[0], ctx.viewport[1], d.color)
		},
		on_destroy = proc(layer: ^Layer) {

		},
	}
}

Text_Layer_Data :: struct {
	buffer:      ^Gap_Buffer,
	font:        ^Font_Handle,
	text_color:  [4]f32,
	line_height: f32,
	padding:     [2]f32,
}

make_text_layer :: proc(
	buffer: ^Gap_Buffer,
	font: ^Font_Handle,
	text_color: [4]f32,
	line_height: f32,
	padding: f32,
	allocator: mem.Allocator = context.allocator,
) -> Layer {
	data := new(Text_Layer_Data, allocator)
	data.buffer = buffer
	data.font = font
	data.text_color = text_color
	data.line_height = line_height
	data.padding = padding

	return Layer {
		kind = .Text,
		z_index = 0,
		enabled = true,
		name = "text",
		user_data = data,
		draw = proc(
			layer: ^Layer,
			br: ^Batch_Renderer,
			atlas: ^Glyph_Atlas,
			lctx: ^Layer_Context,
		) {
			d := cast(^Text_Layer_Data)layer.user_data

			line_count := get_line_count(d.buffer)
			pen_y := d.padding[1] - lctx.scroll_y

			for line_idx in 0 ..< line_count {
				if pen_y + d.line_height < 0 {
					pen_y += d.line_height
					continue
				}
				if pen_y > lctx.viewport[1] {
					break
				}

				line_str := get_line(d.buffer, line_idx)
				defer delete(line_str)

				pen_x := d.padding[0] - lctx.scroll_x
				i := 0
				for i < len(line_str) {
					r, size := rune(line_str), i
					if line_str[i] >= 0x80 {
						r, size = decode_rune_at(line_str, i)
					}
					i += size


					if r == '\t' {
						space_info := get_glyph(atlas, d.font, ' ')
						pen_x += space_info.advance_x * f32(lctx.tab_size)
						continue
					}

					info := get_glyph(atlas, d.font, r)
					if info.size[0] > 0 {
						push_glyph(br, pen_x, pen_y + d.font.ascent, info, d.text_color)
					}
					pen_x += info.advance_x
				}

				pen_y += d.line_height
			}
		},
	}
}

Selection :: struct {
	start_line: int,
	start_col:  int,
	end_line:   int,
	end_col:    int,
}

Selection_Layer_Data :: struct {
	selections:  []Selection,
	color:       [4]f32,
	line_height: f32,
	char_width:  f32,
	padding:     [2]f32,
}

make_selection_layer :: proc(
	line_height: f32,
	char_width: f32,
	padding: [2]f32,
	color: [4]f32,
	allocator: mem.Allocator = context.allocator,
) -> Layer {
	data := new(Selection_Layer_Data, allocator)
	data.color = color
	data.line_height = line_height
	data.char_width = char_width
	data.padding = padding

	return Layer {
		kind = .Selections,
		z_index = -10,
		enabled = true,
		name = "selections",
		user_data = data,
		draw = proc(
			layer: ^Layer,
			br: ^Batch_Renderer,
			atlas: ^Glyph_Atlas,
			lctx: ^Layer_Context,
		) {
			d := cast(^Selection_Layer_Data)layer.user_data
			if d.selections == nil {
				return
			}
			for sel in d.selections {
				sl := min(sel.start_line, sel.end_line)
				el := max(sel.start_line, sel.end_line)
				for ln in sl ..= el {
					x0: f32
					x1: f32
					if ln == sl {
						x0 = d.padding[0] + f32(sel.start_col) * d.char_width - lctx.scroll_x
					} else {
						x0 = d.padding[0] - lctx.scroll_x
					}
					if ln == el {
						x1 = d.padding[0] + f32(sel.end_col) * d.char_width - lctx.scroll_x
					} else {
						x1 = lctx.viewport[0]
					}
					y0 := d.padding[1] + f32(ln) * d.line_height - lctx.scroll_x
					push_rect(br, x0, x1, y0, x1 - x0, d.line_height, d.color)
				}
			}
		},
	}
}

Cursor_Layer_Data :: struct {
	line:        int,
	col:         int,
	color:       [4]f32,
	width:       f32,
	line_height: f32,
	char_width:  f32,
	padding:     [2]f32,
}

make_cursor_layer :: proc(
	line_height: f32,
	char_width: f32,
	padding: [2]f32,
	color: [4]f32,
	caret_width: f32,
	allocator: mem.Allocator = context.allocator,
) -> Layer {
	data := new(Cursor_Layer_Data, allocator)
	data.color = color
	data.width = caret_width
	data.line_height = line_height
	data.char_width = char_width
	data.padding = padding

	return Layer {
		kind = .Cursor,
		z_index = 10,
		enabled = true,
		name = "cursor",
		user_data = data,
		draw = proc(
			layer: ^Layer,
			br: ^Batch_Renderer,
			atlas: ^Glyph_Atlas,
			lctx: ^Layer_Context,
		) {
			d := cast(^Cursor_Layer_Data)layer.user_data
			x := d.padding[0] + f32(d.col) * d.char_width - lctx.scroll_x
			y := d.padding[1] + f32(d.line) * d.line_height - lctx.scroll_y
			push_rect(br, x, y, d.width, d.line_height, d.color)
		},
	}
}

Line_Number_Layer_Data :: struct {
	buffer:      ^Gap_Buffer,
	font:        ^Font_Handle,
	fg_color:    [4]f32,
	bg_color:    [4]f32,
	gutter_w:    f32,
	line_height: f32,
	padding_top: f32,
}

make_line_number_layer :: proc(
	buffer: ^Gap_Buffer,
	font: ^Font_Handle,
	gutter_w: f32,
	line_height: f32,
	padding_top: f32,
	fg_color: [4]f32,
	bg_color: [4]f32,
	allocator: mem.Allocator = context.allocator,
) -> Layer {
	data := new(Line_Number_Layer_Data, allocator)
	data.buffer = buffer
	data.font = font
	data.fg_color = fg_color
	data.bg_color = bg_color
	data.gutter_w = gutter_w
	data.line_height = line_height
	data.padding_top = padding_top

	return Layer {
		kind = .Overlay,
		z_index = 100,
		enabled = true,
		name = "line_numbers",
		user_data = data,
		draw = proc(
			layer: ^Layer,
			br: ^Batch_Renderer,
			atlas: ^Glyph_Atlas,
			lctx: ^Layer_Context,
		) {
			d := cast(^Line_Number_Layer_Data)layer.user_data

			push_rect(br, 0, 0, d.gutter_w, lctx.viewport[1], d.bg_color)

			line_count := get_line_count(d.buffer)
			pen_y := d.padding_top - lctx.scroll_y

			for ln in 0 ..< line_count {
				if pen_y + d.line_height < 0 {
					pen_y += d.line_height
					continue
				}
				if pen_y > lctx.viewport[1] {
					break
				}

				num := ln + 1
				buf: [16]u8
				s := fmt_int_buf(buf[:], num)

				pen_x := d.gutter_w - f32(len(s)) * get_glyph(atlas, d.font, '0').advance_x
				for r in s {
					info := get_glyph(atlas, d.font, r)
					push_glyph(br, pen_x, pen_y + d.font.ascent, info, d.fg_color)
					pen_x += info.advance_x
				}
				pen_y += d.line_height
			}
		},
	}
}

@(private = "file")
decode_rune_at :: proc(s: string, i: int) -> (r: rune, size: int) {
	if i >= len(s) {
		return 0xFFFD, 1
	}
	b := s[i]
	switch {
	case b < 0x80:
		return rune(b), 1
	case b < 0xE0 && i + 1 < len(s):
		return rune(b & 0x1F) << 6 | rune(s[i + 1] & 0x3F), 2
	case b < 0xF0 && i + 2 < len(s):
		return rune(b & 0x0F) << 12 | rune(s[i + 1] & 0x3F) << 6 | rune(s[i + 2] & 0x3F), 3
	case i + 3 < len(s):
		return (rune(b & 0x07) << 18 |
				rune(s[i + 1] & 0x3F) << 12 |
				rune(s[i + 2] & 0x3F) << 6 |
				rune(s[i + 3] & 0x3F)),
			4
	}
}

@(private = "file")
fmt_int_buf :: proc(buf: []u8, n: int) -> string {
	if n == 0 {
		buf[len(buf) - 1] = '0'
		return string(buf[len(buf) - 1:])
	}
	i := len(buf)
	v := n
	for v > 0 {
		i -= 1
		buf[i] = u8('0' + v % 10)
		v /= 10
	}
	return string(buf[i:])
}
