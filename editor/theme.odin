package editor

import sdl "vendor:sdl3"
import mem "core:mem"

Theme :: struct {
    // Core UI
    background: sdl.Color,
    border: sdl.Color,
    text: sdl.Color,
    text_secondary: sdl.Color,
    // File Explorer
    explorer_bg: sdl.Color,
    explorer_text: sdl.Color,
    explorer_dir: sdl.Color,
    explorer_select: sdl.Color,
    // Menu bar
    menu_bg: sdl.Color,
    menu_hover: sdl.Color,
    menu_text: sdl.Color,
    // Search bar
    sb_bg: sdl.Color,
    sb_select: sdl.Color,
    sb_text: sdl.Color,
    // Status bar
    status_bg: sdl.Color,
    status_text: sdl.Color,
    // Editor text area
    cursor: sdl.Color,
    selection_bg: sdl.Color,
    selection_text: sdl.Color,
    line_number_text: sdl.Color,
}

init_default_theme :: proc() -> Theme {
	return Theme{
		background       = sdl.Color{0x12, 0x12, 0x12, 0xFF},
		border           = sdl.Color{0x2A, 0x2A, 0x2A, 0xFF},
		text             = sdl.Color{0xDD, 0xDD, 0xDD, 0xFF},
		text_secondary   = sdl.Color{0x88, 0x88, 0x88, 0xFF},

		explorer_bg      = sdl.Color{0x18, 0x18, 0x18, 0xFF},
		explorer_text    = sdl.Color{0xC8, 0xC8, 0xC8, 0xFF},
		explorer_dir     = sdl.Color{0x7B, 0xC7, 0xFF, 0xFF},
		explorer_select  = sdl.Color{0x26, 0x4D, 0x8C, 0xFF},

		menu_bg          = sdl.Color{0x1B, 0x1B, 0x1B, 0xFF},
		menu_hover       = sdl.Color{0x34, 0x4C, 0x7F, 0xFF},
		menu_text        = sdl.Color{0xF0, 0xF0, 0xF0, 0xFF},

		sb_bg            = sdl.Color{0x15, 0x15, 0x15, 0xFF},
		sb_select        = sdl.Color{0x33, 0x66, 0x99, 0xFF},
		sb_text          = sdl.Color{0xE6, 0xE6, 0xE6, 0xFF},
		
		status_bg        = sdl.Color{0x20, 0x20, 0x20, 0xFF},
		status_text      = sdl.Color{0xC8, 0xC8, 0xC8, 0xFF},

		cursor           = sdl.Color{0xFF, 0xFF, 0xFF, 0xFF},
		selection_bg     = sdl.Color{0x33, 0x5F, 0xA9, 0x80},
		selection_text   = sdl.Color{0xFF, 0xFF, 0xFF, 0xFF},
		line_number_text = sdl.Color{0x66, 0x66, 0x66, 0xFF},
	}
}

load_user_theme :: proc(path: string, allocator: mem.Allocator) -> (Theme, bool) {
    theme := init_default_theme()
    return theme, true
}