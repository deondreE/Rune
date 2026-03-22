package editor

import "core:mem"
import vk "vendor:vulkan"

MAX_QUADS :: 65536
MAX_VERTICES :: MAX_QUADS * 4
MAX_INDICES :: MAX_QUADS * 6

Quad :: struct {
	min:    [2]f32,
	max:    [2]f32,
	uv_min: [2]f32,
	uv_max: [2]f32,
	color:  [4]f32,
}

Draw_Command :: struct {
	index_offset:  u32,
	index_count:   u32,
	pipeline_kind: Pipeline_Kind,
}

Batch_Renderer :: struct {
	vertex_buffers:   [MAX_FRAMES_IN_FLIGHT]GPU_Buffer,
	index_buffer:     GPU_Buffer,
	vertices:         [dynamic]Text_Vertex,
	draw_commands:    [dynamic]Draw_Command,
	current_pipeline: Pipeline_Kind,
	quad_count:       u32,
	pipelines:        [Pipeline_Kind]Pipeline,
	allocator:        mem.Allocator,
}

init_batch_renderer :: proc(
	ctx: ^Render_Context,
	allocator: mem.Allocator = context.allocator,
) -> (
	br: Batch_Renderer,
	ok: bool,
) {
	br.allocator = allocator
	br.vertices = make([dynamic]Text_Vertex, 0, MAX_VERTICES, allocator)
	br.draw_commands = make([dynamic]Draw_Command, 0, 64, allocator)

	indices := make([]u32, MAX_INDICES, allocator)
	defer delete(indices, allocator)
	for i in 0 ..< MAX_QUADS {
		base := u32(i * 4)
		off := i * 6
		indices[off + 0] = base + 0
		indices[off + 1] = base + 1
		indices[off + 2] = base + 2
		indices[off + 3] = base + 2
		indices[off + 4] = base + 3
		indices[off + 5] = base + 0
	}

	index_size := vk.DeviceSize(MAX_INDICES * size_of(u32))

	staging, s_ok := create_gpu_buffer(
		ctx,
		index_size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	if !s_ok {
		return br, false
	}
	defer destroy_gpu_buffer(ctx, &staging) // fix: was `&assign`

	mem.copy(staging.mapped_ptr, raw_data(indices), int(index_size))

	br.index_buffer, ok = create_gpu_buffer(
		ctx,
		index_size,
		{.INDEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
	)
	if !ok {
		return br, false
	}

	// Copy staging → device-local index buffer
	Copy_Params :: struct {
		src:  vk.Buffer,
		dst:  vk.Buffer,
		size: vk.DeviceSize,
	}
	cp := Copy_Params {
		src  = staging.buffer,
		dst  = br.index_buffer.buffer,
		size = index_size,
	}
	execute_immediate(ctx, proc(cmd: vk.CommandBuffer, user_data: rawptr) {
			p := cast(^Copy_Params)user_data
			region := vk.BufferCopy {
				srcOffset = 0,
				dstOffset = 0,
				size      = p.size,
			}
			vk.CmdCopyBuffer(cmd, p.src, p.dst, 1, &region)
		}, &cp)

	// Per-frame host-visible vertex buffers
	vertex_buf_size := vk.DeviceSize(MAX_VERTICES * size_of(Text_Vertex))
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		br.vertex_buffers[i], ok = create_gpu_buffer(
			ctx,
			vertex_buf_size,
			{.VERTEX_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		if !ok {
			return br, false
		}
	}

	for kind in Pipeline_Kind {
		br.pipelines[kind], ok = create_pipeline(ctx, kind)
		if !ok {
			return br, false
		}
	}

	return br, true
}

destroy_batch_renderer :: proc(ctx: ^Render_Context, br: ^Batch_Renderer) {
	for kind in Pipeline_Kind {
		destroy_pipeline(ctx, &br.pipelines[kind])
	}
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		destroy_gpu_buffer(ctx, &br.vertex_buffers[i])
	}
	destroy_gpu_buffer(ctx, &br.index_buffer)
	delete(br.vertices)
	delete(br.draw_commands)
}

push_quad :: proc(br: ^Batch_Renderer, quad: Quad, kind: Pipeline_Kind) {
	if br.quad_count >= MAX_QUADS {
		return
	}

	if len(br.draw_commands) == 0 || kind != br.current_pipeline {
		append(
			&br.draw_commands,
			Draw_Command{
				index_offset = u32(len(br.draw_commands) == 0 ? 0 : br.quad_count * 6), 
				index_count = 0, 
				pipeline_kind = kind,
			},
		)
		br.current_pipeline = kind	
	}

	append(
		&br.vertices,
		Text_Vertex {
			pos = {quad.min.x, quad.min.y},
			uv = {quad.uv_min.x, quad.uv_min.y},
			color = quad.color,
		},
		Text_Vertex {
			pos = {quad.max.x, quad.min.y},
			uv = {quad.uv_max.x, quad.uv_min.y},
			color = quad.color,
		},
		Text_Vertex {
			pos = {quad.max.x, quad.max.y},
			uv = {quad.uv_max.x, quad.uv_max.y},
			color = quad.color,
		},
		Text_Vertex {
			pos = {quad.min.x, quad.max.y},
			uv = {quad.uv_min.x, quad.uv_max.y},
			color = quad.color,
		},
	)

	br.quad_count += 1
	cmd := &br.draw_commands[len(br.draw_commands) - 1]
	cmd.index_count += 6
}

// Push a solid rect no texture.
push_rect :: proc(br: ^Batch_Renderer, x, y, w, h: f32, color: [4]f32) {
	push_quad(
		br,
		Quad{min = {x, y}, max = {x + w, y + h}, uv_min = {0, 0}, uv_max = {0, 0}, color = color},
		.Solid,
	)
}

push_glyph :: proc(br: ^Batch_Renderer, x, y: f32, info: Glyph_Info, color: [4]f32) {
	push_quad(
		br,
		Quad {
			min = {x + info.bearing[0], y + info.bearing[1]},
			max = {x + info.bearing[0] + info.size[0], y + info.bearing[1] + info.size[1]},
			uv_min = info.uv_min,
			uv_max = info.uv_max,
			color = color,
		},
		.Text,
	)
}

flush_batch :: proc(
	br: ^Batch_Renderer,
	ctx: ^Render_Context,
	cmd_buf: vk.CommandBuffer,
	atlas: ^Glyph_Atlas,
) {
	if len(br.vertices) == 0 do return

	vb := &br.vertex_buffers[ctx.frame_index]
	vert_size := len(br.vertices) * size_of(Text_Vertex)
	mem.copy(vb.mapped_ptr, raw_data(br.vertices), vert_size)

	vk.CmdBindIndexBuffer(cmd_buf, br.index_buffer.buffer, 0, .UINT32)
	
	offsets := [1]vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(cmd_buf, 0, 1, &vb.buffer, &offsets[0])

	push := Push_Constants {
		screen_size = ctx.viewport_size,
	}

	for dc in br.draw_commands {
		pipe := &br.pipelines[dc.pipeline_kind]

		vk.CmdBindPipeline(cmd_buf, .GRAPHICS, pipe.pipeline)
		vk.CmdPushConstants(
			cmd_buf,
			pipe.layout,
			{.VERTEX},
			0,
			size_of(Push_Constants),
			&push,
		)

		if dc.pipeline_kind == .Text {
			ds := pipe.descriptor_sets[ctx.frame_index]
			vk.CmdBindDescriptorSets(cmd_buf, .GRAPHICS, pipe.layout, 0, 1, &ds, 0, nil)
		}

		vk.CmdDrawIndexed(cmd_buf, dc.index_count, 1, dc.index_offset, 0, 0)
	}
}

reset_branch :: proc(br: ^Batch_Renderer) {
	clear(&br.vertices)
	clear(&br.draw_commands)
	br.quad_count = 0
}
