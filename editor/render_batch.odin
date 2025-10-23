package editor
import "core:container/queue"
import "core:terminal"
import "core:mem"
import "core:sort"
import sdl "vendor:sdl3"

Batch :: struct {
	texture:      ^sdl.Texture,
	vertex_start: i32,
	index_start:  i32,
	index_count:  i32,
}

Batch_Renderer :: struct {
	renderer:          ^sdl.Renderer,
	vertices:          [dynamic]sdl.Vertex,
	indices:           [dynamic]i32,
	batches:           queue.Queue(Batch),
	current_vertex_id: i32,
	current_index_id:  i32,
	allocator:         mem.Allocator,
}

init_batch_renderer :: proc(renderer: ^sdl.Renderer, allocator: mem.Allocator) -> Batch_Renderer {
	initial_vertex_capacity := 4096
	initial_index_capacity := 6144 // 1.5x vertices (6 indices per 4 vertex)
	initial_batch_capacity := 64

	backing_queue_slice := make([]Batch, initial_batch_capacity)
	batches_queue: queue.Queue(Batch)

	_ = queue.init_from_slice(&batches_queue, backing_queue_slice)

	return Batch_Renderer {
		renderer = renderer,
		vertices = make([dynamic]sdl.Vertex, initial_vertex_capacity),
		indices = make([dynamic]i32, initial_index_capacity),
		batches = batches_queue,
		current_index_id = 0,
		current_vertex_id = 0,
		allocator = allocator,
	}
}

destroy_batch_renderer :: proc(br: ^Batch_Renderer) {
	delete(br.vertices)
	delete(br.indices)
	queue.destroy(&br.batches)
}

begin_frame :: proc(br: ^Batch_Renderer) {
	queue.clear(&br.batches)
	queue.clear(&br.batches)
	br.current_vertex_id = 0
	br.current_index_id = 0
}

add_geometry_to_batch :: proc(br: ^Batch_Renderer, geo: GeometryData) {
	vertex_start_for_batch := br.current_vertex_id
	for vertex in geo.vertices {
	    append(&br.vertices, vertex)
	}
	
	index_start_for_batch := br.current_index_id
	for index in geo.indices {
	    append(&br.indices, index)
	}
	
	num_vertices := i32(len(geo.vertices))
	num_indices := i32(len(geo.indices))
	
	batch := Batch{
        texture = geo.texture,
        vertex_start = vertex_start_for_batch,
        index_start = index_start_for_batch,
        index_count = num_indices,
	}
	queue.push_back(&br.batches, batch)
	
	br.current_index_id += i32(num_indices)
	br.current_vertex_id += i32(num_vertices)
}

batch_compare :: proc(a,b: Batch) -> bool {
    return a.texture < b.texture
}

flush_batches :: proc(br: ^Batch_Renderer) {
    if br.current_index_id == 0 {
        return
    }
    
    num_batches := queue.len(br.batches)
    if num_batches == 0 {
        return
    }
    
    batches_to_process := make([]Batch, num_batches)
    for i := 0; i < num_batches; i+=1 {
        b := queue.pop_front(&br.batches)
        batches_to_process[i] = b
    }
    
    current_texture: ^sdl.Texture
    for batch in batches_to_process {
        if batch.texture != current_texture {
            sdl.SetRenderTarget(br.renderer, batch.texture)
            current_texture = batch.texture
        }
        
        max_vertex_in_batch := 0
        for i := 0; i < int(batch.index_count); i += 1 {
            global_index := int(batch.index_start) + i
            vertex_reffered_by_index := br.indices[global_index]
            if vertex_reffered_by_index > i32(max_vertex_in_batch) {
                max_vertex_in_batch = int(vertex_reffered_by_index)
            }
        }
        num_vertices_for_draw_call := (i32(max_vertex_in_batch) - batch.vertex_start) + 1
        
        sdl.RenderGeometry(
            br.renderer, 
            batch.texture,
            raw_data(br.vertices),
            i32(len(br.vertices)),
            raw_data(br.indices),
            i32(len(br.indices)),
        )
    }
    delete(batches_to_process)
    
    br.current_vertex_id = 0
    br.current_index_id = 0
    queue.clear(&br.batches)
}