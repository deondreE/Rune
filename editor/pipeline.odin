package editor

import "core:os"
import vk "vendor:vulkan"

Pipeline_Kind :: enum u8 {
	Text,
	Solid,
}

Pipeline :: struct {
	pipeline:        vk.Pipeline,
	layout:          vk.PipelineLayout,
	descriptor_pool: vk.DescriptorPool,
	descriptor_sets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	set_layout:      vk.DescriptorSetLayout,
}

Push_Constants :: struct {
	screen_size: [2]f32,
}

Text_Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	color: [4]f32,
}

create_pipeline :: proc(ctx: ^Render_Context, kind: Pipeline_Kind) -> (pipe: Pipeline, ok: bool) {
	// Load shaders
	vert_path, frag_path: string
	switch kind {
	case .Text:
		vert_path = "shaders/text.vert.spv"
		frag_path = "shaders/text.frag.spv"
	case .Solid:
		vert_path = "shaders/solid.vert.spv"
		frag_path = "shaders/solid.frag.spv"
	}

	vert_code, vert_ok := os.read_entire_file_from_path(vert_path, ctx.allocator)
	if vert_ok != nil {return pipe, false}
	defer delete(vert_code, ctx.allocator)

	frag_code, frag_ok := os.read_entire_file_from_path(frag_path, ctx.allocator)
	if frag_ok != nil {return pipe, false}
	defer delete(frag_code, ctx.allocator)

	vert_module, v_ok := create_shader_module(ctx, vert_code)
	if !v_ok {return pipe, false}
	defer vk.DestroyShaderModule(ctx.device, vert_module, nil)

	frag_module, f_ok := create_shader_module(ctx, frag_code)
	if !f_ok {return pipe, false}
	defer vk.DestroyShaderModule(ctx.device, frag_module, nil)

	shader_stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert_module,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag_module,
			pName = "main",
		},
	}

	binding := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = size_of(Text_Vertex),
		inputRate = .VERTEX,
	}

	attributes := [3]vk.VertexInputAttributeDescription {
		{
			location = 0,
			binding = 0,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(Text_Vertex, pos)),
		},
		{
			location = 1,
			binding = 0,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(Text_Vertex, uv)),
		},
		{
			location = 2,
			binding = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(Text_Vertex, color)),
		},
	}

	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding,
		vertexAttributeDescriptionCount = len(attributes),
		pVertexAttributeDescriptions    = &attributes[0],
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(ctx.swapchain_extent.width),
		height   = f32(ctx.swapchain_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = ctx.swapchain_extent,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		pViewports    = &viewport,
		scissorCount  = 1,
		pScissors     = &scissor,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		lineWidth   = 1,
		cullMode    = {.BACK},
		frontFace   = .CLOCKWISE,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}

	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}

	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = len(dynamic_states),
		pDynamicStates    = &dynamic_states[0],
	}

	// descriptor sets
	if kind == .Text {
		sampler_binding := vk.DescriptorSetLayoutBinding {
			binding         = 0,
			descriptorType  = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags      = {.FRAGMENT},
		}

		set_layout_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = 1,
			pBindings    = &sampler_binding,
		}

		if vk.CreateDescriptorSetLayout(ctx.device, &set_layout_info, nil, &pipe.set_layout) !=
		   .SUCCESS {
			return pipe, false
		}

		pool_size := vk.DescriptorPoolSize {
			type            = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = MAX_FRAMES_IN_FLIGHT,
		}
		pool_info := vk.DescriptorPoolCreateInfo {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			maxSets       = MAX_FRAMES_IN_FLIGHT,
			poolSizeCount = 1,
			pPoolSizes    = &pool_size,
		}
		if vk.CreateDescriptorPool(ctx.device, &pool_info, nil, &pipe.descriptor_pool) !=
		   .SUCCESS {
			return pipe, false
		}

		// Allocate descriptor sets
		layouts: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			layouts[i] = pipe.set_layout
		}
		ds_alloc := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = pipe.descriptor_pool,
			descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
			pSetLayouts        = &layouts[0],
		}
		vk.AllocateDescriptorSets(ctx.device, &ds_alloc, &pipe.descriptor_sets[0])
	}

	// push constants
	push_range := vk.PushConstantRange {
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = size_of(Push_Constants),
	}

	set_layout_count: u32 = 0
	p_set_layouts: ^vk.DescriptorSetLayout = nil
	if kind == .Text {
		set_layout_count = 1
		p_set_layouts = &pipe.set_layout
	}

	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = set_layout_count,
		pSetLayouts            = p_set_layouts,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_range,
	}

	if vk.CreatePipelineLayout(ctx.device, &layout_info, nil, &pipe.layout) != .SUCCESS {
		return pipe, false
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = &shader_stages[0],
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,
		pDynamicState       = &dynamic_state,
		layout              = pipe.layout,
		renderPass          = ctx.render_pass,
		subpass             = 0,
	}

	if vk.CreateGraphicsPipelines(ctx.device, {}, 1, &pipeline_info, nil, &pipe.pipeline) !=
	   .SUCCESS {
		return pipe, false
	}

	return pipe, true
}

update_descriptor_set :: proc(ctx: ^Render_Context, pipe: ^Pipeline, atlas_image: ^GPU_Image) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		image_info := vk.DescriptorImageInfo {
			sampler     = atlas_image.sampler,
			imageView   = atlas_image.view,
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		}

		write := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = pipe.descriptor_sets[i],
			dstBinding      = 0,
			descriptorCount = 1,
			descriptorType  = .COMBINED_IMAGE_SAMPLER,
			pImageInfo      = &image_info,
		}

		vk.UpdateDescriptorSets(ctx.device, 1, &write, 0, nil)
	}
}

destroy_pipeline :: proc(ctx: ^Render_Context, pipe: ^Pipeline) {
	vk.DestroyPipeline(ctx.device, pipe.pipeline, nil)
	vk.DestroyPipelineLayout(ctx.device, pipe.layout, nil)
	if pipe.set_layout != {} {
		vk.DestroyDescriptorSetLayout(ctx.device, pipe.set_layout, nil)
	}
	if pipe.descriptor_pool != {} {
		vk.DestroyDescriptorPool(ctx.device, pipe.descriptor_pool, nil)
	}
}

@(private = "file")
create_shader_module :: proc(
	ctx: ^Render_Context,
	code: []u8,
) -> (
	module: vk.ShaderModule,
	ok: bool,
) {
	info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)raw_data(code),
	}
	return module, vk.CreateShaderModule(ctx.device, &info, nil, &module) == .SUCCESS
}
