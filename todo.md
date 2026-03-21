# TODO

Rewrite all rendering to vulkan based text rendering....

Rewrite the rendering backend to be platform agnostic...

-- Restructure the project, more of a sublime based editor, rather then a vscode competitor.

Problems:

  - Tabs ->  
  - UI -> XML -> HTML
    - Not everything needs to draw every frame
    - Save performance for text rendering.
      - HTML -> Panel structure plus label structure.
      - Json -> Styles for each panel.
      - `ui/panel/file_explorer.html` -> `ui/panel/file_explorer.json`    
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
