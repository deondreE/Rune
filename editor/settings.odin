package editor

import "core:encoding/json"
import ini "core:encoding/ini"
import "core:fmt"
import "core:os"
import "core:path/filepath"

Editor_Settings :: struct {
    theme: string,
    font_size: f32,
    font: string,
}

load_settings_file :: proc(editor: ^Editor) {
	dir_path := DEFAULT_CONFIG_PATH
    root_path := filepath.join({dir_path, "settings.json"}, editor.allocator)
    defer delete(root_path, editor.allocator)
	
	if !os.exists(dir_path) {
		err := os.make_directory(dir_path)
		if err != nil {
			fmt.printf("Failed to create directory '%v': %v\n", dir_path, err)
			return
		}
	}

	if !os.exists(root_path) {
		
	    default_settings := Editor_Settings {
			theme = "dark",
			font_size = editor.text_renderer.font_size,
			font = "Maple Mono",
		}
		
		json_bytes, err := json.marshal(default_settings, json.Marshal_Options{pretty = true}, editor.allocator)
		if err != nil {
		    fmt.eprintln("Failed to marshel default settings: %v", err)
			return
		} 
		defer delete(json_bytes, editor.allocator)
		
		ok_write := os.write_entire_file(root_path, transmute([]byte)json_bytes)
		if !ok_write {
		    fmt.eprint("SETTINGS: Failed to write file.")
			return
		}
	}
	
	data, ok := os.read_entire_file_from_filename(root_path, editor.allocator)
	if !ok {
	    fmt.eprintln("Failed to read settings")
		return 
	}
	defer delete(data, editor.allocator)

	parser := json.make_parser_from_string(string(data))
	root_val, valid := json.parse(data)
	defer json.destroy_value(root_val)
	
	if valid != nil {
	    fmt.eprintln("settings.json is not valid JSON.")
	}
	
	settings:Editor_Settings
	decode_ok := json.unmarshal_string(string(data), &settings)
	if decode_ok != nil {
	    fmt.eprintln("failed to unmarshel data.")
		return 
	}
	
	load_text_into_editor(editor, string(data))
}
