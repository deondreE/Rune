package lsp

import "core:fmt"
// import "core:os"
import os "core:os/os2"
import "core:encoding/json"
import "core:sync"
import "core:thread"
import "core:time"

Position :: struct {line, character: int }
Range :: struct { start, end: Position }

Vertex :: struct {
  id: int,
  type: string,
  label: string,
  name: string, 
  uri: string,
  range: Range,
}

Edge :: struct {
  id: int,
  type: string,
  label: string,
  outV: int,
  inVs: []int,
}

emit_vertex :: proc(v: Vertex) {
  json_data, _ := json.marshal(v)
  // os.write_string(os.stdout, string(json_data))
}

emit_edge :: proc(e: Edge) {
  json_data, _ := json.marshal(e)
  // os.write_string(os.stdout, string(json_data))
}

MAX_THREADS :: 2
LSP_Thread :: struct {
  running: bool,
  threads: [MAX_THREADS]^thread.Thread,
  mutex: sync.Mutex,
}

init_lsp_thread :: proc(exe_path: string, allocator := context.allocator) -> ^LSP_Thread {
    // fmt.printf("(stub) starting LSP: %s\n", exe_path)
    lsp := new(LSP_Thread, allocator)
    lsp.running = true
    
    t_id := 1
    lsp.threads[0] = thread.create_and_start_with_poly_data2(lsp, lsp.mutex, background_loop)

    return lsp
}

background_loop :: proc (ctx: ^LSP_Thread, mutex: sync.Mutex) {
  counter := 0

  // 1. find the lsp from the active list of lsps.
  // 2. spawn the process. 
  // 3. respond to the lsp process.


  for ctx.running {
    time.sleep(1 * time.Second)
    sync.mutex_lock(&ctx.mutex)
    // fmt.printf("[LSP Thread]: Tick %v — Generating LSIF vertex/edge\n", counter)
  
    v := Vertex{
      id = counter,
      type = "vertex",
      label = "range",
      name = fmt.aprintf("symbol_%v", counter),
      uri = "file:///example.odin",
      range = Range{
          start = Position{line = counter, character = 1},
          end   = Position{line = counter, character = 10},
      },
    }    
    e := Edge{
      id = counter * 10,
      type = "edge",
      label = "contains",
      outV = 1,
      inVs = []int{v.id},
    }    
      

    p: os.Process; {
      r, w, _ := os.pipe()  
      defer os.close(w)

      p, _ = os.process_start({ 
        command = {"echo", "Hello World"},
        stdout = w,
      }) 
    }  

    _, _ = os.process_wait(p)
      
    emit_vertex(v)
    emit_edge(e)

    sync.unlock(&ctx.mutex)
  }
}

poll_message :: proc(lsp: ^LSP_Thread) -> (string, bool) {
    return "", false
}

send_json :: proc(lsp: ^LSP_Thread, method: string, params: any) {
    fmt.printf("(stub) would send LSP message: %s\n", method)
}

shutdown_lsp :: proc(lsp: ^LSP_Thread) {
  lsp.running = false
  fmt.println("Signaled LSP thread to stop.")

  for t in lsp.threads {
    thread.destroy(t)
  }

  fmt.println("All LSP threads stopped successfully.")
}