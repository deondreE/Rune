package editor

import "vendor:miniaudio"
import "core:mem"
import "core:fmt"
import sdl "vendor:sdl3"

Minimap :: struct {
    width: f32,
    scale: f32,
    background: sdl.Color,
    text_color: sdl.Color,
    viewport_color: sdl.Color,
    is_viisible: bool,
}

init_minimap :: proc() -> Minimap {
    return Minimap{
        width = 100.0,
        scale = 0.5,
        background = sdl.Color{30, 30, 40, 122},
        text_color = sdl.Color{90, 95, 120, 255},
        viewport_color = sdl.Color{120, 120, 160, 100},
        is_viisible = true,
    }
}

toggle_minimap :: proc(minimap: ^Minimap) {
    minimap.is_viisible = !minimap.is_viisible
}

render_minimap :: proc(minimap: ^Minimap, editor: ^Editor, renderer: ^sdl.Renderer, window_w, window_h: i32) {
    if !minimap.is_viisible {
        return
    }
    
    x_offset := f32(window_w) - minimap.width
    bg_rect := sdl.FRect{
        x = x_offset,
        y = 0,
        w = minimap.width,
        h = f32(window_h),
    }
    _ = sdl.SetRenderDrawColor(renderer,
        editor.theme.minimap_bg.r,
        editor.theme.minimap_bg.g,
        editor.theme.minimap_bg.b,
        editor.theme.minimap_bg.a)
    _ = sdl.SetRenderDrawBlendMode(renderer, {.MOD})
    _ = sdl.RenderFillRect(renderer, &bg_rect)
    _ = sdl.SetRenderDrawBlendMode(renderer, {.BLEND})
    
    lines := get_lines(&editor.gap_buffer, editor.allocator)
    defer {
        for line in lines do delete(line, editor.allocator)
        delete(lines, editor.allocator)
    }
    
    step := f32(editor.line_height) * minimap.scale
    y := f32(0)
    color := minimap.text_color 
    editor.text_renderer.color = color
    _ = sdl.SetRenderDrawColor(renderer, editor.theme.minimap_text_color.r, editor.theme.minimap_text_color.g, editor.theme.minimap_text_color.b, editor.theme.minimap_text_color.a)
    
    max_visibile_lines := int(f32(window_h) / step)
    for line in lines {
        if y > f32(window_h) { break }
        if len(line) == 0 {
            y += step
            continue
        }
    
        txt := line
        text_w := measure_text_width(&editor.text_renderer, txt)
        text_h := f32(editor.line_height)
    
        // Clip long lines
        max_w := minimap.width - 8
        if text_w > max_w / minimap.scale {
            rune_limit := int((max_w / (text_w / f32(len(line)))))-3
            if rune_limit > 3 && rune_limit < len(line) {
                txt = line[:rune_limit]
            }
            text_w = max_w / minimap.scale
        }
    
        // We fetch the text as texture once (cached)
        tex, w, h, ok := get_cached_text_texture(&editor.text_renderer, renderer, txt, minimap.text_color)
        if ok && tex != nil {
            dst := sdl.FRect{
                x = x_offset + 4.0,
                y = y,
                w = w * minimap.scale, // scaled down drawing
                h = h * minimap.scale,
            }
            _ = sdl.RenderTexture(renderer, tex, nil, &dst)
        }
        y += step
    }
    
    editor.text_renderer.color = color
}