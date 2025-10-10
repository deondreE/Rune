package lsp

// resource: https://microsoft.github.io/language-server-protocol/

import "core:os"
import "core:mem"
import "core:json"
import "core:sync"
import "core:strings"
import "core:fmt"
import "core:thread"

LSP_Message :: struct {
  id: string,
  method: string,
  params: json.Value,
  result: json.Value,
  erorr: json.Value,
}

LSP_Thread :: struct {
  server_process: ^os.Process,
  send_chan: ^sync.Chan(string),
  recv_chan: ^sync.Chan(string),
  running: bool,
  allocator: mem.Allocator,
}

// Launch lsp server.
init_lsp_thread :: os.exec_process(
   executable_path: string,
   allocator: mem.Allocator = context.allocator,
 ) -> LSP_Thread {
  lsp: LSP_Thread
  lsp.allocator = allocator,
  lsp.send_chan = sync.make_chan(string, 128, allocator)
  lsp.recv_chan = sync.make_chan(string, 128, allocator)

  process, err := os.exec_process(executable_path, os.ExecOptions{
    start_suspended = false,
    redirect_stdin = true,
    redirect_stdout = true,
    redirect_stderr = true,
  })
  if err != nil {
    fmt.printf("Failed to start LSP server: %v\n", err)
  }
  lsp.server_process = process
  lsp.running = true 

  // Background io
  go lsp_read_loop(&lsp)
  go lsp_write_loop(&lsp) 

  return lsp  
}

lsp_read_loop :: proc(lsp: ^LSP_Thread) {
  stdout := lsp.server_process.stdout
  buffer: [4096]u8
  for lsp.running {
    n, err := os.read(stdout, buffer[:])
    if err != nil || n <= 0 {
      return 
    }

    chunk := string(buffer[:n])
    // LSP's come prefixed...
    // e.g. "Content-Length: 123\r\n\r\n{...JSON...}"
    idx := strings.index(chunk, "\r\n\r\n")
    if idx != -1 {
      json_part := chunk[idx+4:]
      sync.send(lsp.recv_chan, json_part)
    }
  }
  fmt.println("LSP read loop terminated")
}

lsp_write_loop :: proc(lsp: ^LSP_Thread) {
  stdin := lsp.server_process.stdin
  for msg in lsp.send_chan {
    content_len := fmt.aprintf("Content-Length: %d\r\n\r\n", len(msg))
    full := fmt.aprintf("%s%s", content_len, msg)
    defer delete(content_len, lsp.allocator)
    defer delete(full, lsp.allocator)
    _, _ = os.write(stdin, transmute([]u8)full)
  }
  fmt.println("LSP write loop terminated.")
}

send_request :: proc(lsp: ^LSP_Thread, method: string, params: json.Value) {
  id_str := fmt.aprintf("%d", os.get_pid())
  payload := json.Object{
    "jsonrpc": "2.0",
    "id":    id_str,
    "method": method,
    "params": params,
  }

  json_str, _ := json.marshal(payload)
  sync.send(lsp.send_chan, string(json_str))
}

shutdown_lsp :: proc (lsp: ^LSP_Thread) {
  lsp.running = false
  sync.close_chan(lsp.send_chan)
  sync.close_chan(lsp_recv_chan)
  os.kill_process(lsp.server_process)
  fmt.println("LSP thread shut down.")
}