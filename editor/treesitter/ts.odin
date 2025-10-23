package treesitter

import "core:strings"
import "core:c"
import "core:mem"
import "core:fmt"

when ODIN_OS == .Windows {
    foreign import tsgateway {
        "libs/tsgateway.dll.lib",
    }
} else when ODIN_OS == .Linux {
    foreign import tsgateway {
        "libs/linux/libtsgateway.a",
    }
} else when ODIN_OS == .Darwin {
    foreign import tsgateway {
        "libs/macos/libtsgateway.a",
    }
}

TSResult :: struct {
    tree_ptr: rawptr,
    root_sexpr: cstring,
}

@(default_calling_convention="c")
foreign tsgateway {
    ts_parse :: proc(source: cstring, lang_id: i32) -> TSResult ---
    ts_free_result :: proc(result: TSResult) ---
}

Treesitter :: struct {
    lang:        Lang,
    last_source: string,
    ast_string:  string,
}

Lang :: enum i32 {
    Rust = 0,
    C = 1,
    Python = 2,
    Odin = 3,
}

// Detemines the lang from the filname suffix.
get_lang_from_filename :: proc(filename: string) -> Lang {
    lower := strings.to_lower(filename)
    if strings.has_suffix(lower, ".odin") {  return Lang.Odin }
    if strings.has_suffix(lower, ".rs") {     return Lang.Rust }
    if strings.has_suffix(lower, ".c") ||
        strings.has_suffix(lower, ".h")  { return Lang.C }
    if strings.has_suffix(lower, ".py")  { return Lang.Python }
    return Lang.Odin
}

// Sets language context.
init :: proc(lang: Lang = Lang.Odin) -> Treesitter {
    return Treesitter{lang = lang}
}

// Parses a source string.
parse_source :: proc(ctx: ^Treesitter, source: string, allocator: mem.Allocator = context.allocator) -> string {
    if len(ctx.ast_string) > 0 {
        delete(ctx.ast_string, allocator)
        ctx.ast_string = ""
    }
    
    c_src := strings.clone_to_cstring(source, allocator) 
    defer delete(c_src, allocator)
    
    result := ts_parse(c_src, i32(ctx.lang))
    defer ts_free_result(result)
    
    if result.root_sexpr == nil {
        ctx.ast_string = "(null)"
        return ctx.ast_string
    }
    
    ctx.ast_string = strings.clone_from_cstring(result.root_sexpr, allocator)
    defer delete(ctx.ast_string, allocator)
    
    return ctx.ast_string
}

// Prints the treesitter ast.
debug_print :: proc(ctx: ^Treesitter) {
    fmt.println("Tree-sitter AST:")
    fmt.println(ctx.ast_string)
}

TreeSitter_Parse :: proc(source: string, lang: Lang) -> string {
    c_src := strings.clone_to_cstring(source, context.temp_allocator)
    defer delete(c_src, context.temp_allocator)
    res := ts_parse(c_src, i32(lang))
    defer ts_free_result(res)
    sexpr := "(null)"
    if res.root_sexpr != nil {
        sexpr = strings.clone_from_cstring(res.root_sexpr, context.temp_allocator)
        defer delete(sexpr, context.temp_allocator)
    }
    ts_free_result(res)
    return sexpr
}