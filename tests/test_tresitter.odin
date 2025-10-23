package tests

import "core:strings"
import "core:log"
import "core:fmt"
import "core:testing"

import "../editor/treesitter"

@(test)
test_tree_sitter_basic :: proc(t: ^testing.T) {
    c_src := "int main(){return 0;}"
    py_src := "def foo():\n    return 42"

    c_tree := treesitter.TreeSitter_Parse(c_src, treesitter.Lang.C)
    py_tree := treesitter.TreeSitter_Parse(py_src, treesitter.Lang.Python)

    if len(c_tree) == 0 || len(py_tree) == 0 {
        testing.fail(t)
    }

    fmt.println("C TREE:\n", c_tree)
    fmt.println("PY TREE:\n", py_tree)
}

@(test)
test_treesitter_api :: proc(t: ^testing.T) {
    // 1. Initialize a context for C.
    ctx := treesitter.init(treesitter.Lang.C)

    // 2. Provide sample C source.
    code_c := "int main() { return 0; }"

    // 3. Parse the code and grab the AST.
    ast_c := treesitter.parse_source(&ctx, code_c)

    fmt.println("C AST:")
    fmt.println(ast_c)
    fmt.println("-----------------------------------")

    // 4. Assert non-empty AST.
    if len(ast_c) == 0 {
        testing.fail(t)
    }

    // 5. Verify expected root node.
    if !strings.contains(ast_c, "translation_unit") {
        testing.fail(t)
    }

    // 6. Now test Python for good measure.
    ctx_py := treesitter.init(treesitter.Lang.Python)
    code_py := "def foo():\n    return 42"
    ast_py := treesitter.parse_source(&ctx_py, code_py)

    fmt.println("PYTHON AST:")
    fmt.println(ast_py)
    fmt.println("-----------------------------------")

    if len(ast_py) == 0 {
        testing.fail(t)
    }

    if !strings.contains(ast_py, "module") {
        testing.fail(t)
    }

    // 7. Call debug_print() (optional visual verification).
    fmt.println("Debug print for Python AST ->")
    treesitter.debug_print(&ctx_py)

    fmt.println("[TreeSitter API test] ✔ Successfully parsed C and Python sources.")
}