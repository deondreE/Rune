# Rune

<p style="align-items: center;">
  <img src="/assets/icon/icon.png" width="100" height="100">
</p>

Bringing speed back to modern editors. Rune is simple and effective at any task you throw at it.

## Threading ideas

+--------------------+ +----------------+
| SDL Main Loop | ---> | Editor State |
| (Render, Input) | <--- | + Diagnostics |
+--------------------+ | + Completions |
| | + Symbols |
| +----------------+
v
+--------------------------------------+
| LSP Thread (lsp.odin) |
| - JSON-RPC transport (stdin/stdout) |
| - Message parsing |
| - Sends data via channels |
+--------------------------------------+

## Developement

> Rune is pre-Alpha software use at your own risk.
