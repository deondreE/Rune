package editor

import sdl "vendor:sdl3"

/*
  I want a conversion process
    - Take a FRECT and convert it to a gpu renderable rect.
     - Samethiing would apply to text

   * Cursor
     * cursor_highlight
     * cursor_blink
*/

GeometryData :: struct {
	texture:  ^sdl.Texture,
	vertices: []sdl.Vertex,
	indices:  []i32,
}

convert_color_to_fcolor :: proc(color: sdl.Color) -> sdl.FColor {
	factor := f32(1.0 / 255.0)
	return sdl.FColor {
		f32(color[0]) * factor,
		f32(color[1]) * factor,
		f32(color[2]) * factor,
		f32(color[3]) * factor,
	}
}

rect_to_geometry :: proc(rect: sdl.FRect, color: sdl.Color) -> GeometryData {
	vertices := make([]sdl.Vertex, 4)
	indices := make([]i32, 6)

	vertices[0] = sdl.Vertex {
		position  = sdl.FPoint{rect.x, rect.y},
		color     = convert_color_to_fcolor(color),
		tex_coord = sdl.FPoint{0, 0},
	}
	indices[0] = 0
	indices[1] = 1
	vertices[1] = sdl.Vertex {
		position  = sdl.FPoint{rect.x + rect.w, rect.y},
		color     = convert_color_to_fcolor(color),
		tex_coord = sdl.FPoint{0, 0},
	}
	indices[2] = 2
	indices[3] = 2
	vertices[2] = sdl.Vertex {
		position  = sdl.FPoint{rect.x + rect.w, rect.y + rect.h},
		color     = convert_color_to_fcolor(color),
		tex_coord = sdl.FPoint{0, 0},
	}
	indices[4] = 3
	indices[5] = 0
	vertices[3] = sdl.Vertex {
		position  = sdl.FPoint{rect.x, rect.y + rect.h},
		color     = convert_color_to_fcolor(color),
		tex_coord = sdl.FPoint{0, 0},
	}

	return GeometryData{texture = nil, vertices = vertices, indices = indices}
}

text_to_geometry :: proc(
    texture: ^sdl.Texture,
    x, y, w, h: f32,
    color: sdl.Color,
) -> GeometryData {
    vertices := make([]sdl.Vertex, 4)
    indices := make([]i32, 6)
    
    fcolor := convert_color_to_fcolor(color)
    
    // Top-Left (0)
	vertices[0] = sdl.Vertex {
		position  = sdl.FPoint{x, y},
		color     = fcolor,
		tex_coord = sdl.FPoint{0, 0}, // Top-left of the texture
	}
	// Top-Right (1)
	vertices[1] = sdl.Vertex {
		position  = sdl.FPoint{x + w, y},
		color     = fcolor,
		tex_coord = sdl.FPoint{1, 0}, // Top-right of the texture
	}
	// Bottom-Right (2)
	vertices[2] = sdl.Vertex {
		position  = sdl.FPoint{x + w, y + h},
		color     = fcolor,
		tex_coord = sdl.FPoint{1, 1}, // Bottom-right of the texture
	}
	// Bottom-Left (3)
	vertices[3] = sdl.Vertex {
		position  = sdl.FPoint{x, y + h},
		color     = fcolor,
		tex_coord = sdl.FPoint{0, 1}, // Bottom-left of the texture
	}
   
	indices[0] = 0
	indices[1] = 1
	indices[2] = 2
   
	indices[3] = 0
	indices[4] = 2
	indices[5] = 3
   
	return GeometryData{texture = texture, vertices = vertices, indices = indices}
}