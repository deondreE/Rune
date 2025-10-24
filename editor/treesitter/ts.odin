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

Token :: struct {
    start: u32,
    end: u32,
    kind: u16,
    _pad: u16,
}

@(default_calling_convention="c")
foreign tsgateway {
    ts_parse :: proc(source: cstring, lang_id: i32) -> TSResult ---
    ts_free_result :: proc(result: TSResult) ---
    ts_get_tokens :: proc(source: cstring, lang: i32, out_tokens: ^[^]Token) -> int ---
    ts_get_highlight_tokens :: proc(source: cstring, lang_id: i32, out_tokens: ^[^]Token) -> int ---
    ts_free_tokens :: proc(tokens: ^Token, len: int) ---
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

// Return tokens slice and count; caller must later call ts_free_tokens.
get_tokens_for_source :: proc(
    source: string,
    lang: Lang,
    allocator: mem.Allocator,
) -> ([]Token, int) {
    c_src := strings.clone_to_cstring(source, allocator)
    defer delete(c_src, allocator)

    toks_ptr: [^]Token = nil
    len := ts_get_tokens(c_src, i32(lang), &toks_ptr)
    if len <= 0 || toks_ptr == nil {
        return {}, 0
    }

    tokens := toks_ptr[:len]
    return tokens, len
}

get_hightlight_tokens :: proc(
    source: string,
    lang: Lang,
    allocator: mem.Allocator,
) -> ([]Token, int) {
    c_src := strings.clone_to_cstring(source, allocator)
    defer delete(c_src, allocator)
    
    toks_ptr: [^]Token = nil
    count := ts_get_highlight_tokens(c_src, i32(lang), &toks_ptr)
    if count <= 0 || toks_ptr == nil {
        return {}, 0
    }
    tokens := toks_ptr[:count]
    return tokens,count
}

// Convenience scoped wrapper that automatically frees tokens.
use_tokens :: proc(
    source: string,
    lang: Lang,
    allocator: mem.Allocator,
    body: proc(tokens: []Token),
) {
    tokens, count := get_tokens_for_source(source, lang, allocator)
    if count == 0 { return }
    defer ts_free_tokens(&tokens[0], count)
    body(tokens)
}

// Detemines the lang from the filpath.
get_lang_from_filepath :: proc(path: string) -> Lang {
    lower_path := strings.to_lower(path)
        
    sep_index := max(strings.last_index_byte(lower_path, '/'),
                         strings.last_index_byte(lower_path, '\\'))
    name_part := lower_path
    if sep_index != -1 {
        name_part = lower_path[sep_index + 1:]
    }
    
    if strings.has_suffix(name_part, ".odin")    { return Lang.Odin }
    if strings.has_suffix(name_part, ".rs")      { return Lang.Rust }
    if strings.has_suffix(name_part, ".c") ||
        strings.has_suffix(name_part, ".h")       { return Lang.C }
    if strings.has_suffix(name_part, ".py")      { return Lang.Python }
    
    return Lang.Odin
}

// Sets language context.
init :: proc(lang: Lang = Lang.Odin) -> Treesitter {
    return Treesitter{lang = lang}
}

// Parses a source string.
parse_source :: proc(ctx: ^Treesitter, source: string,
                     allocator: mem.Allocator = context.allocator) -> string {
    if len(ctx.ast_string) > 0 && ctx.ast_string != "(null)" {
        delete(ctx.ast_string, context.allocator)
        ctx.ast_string = ""
    }
    ctx.ast_string = ""

    c_src := strings.clone_to_cstring(source, allocator)
    defer delete(c_src, allocator)

    result := ts_parse(c_src, i32(ctx.lang))
    defer ts_free_result(result)

    if result.root_sexpr == nil {
        ctx.ast_string = "(null)"
        return ctx.ast_string
    }

    ctx.ast_string = strings.clone_from_cstring(result.root_sexpr, allocator)
    // defer delete(ctx.ast_string, allocator)
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