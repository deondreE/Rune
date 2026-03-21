package editor

import "core:mem"
import vk "vendor:vulkan"

GPU_Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	size: vk.DeviceSize,
	mapped_ptr: rawptr,
}

GPU_Image :: struct {
	image: vk.Image,
	memory: vk.DeviceMemory,
	view: vk.ImageView,
	sampler: vk.Sampler,
	width: u32,
	height: u32,
}

create_gpu_buffer :: proc(
	ctx: ^Render_Context,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
) -> (buf: GPU_Buffer, ok: bool) {
	buf.size = size

	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}

	if vk.CreateBuffer(ctx.device, &buffer_info, nil, &buf.buffer) != .SUCCESS {
		return buf, false
	}

	mem_req: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(ctx.device, buf.buffer, &mem_req)

	type_index, found := find_memory_type(ctx, mem_req.memoryTypeBits, properties)
	if !found { return buf, false }

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_req.size,
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
) -> (img: GPU_Image, ok: bool) {
	img.width = width
	img.height = height

	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = format,
		extent = {width, height, 1},
		mipLevels = 1,
		arrayLevels = 1,
		samples = {._1},
		tiling = .OPTIMAL,
		usage = {.TRANSFER_DST, .SAMPLED},
		sharingMode = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}

	if vk.CreateImage(ctx.device, &image_info, nil, &img.image) != .SUCCESS {
		return img, false
	}

	mem_req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(ctx.device, img.image, &mem_req)

	type_index, found := find_memory_type(
		ctx, mem_req.memoryTypeBits, {.DEVICE_LOCAL},
	)
	if !found { return img, false }

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_req.size,
		memoryTypeIndex = type_index,
	}

	if vk.AllocateMemory(ctx.device, &alloc_info, nil, &img.memory) != .SUCCESS {
		return img, false
	}
	vk.BindImageMemory(ctx.device, img.image, img.memory, 0)

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_CREATE_INFO,
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
		sType = .SAMPLER_CREATE_INFO,
		magFilter = .LINEAR,
		minFilter = .LINEAR,
		addressModeU = .CLAMP_TO_EDGE,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
		maxAnisotropy = 1.0,
		borderColor = .FLOAT_OPAQUE_WHITE,
		maxLod = 1.0,
	}
	if vk.CreateSampler(ctx.device, &sampler_info, nil, &img.sampler) != .SUCCESS {
		return img, false
	}

	transition_image_layout(
		ctx, &img, .UNDEFINED, .SHADER_READ_ONLY_OPTIMAL,
	)
	
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
	execute_immediate(ctx, proc(cmd: vk.CommandBuffer) {
		// We capture via a closure like pattern;
	})
}

upload_image_data :: proc(
	ctx: ^Render_Context,
	img: ^GPU_Image,
	pixels: []u8,
	region_x, region_y, region_w, region_h: u32,
) {
	staging_size := vk.DeviceSize(region_w * region_h)
	staging, ok := create_gpu_buffer(
		ctx, staging_size, {.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	if !ok {return}
	defer destroy_gpu_buffer(ctx, &staging)

	mem.copy(staging.mapped_ptr, raw_data(pixels), int(staging_size))

	execute_immediate(ctx, proc "contextless" (cmd: vk.CommandBuffer) {
		
	})

	alloc_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = ctx.command_pool,
		level = .PRIMARY,
		commandBufferCount = 1,
	}
	cmd: vk.CommandBuffer
	vk.AllocateCommandBuffers(ctx.device, &alloc_info, &cmd)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(cmd, &begin_info)

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = .SHADER_READ_ONLY_OPTIMAL,
		newLayout = .TRANSFER_DST_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = img.image,
		suvresourceRange = {
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
		cmd, {.FRAGMENT_SHADER}, {.TRANSFER}, {},
		0, nil, 0, nil, 1, &barrier
	)

	copy_region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = region_w,
		bufferImageHeight = region_h,
		imageSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 0,
		},
		imageOffset = {i32(region_x), i32(region_y), 0},
		imageExtent = {region_w, region_h, 1},
	}
	vk.CmdCopyBufferToImage(
		cmd, staging.buffer, img.image,
		.TRANSFER_DST_OPTIMAL, 1, &copy_region,
	)

	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = {.TRANSFER_WRITE}
	barrier.dstAccessMask = {.SHADER_READ}
	vk.CmdPipelineBarrier(
		cmd, {.TRANSFER}, {.FRAGMENT_SHADER}, {},
		0, nil, 0, nil, 1, &barrier
	)

	vk.EndCommandBuffer(cmd)

	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &cmd,
	}
	vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, {})
	vk.QueueWaitIdle(ctx.graphics_queue)
	vk.FreeCommandBuffers(ctx.device, ctx.command_pool, 1, &cmd)
}

@(private = "file")
find_memory_type :: proc (
	ctx: ^Render_Context,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (u32, bool) {
	mem_props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(ctx.physical_device, &mem_props)

	for i in 0..< mem_props.memoryTypeCount {
		if (type_filter & (1 << i)) != 0 &&
			(mem_props.memoryTypes[i].propertyFlags & properties) == properties {
				return i, true
			}
	}
	return 0, false
}
