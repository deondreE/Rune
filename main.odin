package main

import "core:fmt"
import "core:mem"
import editor "editor"
import "vendor:glfw"
import vk "vendor:vulkan"

Editor_State :: struct {
	render_ctx:     editor.Render_Context,
	font:           editor.Font_Handle,
	atlas:          editor.Glyph_Atlas,
	batch:          editor.Batch_Renderer,
	buffer:         editor.Gap_Buffer,
	compositor:     editor.Compositer,
	layer_ctx:      editor.Layer_Context,
	cursor_data:    ^editor.Cursor_Layer_Data,
	selection_data: ^editor.Selection_Layer_Data,
	cursor_pos:     int,
	preferred_col:  int, // sticky visual column for up/down movement
}

init_editor :: proc(
	state: ^Editor_State,
	window: glfw.WindowHandle,
	font_path: string,
	font_size: f32,
	allocator: mem.Allocator = context.allocator,
) -> bool {
	ok: bool
	state.render_ctx, ok = editor.init_vulkan(window, allocator)
	if !ok {
		fmt.eprintln("Failed to init Vulkan")
		return false
	}

	state.font, ok = editor.load_font(font_path, font_size, allocator)
	if !ok {
		fmt.eprintln("Failed to load font:", font_path)
		return false
	}

	state.atlas, ok = editor.init_glyph_atlas(&state.render_ctx, allocator)
	if !ok {
		fmt.eprintln("Failed to init glyph atlas")
		return false
	}
	editor.precache_ascii(&state.atlas, &state.font)
	editor.flush_atlas(&state.render_ctx, &state.atlas)

	state.batch, ok = editor.init_batch_renderer(&state.render_ctx, allocator)
	if !ok {
		fmt.eprintln("Failed to init renderer")
		return false
	}

	editor.update_descriptor_set(
		&state.render_ctx,
		&state.batch.pipelines[.Text],
		&state.atlas.image,
	)

	state.buffer = editor.init_gap_buffer(allocator)

	w, h := glfw.GetFramebufferSize(window)
	state.layer_ctx = editor.Layer_Context {
		viewport = {f32(w), f32(h)},
		font     = &state.font,
		tab_size = 4,
	}

	state.compositor = editor.init_compositor(allocator)
	c := &state.compositor

	line_height := state.font.ascent - state.font.descent + state.font.line_gap
	char_width := editor.get_glyph(&state.atlas, &state.font, 'M').advance_x

	gutter_w: f32 = 56
	text_padding := [2]f32{gutter_w + 8, 8}

	editor.add_layer(c, editor.make_background_layer({0.12, 0.12, 0.14, 1.0}, allocator))

	sel := editor.add_layer(
		c,
		editor.make_selection_layer(
			line_height,
			char_width,
			text_padding,
			{0.20, 0.40, 0.80, 0.35},
			allocator,
		),
	)
	state.selection_data = cast(^editor.Selection_Layer_Data)sel.user_data

	editor.add_layer(
		c,
		editor.make_text_layer(
			&state.buffer,
			&state.font,
			{0.92, 0.91, 0.88, 1.0},
			line_height,
			text_padding,
			allocator,
		),
	)

	cur := editor.add_layer(
		c,
		editor.make_cursor_layer(
			line_height,
			char_width,
			text_padding,
			{0.90, 0.85, 0.70, 1.0},
			2,
			allocator,
		),
	)
	state.cursor_data = cast(^editor.Cursor_Layer_Data)cur.user_data

	editor.add_layer(
		c,
		editor.make_line_number_layer(
			&state.buffer,
			&state.font,
			gutter_w,
			line_height,
			8,
			{0.45, 0.45, 0.50, 1.0},
			{0.10, 0.10, 0.12, 1.0},
			allocator,
		),
	)

	return true
}

destroy_editor :: proc(state: ^Editor_State) {
	vk.DeviceWaitIdle(state.render_ctx.device)
	editor.destroy_compositor(&state.compositor)
	editor.destroy_gap_buffer(&state.buffer)
	editor.destroy_batch_renderer(&state.render_ctx, &state.batch)
	//editor.destroy_glyph_atlas(&state.render_ctx, &state.atlas)
	editor.destroy_font(&state.font)
	editor.destroy_vulkan(&state.render_ctx)
}

draw_frame :: proc(state: ^Editor_State) -> bool {
	ctx := &state.render_ctx
	fi := ctx.frame_index

	vk.WaitForFences(ctx.device, 1, &ctx.in_flight_fences[fi], true, max(u64))

	image_index: u32
	result := vk.AcquireNextImageKHR(
		ctx.device,
		ctx.swapchain,
		max(u64),
		ctx.image_available[fi],
		{},
		&image_index,
	)
	if result == .ERROR_OUT_OF_DATE_KHR {return false}

	vk.ResetFences(ctx.device, 1, &ctx.in_flight_fences[fi])

	cmd := ctx.command_buffers[image_index]
	vk.ResetCommandBuffer(cmd, {})

	vk.BeginCommandBuffer(cmd, &vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO})

	clear_val := vk.ClearValue {
		color = {float32 = {0, 0, 0, 1}},
	}
	vk.CmdBeginRenderPass(
		cmd,
		&vk.RenderPassBeginInfo {
			sType = .RENDER_PASS_BEGIN_INFO,
			renderPass = ctx.render_pass,
			framebuffer = ctx.framebuffers[image_index],
			renderArea = {{0, 0}, ctx.swapchain_extent},
			clearValueCount = 1,
			pClearValues = &clear_val,
		},
		.INLINE,
	)

	vk.CmdSetViewport(
		cmd,
		0,
		1,
		&vk.Viewport {
			width = f32(ctx.swapchain_extent.width),
			height = f32(ctx.swapchain_extent.height),
			minDepth = 0,
			maxDepth = 1,
		},
	)
	vk.CmdSetScissor(cmd, 0, 1, &vk.Rect2D{extent = ctx.swapchain_extent})

	editor.flush_atlas(ctx, &state.atlas)
	editor.composite(&state.compositor, &state.batch, &state.atlas, &state.layer_ctx)
	editor.flush_batch(&state.batch, ctx, cmd, &state.atlas)
	editor.reset_batch(&state.batch)

	vk.CmdEndRenderPass(cmd)
	vk.EndCommandBuffer(cmd)

	wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	vk.QueueSubmit(
		ctx.graphics_queue,
		1,
		&vk.SubmitInfo {
			sType = .SUBMIT_INFO,
			waitSemaphoreCount = 1,
			pWaitSemaphores = &ctx.image_available[fi],
			pWaitDstStageMask = &wait_stage,
			commandBufferCount = 1,
			pCommandBuffers = &cmd,
			signalSemaphoreCount = 1,
			pSignalSemaphores = &ctx.render_finished[fi],
		},
		ctx.in_flight_fences[fi],
	)

	vk.QueuePresentKHR(
		ctx.present_queue,
		&vk.PresentInfoKHR {
			sType = .PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores = &ctx.render_finished[fi],
			swapchainCount = 1,
			pSwapchains = &ctx.swapchain,
			pImageIndices = &image_index,
		},
	)

	ctx.frame_index = (fi + 1) % u32(len(ctx.in_flight_fences))
	return true
}

main :: proc() {
	if !glfw.Init() {
		fmt.eprintln("Failed to init GLFW")
		return
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window := glfw.CreateWindow(1280, 800, "Editor", nil, nil)
	if window == nil {
		fmt.eprintln("Failed to create window")
		return
	}
	defer glfw.DestroyWindow(window)

	state: Editor_State
	if !init_editor(&state, window, "assets/fonts/ComicMono.ttf", 16) {return}
	defer destroy_editor(&state)

	// Seed some initial content and place the cursor at the end of it.
	hello := "Hello, Editor!\nType something here.\n"
	editor.insert_bytes(&state.buffer, transmute([]u8)string(hello))
	state.cursor_pos = editor.current_length(&state.buffer)
	sync_cursor(&state)

	// Register input callbacks; the state pointer is retrieved inside each callback.
	glfw.SetWindowUserPointer(window, &state)
	glfw.SetCharCallback(window, char_callback)
	glfw.SetKeyCallback(window, key_callback)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		if !draw_frame(&state) {
			w, h := glfw.GetFramebufferSize(window)
			editor.recreate_swapchain(&state.render_ctx, u32(w), u32(h))
			state.layer_ctx.viewport = {f32(w), f32(h)}
			editor.notify_resize(&state.compositor, state.layer_ctx.viewport)
		}
	}

	vk.DeviceWaitIdle(state.render_ctx.device)
}
