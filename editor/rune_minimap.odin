package editor

import "core:mem"
import "core:fmt"
import sdl "vendor:sdl3"

Minimap :: struct {
    width: f32,
    scale: f32,
    background: sdl.Color,
    text_color: sdl.Color,
    viewport_color: sdl.Color,
    viewport_border_color: sdl.Color,
    padding: f32,
    is_visible: bool,
    show_viewport_indicator: bool,
    char_width: f32,
}

init_minimap :: proc() -> Minimap {
    return Minimap{
        width = 100.0,
        scale = 0.1,
        background = sdl.Color{30, 30, 40, 122},
        text_color = sdl.Color{90, 95, 120, 255},
        viewport_color = sdl.Color{120, 120, 160, 100},
        viewport_border_color = sdl.Color{120, 120, 140, 150},
        is_visible = true,
        padding = 4.0,
        show_viewport_indicator = true,
        char_width = 1.0,
    }
}

toggle_minimap :: proc(minimap: ^Minimap) {
    minimap.is_visible = !minimap.is_visible
}

calculate_viewport_rect :: proc(minimap: ^Minimap, editor: ^Editor, window_w, window_h: i32) -> sdl.FRect {
    x_offset := f32(window_w) - minimap.width
    step := f32(editor.line_height) * minimap.scale

    visible_start := i32(editor.scroll_y) / editor.line_height
    visible_lines := int(f32(window_h) / f32(editor.line_height))

    viewport_y := f32(visible_start) * step
    viewport_h := f32(visible_lines) * step

    return sdl.FRect{
        x = x_offset,
        y = viewport_y,
        w = minimap.width,
        h = viewport_h,
    }
}

render_minimap :: proc(minimap: ^Minimap, editor: ^Editor, renderer: ^sdl.Renderer, window_w, window_h: i32) {
    if !minimap.is_visible {
        return
    }
    
    x_offset := f32(window_w) - minimap.width

    // Draw background
    bg_rect := sdl.FRect{
        x = x_offset,
        y = 0,
        w = minimap.width,
        h = f32(window_h),
    }
    _ = sdl.SetRenderDrawColor(renderer,
        minimap.background.r,
        minimap.background.g,
        minimap.background.b,
        minimap.background.a)
    _ = sdl.SetRenderDrawBlendMode(renderer, {.BLEND})
    _ = sdl.RenderFillRect(renderer, &bg_rect)
    
    // Get lines
    lines := get_lines(&editor.gap_buffer, editor.allocator)
    defer {
        for line in lines do delete(line, editor.allocator)
        delete(lines, editor.allocator)
    }
    
    if len(lines) == 0 {
        return
    }
    
    step := f32(editor.line_height) * minimap.scale
    max_visible_lines := int(f32(window_h) / step) + 1

    // Calculate which lines to render (with small buffer above and below)
    start_line := max(0, int(i32(editor.scroll_y) / editor.line_height) - 5)
    end_line := min(len(lines), start_line + max_visible_lines + 10)

    // Draw viewport indicator behind text
    if minimap.show_viewport_indicator {
        viewport_rect := calculate_viewport_rect(minimap, editor, window_w, window_h)
        
        // Fill
        _ = sdl.SetRenderDrawColor(renderer,
            minimap.viewport_color.r,
            minimap.viewport_color.g, 
            minimap.viewport_color.b,
            minimap.viewport_color.a)
        _ = sdl.RenderFillRect(renderer, &viewport_rect)
        
        // Border
        _ = sdl.SetRenderDrawColor(renderer,
            minimap.viewport_border_color.r,
            minimap.viewport_border_color.g, 
            minimap.viewport_border_color.b,
            minimap.viewport_border_color.a)
        _ = sdl.RenderRect(renderer, &viewport_rect)
    }

    // Save original color
    original_color := editor.text_renderer.color
    defer editor.text_renderer.color = original_color

    // Set minimap text color
    _ = sdl.SetRenderDrawColor(renderer, 
        minimap.text_color.r, 
        minimap.text_color.g, 
        minimap.text_color.b, 
        minimap.text_color.a)
    
    max_chars := int((minimap.width - minimap.padding * 2) / minimap.char_width)

    for i := start_line; i < end_line; i += 1 {
        line := lines[i]
        y := f32(i) * step

        if y + step < 0 || y > f32(window_h) {
            continue
        }

        if len(line) == 0 {
            continue   
        }

        txt := line
        if len(txt) > max_chars {
            txt = line[:max_chars]
        }

        line_width := f32(len(txt)) * minimap.char_width
        line_height := step * 0.8  // Slight gap between lines
        
        line_rect := sdl.FRect{
            x = x_offset + minimap.padding,
            y = y,
            w = line_width,
            h = line_height,
        }
        
        _ = sdl.RenderFillRect(renderer, &line_rect)
    }
}

handle_minimap_click :: proc(minimap: ^Minimap, editor: ^Editor, mouse_x, mouse_y: f32 , window_w, window_h: i32) -> bool {
    if !minimap.is_visible {
        return false
    }
    x_offset := f32(window_w) - minimap.width


    if f32(mouse_x) < x_offset {
        return false
    }

    step := f32(editor.line_height) * minimap.scale
    clicked_line := int(f32(mouse_y) / step)

    visible_lines := int(f32(window_h) / f32(editor.line_height))
    target_line := clicked_line - (visible_lines / 2)
    editor.scroll_y = int(max(0, i32(target_line) * editor.line_height))

    return true
}