package editor

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import sdl "vendor:sdl3"
import mem "core:mem"
import "core:fmt"

Theme :: struct {
}

// @TODO: Theme to file
//
// Theme to color

/// Barley used, might remove
hash :: proc(s: string) -> u16 {
    h: u32 = 2166136261
    for b in s {
        h = (h ~ u32(b)) * 16777619
    }
    return u16(h & 0xFFFF)
}
