package editor

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import sdl "vendor:sdl3"
import mem "core:mem"
import "core:fmt"

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

// Initializes the default config. -- RGBA, u32 format. 
init_default_theme :: proc(theme_type: string) -> Theme {
    if theme_type == "light" {
        return Theme{
		// === Core UI ===
		background       = sdl.Color{242, 236, 188, 255}, // Base parchment
		border           = sdl.Color{233, 229, 199, 255}, // Panel border beige
		text             = sdl.Color{84, 84, 100, 255},   // Main ink (Lotus Ink 1)
		text_secondary   = sdl.Color{111, 111, 112, 255}, // Muted ink (Lotus Ink 2)
        
		// === File Explorer ===
		explorer_bg      = sdl.Color{238, 232, 201, 255}, // slightly darker panel beige
		explorer_text    = sdl.Color{84, 84, 100, 255},
		explorer_dir     = sdl.Color{101, 133, 148, 255}, // Lotus Blue
		explorer_select  = sdl.Color{179, 94, 89, 85},    // Lotus Orange (translucent)
        
		// === Menu Bar ===
		menu_bg          = sdl.Color{233, 229, 199, 255},
		menu_hover       = sdl.Color{240, 231, 202, 255},
		menu_text        = sdl.Color{84, 84, 100, 255},
        
		// === Search Bar ===
		sb_bg            = sdl.Color{238, 232, 201, 255},
		sb_select        = sdl.Color{101, 133, 148, 255}, // accent blue
		sb_text          = sdl.Color{84, 84, 100, 255},
        
		// === Status Bar ===
		status_bg        = sdl.Color{233, 229, 199, 255},
		status_text      = sdl.Color{111, 111, 112, 255},
        
		// === Editor / Cursor / Selection ===
		cursor           = sdl.Color{179, 94, 89, 255},   // warm Lotus Orange caret
		selection_bg     = sdl.Color{101, 133, 148, 63},  // semi‑transparent Lotus Blue
		selection_text   = sdl.Color{0, 0, 0, 255},       // text on selection
		line_number_text = sdl.Color{111, 111, 112, 255}, // muted numbers
        }     
    } else {
        return Theme{
            // === General ===
            background       = sdl.Color{30, 30, 46, 255},    // Base
            border           = sdl.Color{49, 50, 68, 255},    // Surface0
            text             = sdl.Color{205, 214, 244, 255}, // Text
            text_secondary   = sdl.Color{166, 173, 200, 255}, // Subtext0
        
            // === File Explorer ===
            explorer_bg      = sdl.Color{24, 24, 37, 255},    // Mantle
            explorer_text    = sdl.Color{205, 214, 244, 255}, // Text
            explorer_dir     = sdl.Color{137, 180, 250, 255}, // Blue
            explorer_select  = sdl.Color{69, 71, 90, 255},    // Surface1
        
            // === Menu Bar ===
            menu_bg          = sdl.Color{24, 24, 37, 255},    // Mantle
            menu_hover       = sdl.Color{69, 71, 90, 255},    // Surface1
            menu_text        = sdl.Color{205, 214, 244, 255}, // Text
        
            // === Search Bar ===
            sb_bg            = sdl.Color{49, 50, 68, 255},    // Surface0
            sb_select        = sdl.Color{137, 180, 250, 255}, // Blue
            sb_text          = sdl.Color{205, 214, 244, 255}, // Text
        
            // === Status Bar ===
            status_bg        = sdl.Color{17, 17, 27, 255},    // Crust
            status_text      = sdl.Color{186, 194, 222, 255}, // Subtext1
        
            // === Cursor & Selection ===
            cursor           = sdl.Color{245, 224, 220, 255}, // Rosewater
            selection_bg     = sdl.Color{137, 180, 250, 64},  // Blue, semi-transparent
            selection_text   = sdl.Color{245, 224, 220, 255}, // Rosewater
            line_number_text = sdl.Color{88, 91, 112, 255},   // Surface2
        }
    }
    
   return {} 
}

DEFAULT_CONFIG_PATH :: "assets/settings"

// Writes the default config to the default user path.
write_default_config :: proc(theme: Theme, allocator: mem.Allocator, theme_type: string) {
    config_dir := DEFAULT_CONFIG_PATH
    is_dark := false
    if theme_type == "dark" { is_dark = true } 
    config_path := filepath.join({config_dir, is_dark ? "catputtion.json" : "light.json"}, allocator)
    defer delete(config_path, allocator)
    
    if !os.exists(config_dir) {
        err := os.make_directory(config_dir)
        if err != os.ERROR_NONE {
            fmt.eprintln("Failed to create dir")
            return
        }
    }
    
    
    color_to_map :: proc(c: sdl.Color) -> map[string]u8{
        m := make(map[string]u8, context.allocator)
        m["r"] = c.r
        m["g"] = c.g
        m["b"] = c.b
        return m
    }
    
    theme_map := make(map[string]any, allocator)
    theme_map["background"]       = color_to_map(theme.background)
    theme_map["border"]           = color_to_map(theme.border)
    theme_map["text"]             = color_to_map(theme.text)
    theme_map["text_secondary"]   = color_to_map(theme.text_secondary)
    theme_map["explorer_bg"]      = color_to_map(theme.explorer_bg)
    theme_map["explorer_text"]    = color_to_map(theme.explorer_text)
    theme_map["explorer_dir"]     = color_to_map(theme.explorer_dir)
    theme_map["explorer_select"]  = color_to_map(theme.explorer_select)
    theme_map["menu_bg"]          = color_to_map(theme.menu_bg)
    theme_map["menu_hover"]       = color_to_map(theme.menu_hover)
    theme_map["menu_text"]        = color_to_map(theme.menu_text)
    theme_map["sb_bg"]            = color_to_map(theme.sb_bg)
    theme_map["sb_select"]        = color_to_map(theme.sb_select)
    theme_map["sb_text"]          = color_to_map(theme.sb_text)
    theme_map["status_bg"]        = color_to_map(theme.status_bg)
    theme_map["status_text"]      = color_to_map(theme.status_text)
    theme_map["cursor"]           = color_to_map(theme.cursor)
    theme_map["selection_bg"]     = color_to_map(theme.selection_bg)
    theme_map["selection_text"]   = color_to_map(theme.selection_text)
    theme_map["line_number_text"] = color_to_map(theme.line_number_text)
 
    json_bytes, ok := json.marshal(theme, json.Marshal_Options{pretty = true}, allocator)
    if ok != nil {
        fmt.eprintf("X Failed to create marshel to JSON: %v", ok)
        return
    }
    defer delete(json_bytes, allocator)
    
    write_ok := os.write_entire_file(config_path, transmute([]byte)json_bytes)
    if !write_ok {
        fmt.println("Failed to write file")
        return
    }
    
    fmt.println("Wrote json")
}

// TODO: To set editor theme just use "default" as the string input for init_default_theme.

// Loads a default provided theme, or a user path provided theme. Will assume default if no user path is provided.
load_user_theme :: proc(path: string, allocator: mem.Allocator) -> (Theme, bool) {
    theme := init_default_theme("dark")
    write_default_config(theme, allocator, "dark")
    return theme, true
}