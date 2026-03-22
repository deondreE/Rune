package editor

import "core:mem"
import vk "vendor:vulkan"

GPU_Buffer :: struct {
	buffer:     vk.Buffer,
	memory:     vk.DeviceMemory,
	size:       vk.DeviceSize,
	mapped_ptr: rawptr,
}

GPU_Image :: struct {
	image:   vk.Image,
	memory:  vk.DeviceMemory,
	view:    vk.ImageView,
	sampler: vk.Sampler,
	width:   u32,
	height:  u32,
}

create_gpu_buffer :: proc(
	ctx: ^Render_Context,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
) -> (
	buf: GPU_Buffer,
	ok: bool,
) {
	buf.size = size

	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	if vk.CreateBuffer(ctx.device, &buffer_info, nil, &buf.buffer) != .SUCCESS {
		return buf, false
	}

	mem_req: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(ctx.device, buf.buffer, &mem_req)

	type_index, found := find_memory_type(ctx, mem_req.memoryTypeBits, properties)
	if !found {return buf, false}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_req.size,
		memoryTypeIndex = type_index,
	}

	if vk.AllocateMemory(ctx.device, &alloc_info, nil, &buf.memory) != .SUCCESS {
		return buf, false
	}

	vk.BindBufferMemory(ctx.device, buf.buffer, buf.memory, 0)

	if .HOST_VISIBLE in properties {
		vk.MapMemory(ctx.device, buf.memory, 0, size, {}, &buf.mapped_ptr)
	}

	return buf, true
}

destroy_gpu_buffer :: proc(ctx: ^Render_Context, buf: ^GPU_Buffer) {
	if buf.mapped_ptr != nil {
		vk.UnmapMemory(ctx.device, buf.memory)
	}
	vk.DestroyBuffer(ctx.device, buf.buffer, nil)
	vk.FreeMemory(ctx.device, buf.memory, nil)
}

create_gpu_image :: proc(
	ctx: ^Render_Context,
	width, height: u32,
	format: vk.Format,
) -> (
	img: GPU_Image,
	ok: bool,
) {
	img.width = width
	img.height = height

	image_info := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = format,
		extent        = {width, height, 1},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = {._1},
		tiling        = .OPTIMAL,
		usage         = {.TRANSFER_DST, .SAMPLED},
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}

	if vk.CreateImage(ctx.device, &image_info, nil, &img.image) != .SUCCESS {
		return img, false
	}

	mem_req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(ctx.device, img.image, &mem_req)

	type_index, found := find_memory_type(ctx, mem_req.memoryTypeBits, {.DEVICE_LOCAL})
	if !found {return img, false}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_req.size,
		memoryTypeIndex = type_index,
	}

	if vk.AllocateMemory(ctx.device, &alloc_info, nil, &img.memory) != .SUCCESS {
		return img, false
	}
	vk.BindImageMemory(ctx.device, img.image, img.memory, 0)

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = img.image,
		viewType = .D2,
		format = format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}
	if vk.CreateImageView(ctx.device, &view_info, nil, &img.view) != .SUCCESS {
		return img, false
	}

	sampler_info := vk.SamplerCreateInfo {
		sType         = .SAMPLER_CREATE_INFO,
		magFilter     = .LINEAR,
		minFilter     = .LINEAR,
		addressModeU  = .CLAMP_TO_EDGE,
		addressModeV  = .CLAMP_TO_EDGE,
		addressModeW  = .CLAMP_TO_EDGE,
		maxAnisotropy = 1.0,
		borderColor   = .FLOAT_OPAQUE_WHITE,
		maxLod        = 1.0,
	}
	if vk.CreateSampler(ctx.device, &sampler_info, nil, &img.sampler) != .SUCCESS {
		return img, false
	}

	transition_image_layout(ctx, &img, .UNDEFINED, .SHADER_READ_ONLY_OPTIMAL)

	return img, true
}

destroy_gpu_image :: proc(ctx: ^Render_Context, img: ^GPU_Image) {
	vk.DestroySampler(ctx.device, img.sampler, nil)
	vk.DestroyImageView(ctx.device, img.view, nil)
	vk.DestroyImage(ctx.device, img.image, nil)
	vk.FreeMemory(ctx.device, img.memory, nil)
}

transition_image_layout :: proc(
	ctx: ^Render_Context,
	img: ^GPU_Image,
	old_layout, new_layout: vk.ImageLayout,
) {
	src_access: vk.AccessFlags
	dst_access: vk.AccessFlags
	src_stage: vk.PipelineStageFlags
	dst_stage: vk.PipelineStageFlags

	if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		src_access = {}
		dst_access = {.TRANSFER_WRITE}
		src_stage = {.TOP_OF_PIPE}
		dst_stage = {.TRANSFER}
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		src_access = {.TRANSFER_WRITE}
		dst_access = {.SHADER_READ}
		src_stage = {.TRANSFER}
		dst_stage = {.FRAGMENT_SHADER}
	} else if old_layout == .UNDEFINED && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		src_access = {}
		dst_access = {.SHADER_READ}
		src_stage = {.TOP_OF_PIPE}
		dst_stage = {.FRAGMENT_SHADER}
	} else {
		// Generic fallback
		src_access = {.MEMORY_READ, .MEMORY_WRITE}
		dst_access = {.MEMORY_READ, .MEMORY_WRITE}
		src_stage = {.ALL_COMMANDS}
		dst_stage = {.ALL_COMMANDS}
	}

	execute_immediate(ctx, proc(cmd: vk.CommandBuffer, user_data: rawptr) {
			params := cast(^Transition_Params)user_data
			barrier := vk.ImageMemoryBarrier {
				sType = .IMAGE_MEMORY_BARRIER,
				oldLayout = params.old_layout,
				newLayout = params.new_layout,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = params.image,
				subresourceRange = {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				srcAccessMask = params.src_access,
				dstAccessMask = params.dst_access,
			}
			vk.CmdPipelineBarrier(
				cmd,
				params.src_stage,
				params.dst_stage,
				{},
				0,
				nil,
				0,
				nil,
				1,
				&barrier,
			)
		}, &Transition_Params {
			image = img.image,
			old_layout = old_layout,
			new_layout = new_layout,
			src_access = src_access,
			dst_access = dst_access,
			src_stage = src_stage,
			dst_stage = dst_stage,
		})
}

@(private = "file")
Transition_Params :: struct {
	image:      vk.Image,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	src_access: vk.AccessFlags,
	dst_access: vk.AccessFlags,
	src_stage:  vk.PipelineStageFlags,
	dst_stage:  vk.PipelineStageFlags,
}

upload_image_data :: proc(
	ctx: ^Render_Context,
	img: ^GPU_Image,
	pixels: []u8,
	region_x, region_y, region_w, region_h: u32,
) {
	staging_size := vk.DeviceSize(region_w * region_h)
	staging, ok := create_gpu_buffer(
		ctx,
		staging_size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	if !ok {
		return
	}
	defer destroy_gpu_buffer(ctx, &staging)

	mem.copy(staging.mapped_ptr, raw_data(pixels), int(staging_size))

	Upload_Params :: struct {
		staging:  vk.Buffer,
		image:    vk.Image,
		region_x: u32,
		region_y: u32,
		region_w: u32,
		region_h: u32,
	}

	params := Upload_Params {
		staging  = staging.buffer,
		image    = img.image,
		region_x = region_x,
		region_y = region_y,
		region_w = region_w,
		region_h = region_h,
	}

	execute_immediate(
		ctx,
		proc(cmd: vk.CommandBuffer, user_data: rawptr) {
			p := cast(^Upload_Params)user_data

			// Transition to transfer dst
			to_transfer := vk.ImageMemoryBarrier {
				sType = .IMAGE_MEMORY_BARRIER,
				oldLayout = .SHADER_READ_ONLY_OPTIMAL,
				newLayout = .TRANSFER_DST_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = p.image,
				subresourceRange = {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				srcAccessMask = {.SHADER_READ},
				dstAccessMask = {.TRANSFER_WRITE},
			}
			vk.CmdPipelineBarrier(
				cmd,
				{.FRAGMENT_SHADER},
				{.TRANSFER},
				{},
				0,
				nil,
				0,
				nil,
				1,
				&to_transfer,
			)

			copy_region := vk.BufferImageCopy {
				bufferOffset = 0,
				bufferRowLength = p.region_w,
				bufferImageHeight = p.region_h,
				imageSubresource = {
					aspectMask     = {.COLOR},
					mipLevel       = 0,
					baseArrayLayer = 0,
					layerCount     = 1, // fix: was 0
				},
				imageOffset = {i32(p.region_x), i32(p.region_y), 0},
				imageExtent = {p.region_w, p.region_h, 1},
			}
			vk.CmdCopyBufferToImage(
				cmd,
				p.staging,
				p.image,
				.TRANSFER_DST_OPTIMAL,
				1,
				&copy_region,
			)

			// Transition back to shader read
			to_shader := vk.ImageMemoryBarrier {
				sType = .IMAGE_MEMORY_BARRIER,
				oldLayout = .TRANSFER_DST_OPTIMAL,
				newLayout = .SHADER_READ_ONLY_OPTIMAL,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				image = p.image,
				subresourceRange = {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				srcAccessMask = {.TRANSFER_WRITE},
				dstAccessMask = {.SHADER_READ},
			}
			vk.CmdPipelineBarrier(
				cmd,
				{.TRANSFER},
				{.FRAGMENT_SHADER},
				{},
				0,
				nil,
				0,
				nil,
				1,
				&to_shader,
			)
		},
		&params,
	)
}

@(private = "file")
find_memory_type :: proc(
	ctx: ^Render_Context,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	u32,
	bool,
) {
	mem_props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(ctx.physical_device, &mem_props)

	for i in 0 ..< mem_props.memoryTypeCount {
		if (type_filter & (1 << i)) != 0 &&
		   (mem_props.memoryTypes[i].propertyFlags & properties) == properties {
			return i, true
		}
	}
	return 0, false
}
