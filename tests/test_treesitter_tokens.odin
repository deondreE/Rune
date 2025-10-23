#+feature dynamic-literals
package tests

import "core:fmt"
import "core:mem"
import "core:testing"
import "../editor/treesitter"

@(test)
test_get_tokens_for_source :: proc(t: ^testing.T) {
    allocator := context.allocator

    // Simple sources to parse per language
    sources := map[treesitter.Lang]string{
        treesitter.Lang.C      = "int main() { return 0; }",
        treesitter.Lang.Python = "def foo():\n    return 42",
        treesitter.Lang.Rust   = "fn add(a: i32, b: i32) -> i32 { a + b }",
    }

    for lang, src in sources {
        fmt.printf("\n[Tree‑sitter Token Test] Parsing %v code...\n", lang)

        tokens, count := treesitter.get_tokens_for_source(src, lang, allocator)
        fmt.printf("Received %d tokens for %v\n", count, lang)

        if count <= 0 {
            fmt.printf("No tokens returned for %v code\n", lang)
            testing.fail(t)
            continue
        }

        // Show first few tokens for debugging
        show_n := min(count, 10)
        for i in 0..<show_n {
            tok := tokens[i]
            fmt.printf("#%02d: start=%d end=%d kind=%d\n",
                i, tok.start, tok.end, tok.kind)
        }

        // --- Basic validation ---------------------------------------------
        src_len := cast(u32) len(src)
        bad_count := 0
        for i in 0..<len(tokens) {
            tok := tokens[i]
            if tok.start > tok.end {
                fmt.printf("Invalid token range in %v: start=%d end=%d\n",
                    lang, tok.start, tok.end)
                bad_count += 1
            } else if tok.end > src_len {
                // end == src_len is OK; > len(src) is invalid
                fmt.printf("Token out of bounds in %v: start=%d end=%d (len=%d)\n",
                    lang, tok.start, tok.end, src_len)
                bad_count += 1
            }
        }

        if bad_count > 0 {
            fmt.printf("%d invalid tokens detected for %v\n", bad_count, lang)
            testing.fail(t)
        } else {
            fmt.printf("[✓] Token extraction succeeded for %v — %d valid tokens.\n",
                lang, count)
        }

        // Free all tokens once for this language
        if count > 0 {
            treesitter.ts_free_tokens(&tokens[0], len(tokens))
        }
    }
}