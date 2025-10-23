use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use tree_sitter::{Language, Parser, Tree};

use tree_sitter_rust;
use tree_sitter_c;
use tree_sitter_python;

#[repr(C)]
pub struct TSResult {
    tree_ptr: *mut Tree,
    root_sexpr: *mut c_char,
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

    let sexpr = CString::new(tree.root_node().to_sexp()).unwrap();

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