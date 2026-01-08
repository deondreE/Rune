use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::{
    fs,
    io::Write,
};
use tree_sitter::{Language, Parser, Tree};
use streaming_iterator::StreamingIterator;

use tree_sitter_c;
use tree_sitter_python;
use tree_sitter_rust;

const RUST_HIGHLIGHT_QUERY: &str = r#"
; Functions
(function_item name: (identifier) @function)
(function_signature_item name: (identifier) @function)
(call_expression function: (identifier) @function.call)
(call_expression function: (field_expression field: (field_identifier) @function.call))

; Types and Structs
(type_identifier) @type
(struct_item name: (type_identifier) @type)
(enum_item name: (type_identifier) @type)
(trait_item name: (type_identifier) @trait)
(impl_item type: (type_identifier) @type)
(primitive_type) @type.builtin

; Keywords and Modifiers
[
 "fn" "let" "mut" "struct" "enum" "impl" "trait" "use" "as" "pub"
 "crate" "mod" "return" "if" "else" "match" "while" "for" "loop"
 "in" "break" "continue" "const" "static" "async" "await" "move"
 "ref" "type" "where" "unsafe" "extern" "dyn"
] @keyword

; Literals
(string_literal) @string
(raw_string_literal) @string
(char_literal) @character
(integer_literal) @number
(float_literal) @number
(boolean_literal) @boolean

; Comments
(line_comment) @comment
(block_comment) @comment

; Operators
["=" "==" "!=" "<" "<=" ">" ">=" "+" "-" "*" "/" "%" "&&" "||" "!" "&" "|" "^" "<<" ">>"] @operator

; Punctuation
["(" ")" "{" "}" "[" "]" ";" "," "." "::" ":" "->"] @punctuation

; Macros
(macro_invocation macro: (identifier) @macro)

; Variables
(identifier) @variable
"#;

const ODIN_HIGHLIGHT_QUERY: &str = r#"
; Procedures
(procedure_declaration name: (identifier) @function)
(call_expression function: (identifier) @function.call)

; Types
(type_identifier) @type
(struct_declaration name: (identifier) @type)
(enum_declaration name: (identifier) @type)
(union_declaration name: (identifier) @type)

; Built-in types
[
 "int" "i8" "i16" "i32" "i64" "i128"
 "uint" "u8" "u16" "u32" "u64" "u128"
 "f32" "f64" "bool" "string" "rune"
 "rawptr" "any" "typeid"
] @type.builtin

; Constants
(constant_declaration name: (identifier) @constant)

; Keywords
[
 "proc" "struct" "enum" "union" "import" "package" "foreign"
 "if" "else" "return" "when" "for" "in" "while"
 "break" "continue" "case" "switch" "defer" "using"
 "cast" "transmute" "auto_cast" "distinct" "bit_set"
 "map" "dynamic" "or_else" "or_return"
] @keyword

; Literals
(string_literal) @string
(rune_literal) @character
(integer_literal) @number
(float_literal) @number
(boolean_literal) @boolean

; Comments
(comment) @comment
(block_comment) @comment

; Operators
["=" "==" "!=" "<" "<=" ">" ">=" "+" "-" "*" "/" "%" "&&" "||" "!" "&" "|" "^" "<<" ">>"] @operator

; Punctuation
["(" ")" "{" "}" "[" "]" ";" "," "." "::" ":" "->"] @punctuation

; Directives
(directive) @keyword.directive

; Variables and fields
(identifier) @variable
(field_identifier) @field
"#;

const PYTHON_HIGHLIGHT_QUERY: &str = r#"
; Functions and Classes
(function_definition name: (identifier) @function)
(call function: (identifier) @function.call)
(call function: (attribute attribute: (identifier) @function.call))
(class_definition name: (identifier) @type)

; Decorators
(decorator "@" @punctuation (identifier) @function.decorator)

; Keywords
[
 "def" "class" "if" "elif" "else" "while" "for" "in"
 "import" "from" "return" "yield" "async" "await"
 "try" "except" "finally" "as" "assert" "with"
 "lambda" "global" "nonlocal" "del" "pass" "continue"
 "break" "raise" "and" "or" "not" "is"
] @keyword

; Built-in constants
[
 "True" "False" "None"
] @constant.builtin

; Literals
(string) @string
(integer) @number
(float) @number

; Comments
(comment) @comment

; Operators
["=" "==" "!=" "<" "<=" ">" ">=" "+" "-" "*" "/" "//" "%" "**" "&" "|" "^" "~" "<<" ">>"] @operator

; Punctuation
["(" ")" "{" "}" "[" "]" ";" "," "." ":" "->"] @punctuation

; Variables
(identifier) @variable
(attribute attribute: (identifier) @field)

; Parameters
(parameters (identifier) @parameter)
"#;

const C_HIGHLIGHT_QUERY: &str = r#"
; Functions
(function_definition declarator: (function_declarator declarator: (identifier) @function))
(call_expression function: (identifier) @function.call)
(call_expression function: (field_expression field: (field_identifier) @function.call))

; Types
(type_identifier) @type
(struct_specifier name: (type_identifier) @type)
(enum_specifier name: (type_identifier) @type)
(union_specifier name: (type_identifier) @type)

; Primitive types
(primitive_type) @type.builtin

; Keywords
[
 "if" "else" "for" "while" "do" "switch" "case" "default"
 "break" "continue" "return" "goto"
 "typedef" "struct" "enum" "union"
 "const" "volatile" "static" "extern" "auto" "register"
 "sizeof" "void" "inline" "restrict"
] @keyword

; Preprocessor
(preproc_directive) @keyword.directive
(preproc_def) @keyword.directive
(preproc_include) @keyword.directive

; Literals
(string_literal) @string
(char_literal) @character
(number_literal) @number

; Comments
(comment) @comment

; Operators
["=" "==" "!=" "<" "<=" ">" ">=" "+" "-" "*" "/" "%" "&&" "||" "!" "&" "|" "^" "<<" ">>"] @operator

; Punctuation
["(" ")" "{" "}" "[" "]" ";" "," "." "->" ":"] @punctuation

; Variables
(identifier) @variable
(field_identifier) @field
"#;

#[repr(C)]
pub struct TSResult {
    tree_ptr: *mut Tree,
    root_sexpr: *mut c_char,
}

#[repr(C)]
pub struct Token {
    pub start: u32,
    pub end: u32,
    pub kind_id: u16,
    pub _pad: u16,
}

pub const TOKEN_FUNCTION: u16 = 1;
pub const TOKEN_FUNCTION_CALL: u16 = 2;
pub const TOKEN_TYPE: u16 = 3;
pub const TOKEN_TYPE_BUILTIN: u16 = 4;
pub const TOKEN_KEYWORD: u16 = 5;
pub const TOKEN_STRING: u16 = 6;
pub const TOKEN_CHARACTER: u16 = 7;
pub const TOKEN_NUMBER: u16 = 8;
pub const TOKEN_BOOLEAN: u16 = 9;
pub const TOKEN_COMMENT: u16 = 10;
pub const TOKEN_OPERATOR: u16 = 11;
pub const TOKEN_PUNCTUATION: u16 = 12;
pub const TOKEN_VARIABLE: u16 = 13;
pub const TOKEN_CONSTANT: u16 = 14;
pub const TOKEN_FIELD: u16 = 15;
pub const TOKEN_PARAMETER: u16 = 16;
pub const TOKEN_MACRO: u16 = 17;
pub const TOKEN_TRAIT: u16 = 18;
pub const TOKEN_DIRECTIVE: u16 = 19;
pub const TOKEN_DECORATOR: u16 = 20;

fn map_capture_to_kind(capture_name: &str) -> u16 {
    match capture_name {
        "function" => TOKEN_FUNCTION,
        "function.call" => TOKEN_FUNCTION_CALL,
        "function.decorator" => TOKEN_DECORATOR,
        "type" => TOKEN_TYPE,
        "type.builtin" => TOKEN_TYPE_BUILTIN,
        "trait" => TOKEN_TRAIT,
        "keyword" => TOKEN_KEYWORD,
        "keyword.directive" => TOKEN_DIRECTIVE,
        "string" => TOKEN_STRING,
        "character" => TOKEN_CHARACTER,
        "number" => TOKEN_NUMBER,
        "boolean" => TOKEN_BOOLEAN,
        "constant" => TOKEN_CONSTANT,
        "constant.builtin" => TOKEN_CONSTANT,
        "comment" => TOKEN_COMMENT,
        "operator" => TOKEN_OPERATOR,
        "punctuation" => TOKEN_PUNCTUATION,
        "variable" => TOKEN_VARIABLE,
        "parameter" => TOKEN_PARAMETER,
        "field" => TOKEN_FIELD,
        "macro" => TOKEN_MACRO,
        _ => hash_kind(capture_name),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ts_get_tokens(
    source: *const c_char,
    lang_id: c_int,
    out_tokens: *mut *mut Token,
) -> usize {
    if source.is_null() || out_tokens.is_null() {
        return 0;
    }
    let c_src = unsafe { CStr::from_ptr(source) };
    let Ok(code) = c_src.to_str() else { return 0 };

    let mut parser = Parser::new();
    let lang = match lang_id {
        0 => tree_sitter_rust::LANGUAGE.into(),
        1 => tree_sitter_c::LANGUAGE.into(),
        2 => tree_sitter_python::LANGUAGE.into(),
        3 => tree_sitter_odin::LANGUAGE.into(),
        _ => return 0,
    };

    if parser.set_language(&lang).is_err() {
        return 0;
    }
    let Some(tree) = parser.parse(code, None) else {
        return 0;
    };
    let root = tree.root_node();
    let src_len = code.len() as u32;

    // Walk the tree and collect leaf nodes    // let mut cursor = root.walk()
    let mut tokens: Vec<Token> = Vec::with_capacity(256);
    let mut stack = Vec::with_capacity(256);
    stack.push(root);

    while let Some(node) = stack.pop() {
        if node.child_count() == 0 {
            let mut start = node.start_byte() as u32;
            let mut end = node.end_byte() as u32;
            // Clamp values into valid range
            if start > src_len {
                start = src_len;
            }
            if end > src_len {
                end = src_len;
            }
            if end < start {
                std::mem::swap(&mut start, &mut end);
            }

            tokens.push(Token {
                start,
                end,
                kind_id: hash_kind(node.kind()) as u16,
                _pad: 0,
            });
        } else {
            for i in 0..node.child_count() {
                if let Some(child) = node.child(i) {
                    stack.push(child);
                }
            }
        }
    }

    let len = tokens.len();
    let boxed: Box<[Token]> = tokens.into_boxed_slice();
    let ptr = boxed.as_ptr() as *mut Token;
    std::mem::forget(boxed);
    unsafe {
        *out_tokens = ptr;
    }
    len
}

#[unsafe(no_mangle)]
pub extern "C" fn ts_get_highlight_tokens(
    source: *const c_char,
    lang_id: c_int,
    out_tokens: *mut *mut Token,
) -> usize {
    use tree_sitter::{Parser};
    if source.is_null() || out_tokens.is_null() {
        return 0;
    }

    let c_src = unsafe{ CStr::from_ptr(source) };
    let Ok(code) = c_src.to_str() else { return 0 };

    let mut parser = Parser::new();
    let lang = match get_language(lang_id) {
        Some(l) => l,
        _ => return 0,
    };
    parser.set_language(&lang).ok();

    let Some(tree) = parser.parse(code, None) else { return 0 };

    let query_source = match lang_id {
        0 => RUST_HIGHLIGHT_QUERY,
        1 => C_HIGHLIGHT_QUERY,
        2 => PYTHON_HIGHLIGHT_QUERY,
        3 => ODIN_HIGHLIGHT_QUERY,
        _ => return 0,
    };

    let query = match tree_sitter::Query::new(&lang.into(), query_source) {
        Ok(q) => q,
        Err(_) => return 0,
    };

    let mut cursor = tree_sitter::QueryCursor::new();
    let root = tree.root_node();
    let _bytes = code.as_bytes();
    let mut matches = cursor.matches(&query, root, _bytes);
    let mut tokens: Vec<Token> = Vec::with_capacity(256);

    loop {
        matches.advance();
        let m = matches.get();
        if m.is_none() {
            break;
        }
        let m = m.unwrap();

        for cap in m.captures {
            let node = cap.node;
            let name = query.capture_names()[cap.index as usize];
            tokens.push(Token{
                start: node.start_byte() as u32,
                end: node.end_byte() as u32,
                kind_id: hash_kind(name) as u16,
                _pad: 0,
            });
        }
    }

    let len = tokens.len();
    let boxed = tokens.into_boxed_slice();
    let ptr = boxed.as_ptr() as *mut Token;
    std::mem::forget(boxed);
    unsafe { *out_tokens = ptr; }
    len
}

#[unsafe(no_mangle)]
pub extern "C" fn ts_free_tokens(ptr: *mut Token, len: usize) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(std::slice::from_raw_parts_mut(ptr, len))) }
    }
}

fn hash_kind(kind: &str) -> u16 {
    let mut h: u32 = 2166136261;
    for &b in kind.as_bytes() {
        h = (h ^ b as u32).wrapping_mul(16777619);
    }
    (h & 0xFFFF) as u16
}

fn get_language(lang_id: c_int) -> Option<Language> {
    Some(match lang_id {
        0 => tree_sitter_rust::LANGUAGE.into(),
        1 => tree_sitter_c::LANGUAGE.into(),
        2 => tree_sitter_python::LANGUAGE.into(),
        3 => tree_sitter_odin::LANGUAGE.into(),
        _ => return None,
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn ts_parse(source: *const c_char, lang_id: c_int) -> TSResult {
    let c_str = unsafe { CStr::from_ptr(source) };
    let code = c_str.to_str().unwrap_or("");

    let mut parser = Parser::new();

    let language = match get_language(lang_id) {
        Some(lang) => lang,
        None => {
            eprintln!("Unsupported language id {}", lang_id);
            return TSResult {
                tree_ptr: std::ptr::null_mut(),
                root_sexpr: CString::new("(unsupported)").unwrap().into_raw(),
            };
        }
    };

    if let Err(err) = parser.set_language(&language) {
        eprintln!("Failed to set language: {:?}", err);
        return TSResult {
            tree_ptr: std::ptr::null_mut(),
            root_sexpr: CString::new("(language error)").unwrap().into_raw(),
        };
    }

    let tree = match parser.parse(code, None) {
        Some(t) => t,
        None => {
            return TSResult {
                tree_ptr: std::ptr::null_mut(),
                root_sexpr: CString::new("(parse failed)").unwrap().into_raw(),
            };
        }
    };

    let sepxr_str = tree.root_node().to_sexp();

    let _ = fs::create_dir_all("out");
    let path = format!("out/parse_lang{}_tree.ast", lang_id);
    match fs::File::create(&path) {
        Ok(mut file) => {
            if let Err(e) = file.write_all(sepxr_str.as_bytes()) {
                eprintln!("Error writing AST file {}: {}", path, e);
            } else {
                eprintln!("AST written")
            }
        }
        Err(e) => eprintln!("Could not create AST file {}: {}", path, e)
    }

    let sexpr = CString::new(sepxr_str).unwrap();
    TSResult {
        tree_ptr: Box::into_raw(Box::new(tree)),
        root_sexpr: sexpr.into_raw(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ts_free_result(result: TSResult) {
    unsafe {
        if !result.tree_ptr.is_null() {
            drop(Box::from_raw(result.tree_ptr));
        }
        if !result.root_sexpr.is_null() {
            drop(CString::from_raw(result.root_sexpr));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tree_sitter::Parser;

    #[test]
    fn parse_rust_code() {
        let code = "fn double(x:i32)->i32{x*2}";
        let mut parser = Parser::new();
        let lang = get_language(0).expect("Rust language not loaded");
        parser.set_language(&lang).unwrap();

        let tree = parser.parse(code, None).unwrap();
        let root = tree.root_node();
        assert_eq!(root.kind(), "source_file");
        assert!(!root.has_error(), "Rust parse tree contains errors");
    }

    #[test]
    fn parse_c_code() {
        let code = "int main(){return 0;}";
        let mut parser = Parser::new();
        let lang = get_language(1).expect("C language not loaded");
        parser.set_language(&lang).unwrap();

        let tree = parser.parse(code, None).unwrap();
        let root = tree.root_node();
        assert_eq!(root.kind(), "translation_unit");
        assert!(!root.has_error(), "C parse tree contains errors");
    }

    #[test]
    fn parse_python_code() {
        let code = "def foo():\n    return 42";
        let mut parser = Parser::new();
        let lang = get_language(2).expect("Python language not loaded");
        parser.set_language(&lang).unwrap();

        let tree = parser.parse(code, None).unwrap();
        let root = tree.root_node();
        assert_eq!(root.kind(), "module");
        assert!(!root.has_error(), "Python parse tree contains errors");
    }

    #[test]
    fn invalid_language_id_returns_none() {
        assert!(get_language(999).is_none());
    }
}
