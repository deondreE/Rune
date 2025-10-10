package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sys/darwin/Security"
import "core:time"
import editor "editor"
import sdl "vendor:sdl3"
import sdl_image "vendor:sdl3/image"

WINDOW_WIDTH :: 1200
WINDOW_HEIGHT :: 800
WINDOW_TITLE :: "Odin Code Editor"
WINDOW_ICON_PATH :: "assets/icon/icon.png"

main :: proc() {
	allocator := context.allocator
	if !sdl.Init(sdl.INIT_VIDEO) {
		fmt.eprintf("SDL could not initialized! SDL_Error: %s\n", sdl.GetError())
		return
	}
	defer sdl.Quit()

	window := sdl.CreateWindow(
		WINDOW_TITLE,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		sdl.WindowFlags(sdl.WINDOW_RESIZABLE),
	)
	if window == nil {
		fmt.eprintf("Window could not be created! SDL_Error: %s\n", sdl.GetError())
		return
	}
	defer sdl.DestroyWindow(window)

	set_window_icon(window, allocator)
	_ = sdl.SetWindowFocusable(window, true)

	renderer := sdl.CreateRenderer(window, nil)
	if renderer == nil {
		fmt.eprintf("Renderer could not be created! SDL_Error: %s\n", sdl.GetError())
		return
	}
	defer sdl.DestroyRenderer(renderer)

	fmt.println("Initializing editor...")
	editor_state := editor.init_editor(window, renderer)
	defer editor.destroy_editor(&editor_state)

	_ = sdl.StartTextInput(window)
	defer if sdl.StopTextInput(window) {

	}

	running := true
	event: sdl.Event
	dt: f64 = 0.0
	last_frame_time := time.tick_now()

	for running {
		current_frame_time := time.tick_now()
		dt = time.duration_seconds(time.tick_diff(last_frame_time, current_frame_time))
		last_frame_time = current_frame_time

		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case sdl.EventType.QUIT:
				running = false
			case sdl.EventType.KEY_DOWN:
				if event.key.key == 27 {
					running = false
				}
				editor.handle_event(&editor_state, &event)
			case sdl.EventType.TEXT_INPUT:
				editor.handle_event(&editor_state, &event)
			}
		}

		editor.update(&editor_state, dt)
		editor.render(&editor_state)
	}

	fmt.println("Application gracefully quit")
}

set_window_icon :: proc(window: ^sdl.Window, allocator: mem.Allocator) {
	icon_path := WINDOW_ICON_PATH

	surface := sdl_image.Load(strings.clone_to_cstring(icon_path, allocator))
	if surface == nil {
		fmt.eprintf("Could not load window icon: %s:\n", icon_path)
		return
	}

	sdl.SetWindowIcon(window, surface)
}
