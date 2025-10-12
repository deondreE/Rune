package editor

import ini "core:encoding/ini"
import "core:fmt"
import "core:os"

Editor_Settings :: struct {}

load_settings_file :: proc(editor: ^Editor) {
	root_path := "config/settings.ini"
	fmt.println("Loading the settings config")

	// Ensure the "config" directory exists before trying to load the file
	dir_path := "config"
	if !os.exists(dir_path) {
		err := os.make_directory(dir_path)
		if err != nil {
			fmt.printf("Failed to create directory '%v': %v\n", dir_path, err)
			return
		}
	}

	if !os.exists(root_path) {
		file, err := os.open(root_path, os.O_CREATE | os.O_RDWR)
		if err != nil {
			fmt.printf("Failed to create '%v': %v\n", root_path, err)
			return
		}

		init_data :=
			"[editor]\n" +
			"theme = default\n" +
			"font_size = 14\n" +
			"" +
			"[window]\n" +
			"width = 1280\n" +
			"height = 720\n" +
			"\n"
		init_map, e := ini.load_map_from_string(init_data, editor.allocator)
		stream := os.stream_from_handle(file)
		if e != nil {fmt.printf("Error: %v", e)}

		_, write_err := ini.write_map(stream, init_map)
		if write_err != nil {
			fmt.printf("Failed to write init data: %v\n", write_err)
			os.close(file)
			return
		}

		os.close(file)

	}
	// Try loading the file now
	ini_map, err, ok := ini.load_map_from_path(root_path, editor.allocator)
	if err != nil {
		fmt.printf("There was an error loading settings: %v\n", err)
		return
	}

	if ok {
		fmt.printf("%v", ini_map)
		ini_map_string := ini.save_map_to_string(ini_map, editor.allocator)
		defer delete(ini_map_string)

		load_text_into_editor(editor, ini_map_string)
		return
	} else {
		fmt.printf("INI map did not load properly.\n")
	}
}
