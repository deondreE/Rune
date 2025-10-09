package main

import "core:fmt"
import "core:os"
import "core:time"
import editor "editor"
import sdl "vendor:sdl3"

WINDOW_WIDTH :: 1200
WINDOW_HEIGHT :: 800
WINDOW_TITLE :: "Odin Code Editor"

main :: proc() {
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

		// Rendering
		// sdl.SetRenderDrawColor(renderer, 0x00, 0x00, 0xFF, 0xFF)
		// sdl.RenderClear(renderer)

		// sdl.RenderPresent(renderer)
		// time.sleep(time.Duration(16 * time.Millisecond)) // ~60 fps
	}

	fmt.println("Application gracefully quit")
}
