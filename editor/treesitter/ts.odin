package treesitter

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"

// TODO: Add Debug flag
// TODO: Write the parser for dyn ast, threaded. ;--(

when ODIN_OS == .Windows {
	foreign import tsgateway "libs/tsgateway.dll.lib"
} else when ODIN_OS == .Linux {
	foreign import tsgateway "libs/linux/libtsgateway.a"
} else when ODIN_OS == .Darwin {
	foreign import tsgateway "libs/macos/libtsgateway.a"
}

TSResult :: struct {
	tree_ptr:   rawptr,
	root_sexpr: cstring,
}

Token :: struct {
	start: u32,
	end:   u32,
	kind:  u16,
	_pad:  u16,
}

TOKEN_FUNCTION :: 1
TOKEN_FUNCTION_CALL :: 2
TOKEN_TYPE :: 3
TOKEN_TYPE_BUILTIN :: 4
TOKEN_KEYWORD :: 5
TOKEN_STRING :: 6
TOKEN_CHARACTER :: 7
TOKEN_NUMBER :: 8
TOKEN_BOOLEAN :: 9
TOKEN_COMMENT :: 10
TOKEN_OPERATOR :: 11
TOKEN_PUNCTUATION :: 12
TOKEN_VARIABLE :: 13
TOKEN_CONSTANT :: 14
TOKEN_FIELD :: 15
TOKEN_PARAMETER :: 16
TOKEN_MACRO :: 17
TOKEN_TRAIT :: 18
TOKEN_DIRECTIVE :: 19
TOKEN_DECORATOR :: 20

@(default_calling_convention = "c")
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
	Rust   = 0,
	C      = 1,
	Python = 2,
	Odin   = 3,
}

// Return tokens slice and count; caller must later call ts_free_tokens.
get_tokens_for_source :: proc(
	source: string,
	lang: Lang,
	allocator: mem.Allocator,
) -> (
	[]Token,
	int,
) {
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

// Get highlight tokens with proper semantic information.
get_hightlight_tokens :: proc(
	source: string,
	lang: Lang,
	allocator: mem.Allocator,
) -> (
	[]Token,
	int,
) {
	c_src := strings.clone_to_cstring(source, allocator)
	defer delete(c_src, allocator)

	toks_ptr: [^]Token = nil
	count := ts_get_highlight_tokens(c_src, i32(lang), &toks_ptr)
	if count <= 0 || toks_ptr == nil {
		return {}, 0
	}
	tokens := toks_ptr[:count]
	return tokens, count
}

// Convenience scoped wrapper that automatically frees tokens.
use_tokens :: proc(
	source: string,
	lang: Lang,
	allocator: mem.Allocator,
	body: proc(tokens: []Token),
) {
	tokens, count := get_tokens_for_source(source, lang, allocator)
	if count == 0 {return}
	defer ts_free_tokens(&tokens[0], count)
	body(tokens)
}

// Convenience scoped wrapper for highlight tokens 
use_highlight_tokens :: proc (
	source: string,
	lang: Lang,
	allocator := context.allocator,
	body: proc(tokens: []Token),
) {
	tokens, count := get_hightlight_tokens(source, lang, allocator)
	if count == 0 {return}
	defer ts_free_tokens(&tokens[0], count)
	body(tokens)
}

// Detemines the lang from the filpath.
get_lang_from_filepath :: proc(path: string) -> Lang {
	lower_path := strings.to_lower(path)

	sep_index := max(
		strings.last_index_byte(lower_path, '/'),
		strings.last_index_byte(lower_path, '\\'),
	)
	name_part := lower_path
	if sep_index != -1 {
		name_part = lower_path[sep_index + 1:]
	}

	if strings.has_suffix(name_part, ".odin") {return Lang.Odin}
	if strings.has_suffix(name_part, ".rs") {return Lang.Rust}
	if strings.has_suffix(name_part, ".c") || strings.has_suffix(name_part, ".h") {return Lang.C}
	if strings.has_suffix(name_part, ".py") {return Lang.Python}

	return Lang.Odin
}

// Helper to get token kind name for debugging
get_token_kind_name :: proc(kind: u16) -> string {
	switch kind {
	case TOKEN_FUNCTION: return "function"
	case TOKEN_FUNCTION_CALL: return "function.call"
	case TOKEN_TYPE: return "type"
	case TOKEN_TYPE_BUILTIN: return "type.builtin"
	case TOKEN_KEYWORD: return "keyword"
	case TOKEN_STRING: return "string"
	case TOKEN_CHARACTER: return "character"
	case TOKEN_NUMBER: return "number"
	case TOKEN_BOOLEAN: return "boolean"
	case TOKEN_COMMENT: return "comment"
	case TOKEN_OPERATOR: return "operator"
	case TOKEN_PUNCTUATION: return "punctuation"
	case TOKEN_VARIABLE: return "variable"
	case TOKEN_CONSTANT: return "constant"
	case TOKEN_FIELD: return "field"
	case TOKEN_PARAMETER: return "parameter"
	case TOKEN_MACRO: return "macro"
	case TOKEN_TRAIT: return "trait"
	case TOKEN_DIRECTIVE: return "directive"
	case TOKEN_DECORATOR: return "decorator"
	case: return "unknown"
	}
}

// Sets language context.
init :: proc(lang: Lang = Lang.Odin) -> Treesitter {
	return Treesitter{lang = lang}
}

// Parses a source string.
parse_source :: proc(
	ctx: ^Treesitter,
	source: string,
	allocator: mem.Allocator = context.allocator,
) -> string {
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

// Debug print tokens with their kinds
debug_print_tokens :: proc(tokens: []Token, source: string) {
	fmt.println("Tokens:")
	for token in tokens {
		if int(token.end) <= len(source) && int(token.start) <= len(source) {
			text := source[token.start:token.end]
			kind_name := get_token_kind_name(token.kind)
			fmt.printf("  [%d-%d] %s: '%s'\n", token.start, token.end, kind_name, text)
		}
	}
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
