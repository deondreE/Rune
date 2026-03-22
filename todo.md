# TODO

Rewrite all rendering to vulkan based text rendering....

Rewrite the rendering backend to be platform agnostic...

-- Restructure the project, more of a sublime based editor, rather then a vscode competitor.

Problems:

Layer system

0 Background - Solid window background
1 Selections - higlighted selection ranges
2 Cursors - cursor line / caret rect
3 Text - actual glyph quads
4 Decorations - underlines, error_squiggles,
5 Overlay - (line_numbers, scrollbars)

  - Tabs ->  
    - Tabs
    - Debugger
    - Terminal
    - AI integration
    - Extensions
    - Gap buffer re-evaluation

### Rendering

Vulkan -- Theoredically write specific font rendering for each platform, not required.
Ttf is gunna be fun

### File Explorer

One Window like helix.

### Debugger

lldb-debug protocol implementation

### Lsp

Lsp protocol implementation

### Markdown rendering

Custom Solution

### Syntax Highlighting

Treesitter for parsing of langs,
Theme files for specific specifiers.
Default themes

### Builtin Terminal

The builtin terminal is usally garbage, so we won't build one in. 
