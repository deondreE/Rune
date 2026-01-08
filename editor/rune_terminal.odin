package editor

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import sdl "vendor:sdl3"

Terminal_Cell :: struct {
	rune:      rune,
	fg_color:  sdl.Color,
	bg_color:  sdl.Color,
	bold:      bool,
	underline: bool,
	reverse:   bool,
}

Terminal_Cursor :: struct {
	x:          int,
	y:          int,
	visible:    bool,
	blink_time: f32,
	blink_rate: f32,
}

Terminal_Buffer :: struct {
	cells:     [dynamic]Terminal_Cell,
	cols:      int,
	rows:      int,
	allocator: mem.Allocator,
}

Rune_Terminal :: struct {
	allocator:     mem.Allocator,
	buffer:        Terminal_Buffer,
	cursor:        Terminal_Cursor,
	scroll_offset: f32,
	scroll_target: f32,
	history:       [dynamic]string, // Command history
	history_index: int,
	current_line:  [dynamic]rune, // Current input line
	x:             f32,
	y:             f32,
	width:         f32,
	height:        f32,
	char_width:    f32,
	char_height:   f32,
	text_renderer: Text_Renderer,
	is_visible:    bool,
	is_focused:    bool,
	prompt:        string,
	working_dir:   string,

	// Colors
	bg_color:      sdl.Color,
	fg_color:      sdl.Color,
	cursor_color:  sdl.Color,
	prompt_color:  sdl.Color,
	error_color:   sdl.Color,
	success_color: sdl.Color,
}
init_terminal :: proc(
	x: f32 = 0,
	y: f32 = 0,
	width: f32 = 800,
	height: f32 = 400,
	font_path: string = "assets/fonts/MapleMono-Regular.ttf",
	font_size: f32 = 14,
	allocator: mem.Allocator = context.allocator,
) -> Rune_Terminal {
	tr, ok := init_text_renderer(font_path, font_size, nil, allocator)
	if !ok {
		fmt.println("Terminal: Failed to initialize font renderer")
	}

	char_width := f32(tr.line_height) * 0.6 // Approximate monospace width
	char_height := f32(tr.line_height)

	cols := int(width / char_width)
	rows := int(height / char_height)

	buffer := Terminal_Buffer {
		cells     = make([dynamic]Terminal_Cell, cols * rows, allocator),
		cols      = cols,
		rows      = rows,
		allocator = allocator,
	}

	default_cell := Terminal_Cell {
		rune     = ' ',
		fg_color = sdl.Color{200, 200, 200, 255},
		bg_color = sdl.Color{20, 20, 30, 255},
	}
	for i := 0; i < cols * rows; i += 1 {
		append(&buffer.cells, default_cell)
	}

	working_dir := os.get_current_directory(allocator)

	term := Rune_Terminal {
		allocator = allocator,
		buffer = buffer,
		cursor = Terminal_Cursor{x = 0, y = 0, visible = true, blink_time = 0, blink_rate = 1.0},
		scroll_offset = 0,
		scroll_target = 0,
		history = make([dynamic]string, allocator),
		history_index = 0,
		current_line = make([dynamic]rune, allocator),
		x = x,
		y = y,
		width = width,
		height = height,
		char_width = char_width,
		char_height = char_height,
		text_renderer = tr,
		is_visible = false,
		is_focused = false,
		prompt = "$ ",
		working_dir = working_dir,
		bg_color = sdl.Color{20, 20, 30, 255},
		fg_color = sdl.Color{200, 200, 200, 255},
		cursor_color = sdl.Color{100, 200, 255, 255},
		prompt_color = sdl.Color{100, 255, 150, 255},
		error_color = sdl.Color{255, 100, 100, 255},
		success_color = sdl.Color{100, 255, 100, 255},
	}

	// Print welcome message
	print_line(&term, "Rune Terminal v1.0", term.prompt_color)
	print_line(&term, fmt.tprintf("Working directory: %s", working_dir), term.fg_color)
	print_prompt(&term)

	return term
}

destroy_terminal :: proc(term: ^Rune_Terminal) {
	delete(term.buffer.cells)
	
	for line in term.history {
		delete(line, term.allocator)
	}
	delete(term.history)
	delete(term.current_line)
	delete(term.working_dir, term.allocator)
	
	destroy_text_renderer(&term.text_renderer)
}

// Get cell at position.
get_cell :: proc(term: ^Rune_Terminal, x, y: int) -> ^Terminal_Cell {
  if x < 0 || x >= term.buffer.cols || y < 0 || y >= term.buffer.rows {
    return nil
  }
  idx := y * term.buffer.cols + x
  return &term.buffer.cells[idx]
}

// Set cell at position
set_cell :: proc(term: ^Rune_Terminal, x, y: int, cell: Terminal_Cell) {
  if x < 0 || x >= term.buffer.cols || y < 0 || y >= term.buffer.rows {
    return
  }
  idx := y * term.buffer.cols + x
  term.buffer.cells[idx] = cell
}

// Clear the terminal
clear_terminal :: proc(term: ^Rune_Terminal) {
  default_cell := Terminal_Cell{
    rune     = ' ',
    fg_color = term.fg_color,
    bg_color = term.bg_color,
  }
  
  for i := 0; i < len(term.buffer.cells); i += 1 {
    term.buffer.cells[i] = default_cell
  }
  
  term.cursor.x = 0
  term.cursor.y = 0
}

// Scroll terminal up by one line
scroll_up :: proc(term: ^Rune_Terminal) {
  // Move all lines up
  for y := 1; y < term.buffer.rows; y += 1 {
    for x := 0; x < term.buffer.cols; x += 1 {
      src_idx := y * term.buffer.cols + x
      dst_idx := (y - 1) * term.buffer.cols + x
      term.buffer.cells[dst_idx] = term.buffer.cells[src_idx]
    }
  }
  
  // Clear bottom line
  default_cell := Terminal_Cell{
    rune     = ' ',
    fg_color = term.fg_color,
    bg_color = term.bg_color,
  }
  
  y := term.buffer.rows - 1
  for x := 0; x < term.buffer.cols; x += 1 {
    idx := y * term.buffer.cols + x
    term.buffer.cells[idx] = default_cell
  }
}

put_rune :: proc(term: ^Rune_Terminal, r: rune, color: sdl.Color) {
  if r == '\n' {
    term.cursor.x = 0
    term.cursor.y += 1
    
    if term.cursor.y >= term.buffer.rows {
      scroll_up(term)
      term.cursor.y = term.buffer.rows - 1
    }
    return
  }
  
  cell := Terminal_Cell{
    rune     = r,
    fg_color = color,
    bg_color = term.bg_color,
  }
  
  set_cell(term, term.cursor.x, term.cursor.y, cell)
  term.cursor.x += 1
  
  if term.cursor.x >= term.buffer.cols {
    term.cursor.x = 0
    term.cursor.y += 1
    
    if term.cursor.y >= term.buffer.rows {
      scroll_up(term)
      term.cursor.y = term.buffer.rows - 1
    }
  }
}

print_string :: proc(term: ^Rune_Terminal, text: string, color: sdl.Color) {
  for r in text {
    put_rune(term, r, color)
  }
}

print_line :: proc(term: ^Rune_Terminal, text: string, color: sdl.Color) {
  print_string(term, text, color)
  put_rune(term, '\n', color)
}

print_prompt :: proc(term: ^Rune_Terminal) {
  print_string(term, term.prompt, term.prompt_color)
}

execute_command :: proc(term: ^Rune_Terminal, command: string) {
  if len(command) == 0 {
    return
  }
  
  // Add to history
  append(&term.history, strings.clone(command, term.allocator))
  term.history_index = len(term.history)
  
  // Parse command
  parts := strings.split(command, " ", term.allocator)
  defer delete(parts, term.allocator)
  
  if len(parts) == 0 {
    return
  }
  
  cmd := parts[0]
  
  switch cmd {
  case "clear", "cls":
    clear_terminal(term)
    
  case "echo":
    if len(parts) > 1 {
      output := strings.join(parts[1:], " ", term.allocator)
      defer delete(output, term.allocator)
      print_line(term, output, term.fg_color)
    }
    
  case "help":
    print_line(term, "Available commands:", term.success_color)
    print_line(term, "  clear/cls  - Clear the terminal", term.fg_color)
    print_line(term, "  echo <msg> - Print a message", term.fg_color)
    print_line(term, "  help       - Show this help", term.fg_color)
    print_line(term, "  pwd        - Print working directory", term.fg_color)
    print_line(term, "  exit       - Close terminal", term.fg_color)
    
  case "pwd":
    print_line(term, term.working_dir, term.fg_color)
    
  case "exit":
    term.is_visible = false
    
  case:
    error_msg := fmt.tprintf("Unknown command: %s", cmd)
    print_line(term, error_msg, term.error_color)
  }
}

update_terminal :: proc(term: ^Rune_Terminal, dt: f32) {
  term.cursor.blink_time += dt
  if term.cursor.blink_time >= term.cursor.blink_rate {
    term.cursor.blink_time = 0
  }
  
  scroll_speed: f32 = 10.0
  scroll_diff := term.scroll_target - term.scroll_offset
  if abs(scroll_diff) > 0.1 {
    term.scroll_offset += scroll_diff * scroll_speed * dt
  } else {
    term.scroll_offset = term.scroll_target
  }
}

render_terminal :: proc(term: ^Rune_Terminal, renderer: ^sdl.Renderer) {
  if !term.is_visible {
    return
  }
  
  bg_rect := sdl.FRect{
    x = term.x,
    y = term.y,
    w = term.width,
    h = term.height,
  }
  _ = sdl.SetRenderDrawColor(renderer, term.bg_color.r, term.bg_color.g, term.bg_color.b, term.bg_color.a)
  _ = sdl.RenderFillRect(renderer, &bg_rect)
  
  border_color := sdl.Color{60, 60, 80, 255}
  _ = sdl.SetRenderDrawColor(renderer, border_color.r, border_color.g, border_color.b, border_color.a)
  _ = sdl.RenderRect(renderer, &bg_rect)
  
  clip_rect := sdl.Rect{
    x = i32(term.x),
    y = i32(term.y),
    w = i32(term.width),
    h = i32(term.height),
  }
  sdl.SetRenderClipRect(renderer, &clip_rect)
  
  // Render cells
  for y := 0; y < term.buffer.rows; y += 1 {
    for x := 0; x < term.buffer.cols; x += 1 {
      cell := get_cell(term, x, y)
      if cell == nil || cell.rune == ' ' {
        continue
      }
      
      px := term.x + f32(x) * term.char_width
      py := term.y + f32(y) * term.char_height
      
      // Render background if different from default
      if cell.bg_color != term.bg_color {
        cell_rect := sdl.FRect{
          x = px,
          y = py,
          w = term.char_width,
          h = term.char_height,
        }
        _ = sdl.SetRenderDrawColor(renderer, cell.bg_color.r, cell.bg_color.g, cell.bg_color.b, cell.bg_color.a)
        _ = sdl.RenderFillRect(renderer, &cell_rect)
      }
      
      // Render character
      rune_str := fmt.tprintf("%c", cell.rune)
      render_text(&term.text_renderer, renderer, rune_str, px, py, term.allocator, cell.fg_color)
    }
  }
  
  // Render cursor
  if term.is_focused && term.cursor.visible && (term.cursor.blink_time < term.cursor.blink_rate / 2) {
    cursor_rect := sdl.FRect{
      x = term.x + f32(term.cursor.x) * term.char_width,
      y = term.y + f32(term.cursor.y) * term.char_height,
      w = term.char_width,
      h = term.char_height,
    }
    _ = sdl.SetRenderDrawColor(renderer, term.cursor_color.r, term.cursor_color.g, term.cursor_color.b, 128)
    _ = sdl.RenderFillRect(renderer, &cursor_rect)
  }
  
  _ = sdl.SetRenderClipRect(renderer, nil)
}

handle_terminal_event :: proc(term: ^Rune_Terminal, event: ^sdl.Event) -> bool {
  if !term.is_visible {
    return false
  }
  
  #partial switch event.type {
  case .KEY_DOWN:
    if !term.is_focused {
      return false
    }
    
    switch event.key.key {
    case sdl.K_RETURN:
      // Execute current line
      put_rune(term, '\n', term.fg_color)
      
      s := term.current_line
      command := strings.clone_from_ptr(
          transmute(^u8) raw_data(s),
          len(s) * size_of(rune),
          term.allocator,
      )
      defer delete(command, term.allocator)
      
      execute_command(term, command)
      clear(&term.current_line)
      
      print_prompt(term)
      return true
      
    case sdl.K_BACKSPACE:
      if len(term.current_line) > 0 {
        pop(&term.current_line)
        
        // Move cursor back and clear character
        term.cursor.x -= 1
        if term.cursor.x < 0 {
          term.cursor.x = term.buffer.cols - 1
          term.cursor.y -= 1
        }
        
        cell := Terminal_Cell{
          rune     = ' ',
          fg_color = term.fg_color,
          bg_color = term.bg_color,
        }
        set_cell(term, term.cursor.x, term.cursor.y, cell)
      }
      return true
      
    case sdl.K_UP:
      // History navigation (previous)
      if term.history_index > 0 {
        term.history_index -= 1
        
        // Clear current line on screen
        for _ in term.current_line {
          term.cursor.x -= 1
          if term.cursor.x < 0 {
            term.cursor.x = term.buffer.cols - 1
            term.cursor.y -= 1
          }
          cell := Terminal_Cell{rune = ' ', fg_color = term.fg_color, bg_color = term.bg_color}
          set_cell(term, term.cursor.x, term.cursor.y, cell)
        }
        
        clear(&term.current_line)
        
        // Load from history
        if term.history_index < len(term.history) {
          history_cmd := term.history[term.history_index]
          for r in history_cmd {
            append(&term.current_line, r)
            put_rune(term, r, term.fg_color)
          }
        }
      }
      return true
      
    case sdl.K_DOWN:
      // History navigation (next)
      if term.history_index < len(term.history) {
        term.history_index += 1
        
        // Clear current line on screen
        for _ in term.current_line {
          term.cursor.x -= 1
          if term.cursor.x < 0 {
            term.cursor.x = term.buffer.cols - 1
            term.cursor.y -= 1
          }
          cell := Terminal_Cell{rune = ' ', fg_color = term.fg_color, bg_color = term.bg_color}
          set_cell(term, term.cursor.x, term.cursor.y, cell)
        }
        
        clear(&term.current_line)
        
        // Load from history or clear
        if term.history_index < len(term.history) {
          history_cmd := term.history[term.history_index]
          for r in history_cmd {
            append(&term.current_line, r)
            put_rune(term, r, term.fg_color)
          }
        }
      }
      return true
    }
    
  case .TEXT_INPUT:
    if !term.is_focused {
      return false
    }
    
    // Add text to current line
    text := string(event.text.text)
    for r in text {
        append(&term.current_line, r)
        put_rune(term, r, term.fg_color)
    }
    return true
    
  case .MOUSE_BUTTON_DOWN:
    // Check if clicked inside terminal
    mouse_x := f32(event.button.x)
    mouse_y := f32(event.button.y)
    
    in_bounds := mouse_x >= term.x && mouse_x <= term.x + term.width &&
                 mouse_y >= term.y && mouse_y <= term.y + term.height
    
    term.is_focused = in_bounds
    return in_bounds
  }
  
  return false
}

toggle_terminal :: proc(term: ^Rune_Terminal) {
  term.is_visible = !term.is_visible
  if term.is_visible {
    term.is_focused = true
  }
}