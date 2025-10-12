package editor

import "core:os"
import "core:fmt"
import "core:path/filepath"

return_file_contents :: proc(filename: string) -> string {
    data: string = ""

    abs_path, ok := filepath.abs(filename, context.temp_allocator)
    if !ok {
        fmt.printf("Failed to resolve absolute path for '%s'\n", filename)
        return data
    }

    contents, err := os.read_entire_file(abs_path)
    delete(abs_path)
    if err {
        fmt.printf("Failed to read file '%s' (error: %v)\n", filename, err)
        return data
    }

    data = string(contents)
    delete(contents)
    return data
}