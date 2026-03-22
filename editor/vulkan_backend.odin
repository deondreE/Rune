package editor

import "core:fmt"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 2

Render_Context :: struct {
	instance:         vk.Instance,
	physical_device:  vk.PhysicalDevice,
	device:           vk.Device,
	surface:          vk.SurfaceKHR,
	graphics_queue:   vk.Queue,
	present_queue:    vk.Queue,
	graphics_family:  u32,
	present_family:   u32,

	// Swapchain
	swapchain:        vk.SwapchainKHR,
	swapchain_images: []vk.Image,
	swapchain_views:  []vk.ImageView,
	swapchain_format: vk.SurfaceFormatKHR,
	swapchain_extent: vk.Extent2D,

	// Render pass
	render_pass:      vk.RenderPass,
	framebuffers:     []vk.Framebuffer,

	// Command pools and buffers
	command_pool:     vk.CommandPool,
	command_buffers:  [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,

	// Sync
	image_available:  [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished:  [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight_fences: [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	frame_index:      u32,
	viewport_size:    [2]f32,
	allocator:        mem.Allocator,
}

Immediate_Fn :: #type proc(cmd: vk.CommandBuffer, userdata: rawptr)

vk_check :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCCESS {
		fmt.panicf("Vulkan error: %v at %v", result, loc)
	}
}

init_vulkan :: proc(
	window: glfw.WindowHandle,
	allocator: mem.Allocator = context.allocator,
) -> (
	ctx: Render_Context,
	ok: bool,
) {
	ctx.allocator = allocator

	// 1. Global Load
	get_proc := glfw.GetInstanceProcAddress(nil, "vkGetInstanceProcAddr")
	if get_proc == nil {
		fmt.eprintln("Failed to find vkGetInstanceProcAddr")
		return ctx, false
	}
	vk.load_proc_addresses_global(rawptr(get_proc))

	glfw_extensions := glfw.GetRequiredInstanceExtensions()

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Editor",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "Custom",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_2,
	}

	layers := [?]cstring{"VK_LAYER_KHRONOS_validation"}
	instance_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = cast(u32)len(glfw_extensions),
		ppEnabledExtensionNames = raw_data(glfw_extensions),
		enabledLayerCount       = len(layers),
		ppEnabledLayerNames     = &layers[0],
	}

	if vk.CreateInstance(&instance_info, nil, &ctx.instance) != .SUCCESS {
		fmt.eprintln("Failed to create Vulkan instance")
		return ctx, false
	}

	// 2. Instance Load (Crucial: This loads Surface and Physical Device procs)
	vk.load_proc_addresses_instance(ctx.instance)

	if glfw.CreateWindowSurface(ctx.instance, window, nil, &ctx.surface) != .SUCCESS {
		fmt.eprintln("Failed to create window surface")
		return ctx, false
	}

	if !pick_physical_device(&ctx) {
		fmt.eprintln("Failed to find suitable GPU")
		return ctx, false
	}

	if !create_logical_device(&ctx) {
		fmt.eprintln("Failed to create logical device")
		return ctx, false
	}

	vk.load_proc_addresses_device(ctx.device)

	w, h := glfw.GetFramebufferSize(window)
	if w == 0 || h == 0 {
		fmt.eprintln("Window size is 0, cannot initialize swapchain")
		return ctx, false
	}
	ctx.viewport_size = {f32(w), f32(h)}

	if !create_swapchain(&ctx, u32(w), u32(h)) {
		fmt.eprintln("Failed to create swapchain")
		return ctx, false
	}

	if !create_render_pass(&ctx) {
		fmt.eprintln("Failed to create render pass")
		return ctx, false
	}

	if !create_framebuffers(&ctx) {
		fmt.eprintln("Failed to create framebuffers")
		return ctx, false
	}

	if !create_command_resources(&ctx) {
		fmt.eprintln("Failed to create command resources")
		return ctx, false
	}

	if !create_sync_objects(&ctx) {
		fmt.eprintln("Failed to create sync objects")
		return ctx, false
	}

	return ctx, true
}

destroy_vulkan :: proc(ctx: ^Render_Context) {
	vk.DeviceWaitIdle(ctx.device)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(ctx.device, ctx.image_available[i], nil)
		vk.DestroySemaphore(ctx.device, ctx.render_finished[i], nil)
		vk.DestroyFence(ctx.device, ctx.in_flight_fences[i], nil)
	}

	vk.DestroyCommandPool(ctx.device, ctx.command_pool, nil)

	for fb in ctx.framebuffers {
		vk.DestroyFramebuffer(ctx.device, fb, nil)
	}
	delete(ctx.framebuffers, ctx.allocator)

	vk.DestroyRenderPass(ctx.device, ctx.render_pass, nil)

	for view in ctx.swapchain_views {
		vk.DestroyImageView(ctx.device, view, nil)
	}
	delete(ctx.swapchain_views, ctx.allocator)
	delete(ctx.swapchain_images, ctx.allocator)

	vk.DestroySwapchainKHR(ctx.device, ctx.swapchain, nil)
	vk.DestroyDevice(ctx.device, nil)
	vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
	vk.DestroyInstance(ctx.instance, nil)
}

pick_physical_device :: proc(ctx: ^Render_Context) -> bool {
	count: u32
	vk.EnumeratePhysicalDevices(ctx.instance, &count, nil)
	assert(count > 0, "No Vulkan-capable GPU found")

	devices := make([]vk.PhysicalDevice, count, ctx.allocator)
	vk.EnumeratePhysicalDevices(ctx.instance, &count, raw_data(devices))

	for dev in devices {
		gf, pf, ok := find_queue_families(ctx, dev)
		if !ok {continue}
		if !check_device_extension_support(dev) {continue}

		ctx.physical_device = dev
		ctx.graphics_family = gf
		ctx.present_family = pf
		return true
	}

	fmt.eprintln("No suitable physical device found ")
	return false
}

find_queue_families :: proc(
	ctx: ^Render_Context,
	device: vk.PhysicalDevice,
) -> (
	graphics: u32,
	present: u32,
	ok: bool,
) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	families := make([]vk.QueueFamilyProperties, count, ctx.allocator)
	defer delete(families, ctx.allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	found_graphics, found_present: bool

	for props, i in families {
		idx := u32(i)
		if .GRAPHICS in props.queueFlags {
			graphics = idx
			found_graphics = true
		}

		present_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, idx, ctx.surface, &present_support)
		if present_support {
			present = idx
			found_present = true
		}

		if found_graphics && found_present {
			return graphics, present, true
		}
	}

	return 0, 0, false
}

check_device_extension_support :: proc(device: vk.PhysicalDevice) -> bool {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)
	return count > 0
}

@(private = "file")
create_logical_device :: proc(ctx: ^Render_Context) -> bool {
	unique_families: [2]u32
	family_count: int
	unique_families[0] = ctx.graphics_family
	family_count = 1
	if ctx.present_family != ctx.graphics_family {
		unique_families[1] = ctx.present_family
		family_count = 2
	}

	priority: f32 = 1.0
	queue_infos: [2]vk.DeviceQueueCreateInfo
	for i in 0 ..< family_count {
		queue_infos[i] = vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = unique_families[i],
			queueCount       = 1,
			pQueuePriorities = &priority,
		}
	}

	device_extensions := [1]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
	features := vk.PhysicalDeviceFeatures{}

	device_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(family_count),
		pQueueCreateInfos       = &queue_infos[0],
		enabledExtensionCount   = 1,
		ppEnabledExtensionNames = &device_extensions[0],
		pEnabledFeatures        = &features,
	}

	if vk.CreateDevice(ctx.physical_device, &device_info, nil, &ctx.device) != .SUCCESS {
		return false
	}

	vk.GetDeviceQueue(ctx.device, ctx.graphics_family, 0, &ctx.graphics_queue)
	vk.GetDeviceQueue(ctx.device, ctx.present_family, 0, &ctx.present_queue)
	return true
}

@(private = "file")
create_swapchain :: proc(ctx: ^Render_Context, width, height: u32) -> bool {
	caps: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.physical_device, ctx.surface, &caps)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &format_count, nil)
	formats := make([]vk.SurfaceFormatKHR, format_count, context.temp_allocator)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(
		ctx.physical_device,
		ctx.surface,
		&format_count,
		raw_data(formats),
	)

	ctx.swapchain_format = formats[0]
	for f in formats {
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			ctx.swapchain_format = f
			break
		}
	}

	if caps.currentExtent.width != max(u32) {
		ctx.swapchain_extent = caps.currentExtent
	} else {
		ctx.swapchain_extent = vk.Extent2D {
			width  = clamp(width, caps.minImageExtent.width, caps.maxImageExtent.width),
			height = clamp(height, caps.minImageExtent.height, caps.maxImageExtent.height),
		}
	}

	image_count := caps.minImageCount + 1
	if caps.maxImageCount > 0 && image_count > caps.maxImageCount {
		image_count = caps.maxImageCount
	}

	queue_family_indices := [2]u32{ctx.graphics_family, ctx.present_family}

	swapchain_info := vk.SwapchainCreateInfoKHR {
		sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
		surface               = ctx.surface,
		minImageCount         = image_count,
		imageFormat           = ctx.swapchain_format.format,
		imageColorSpace       = ctx.swapchain_format.colorSpace,
		imageExtent           = ctx.swapchain_extent,
		imageArrayLayers      = 1,
		imageUsage            = {.COLOR_ATTACHMENT},
		preTransform          = caps.currentTransform,
		compositeAlpha        = {.OPAQUE},
		presentMode           = .FIFO,
		clipped               = true,
	}

	if ctx.graphics_family != ctx.present_family {
		swapchain_info.imageSharingMode = .CONCURRENT
		swapchain_info.queueFamilyIndexCount = 2
		swapchain_info.pQueueFamilyIndices = &queue_family_indices[0]
	} else {
		swapchain_info.imageSharingMode = .EXCLUSIVE
		swapchain_info.queueFamilyIndexCount = 0
		swapchain_info.pQueueFamilyIndices = nil
	}

	if vk.CreateSwapchainKHR(ctx.device, &swapchain_info, nil, &ctx.swapchain) != .SUCCESS {
		return false
	}

	actual_count: u32 = 0
	vk.GetSwapchainImagesKHR(ctx.device, ctx.swapchain, &actual_count, nil)

	// Ensure we clean up old slices if this is a resize/recreation
	if ctx.swapchain_images != nil {
		delete(ctx.swapchain_images, ctx.allocator)
	}

	ctx.swapchain_images = make([]vk.Image, actual_count, ctx.allocator)
	vk.GetSwapchainImagesKHR(
		ctx.device,
		ctx.swapchain,
		&actual_count,
		raw_data(ctx.swapchain_images),
	)

	if ctx.swapchain_views != nil {
		delete(ctx.swapchain_views, ctx.allocator)
	}

	ctx.swapchain_views = make([]vk.ImageView, actual_count, ctx.allocator)
	for img, i in ctx.swapchain_images {
		view_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = img,
			viewType = .D2,
			format = ctx.swapchain_format.format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		if vk.CreateImageView(ctx.device, &view_info, nil, &ctx.swapchain_views[i]) != .SUCCESS {
			return false
		}
	}

	return true
}

create_render_pass :: proc(ctx: ^Render_Context) -> bool {
	color_attachment := vk.AttachmentDescription {
		format         = ctx.swapchain_format.format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	render_pass_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	return vk.CreateRenderPass(ctx.device, &render_pass_info, nil, &ctx.render_pass) == .SUCCESS
}

@(private = "file")
create_framebuffers :: proc(ctx: ^Render_Context) -> bool {
	ctx.framebuffers = make([]vk.Framebuffer, len(ctx.swapchain_views), ctx.allocator)

	for view, i in ctx.swapchain_views {
		attachments := [1]vk.ImageView{view}
		fb_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = ctx.render_pass,
			attachmentCount = 1,
			pAttachments    = &attachments[0],
			width           = ctx.swapchain_extent.width,
			height          = ctx.swapchain_extent.height,
			layers          = 1,
		}
		if vk.CreateFramebuffer(ctx.device, &fb_info, nil, &ctx.framebuffers[i]) != .SUCCESS {
			return false
		}
	}

	return true
}

@(private = "file")
create_command_resources :: proc(ctx: ^Render_Context) -> bool {
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = ctx.graphics_family,
	}
	if vk.CreateCommandPool(ctx.device, &pool_info, nil, &ctx.command_pool) != .SUCCESS {
		return false
	}

	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	result := vk.AllocateCommandBuffers(ctx.device, &alloc_info, &ctx.command_buffers[0])
	return result == .SUCCESS
}

@(private = "file")
create_sync_objects :: proc(ctx: ^Render_Context) -> bool {
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if vk.CreateSemaphore(ctx.device, &sem_info, nil, &ctx.image_available[i]) != .SUCCESS {
			return false
		}
		if vk.CreateSemaphore(ctx.device, &sem_info, nil, &ctx.render_finished[i]) != .SUCCESS {
			return false
		}
		if vk.CreateFence(ctx.device, &fence_info, nil, &ctx.in_flight_fences[i]) != .SUCCESS {
			return false
		}
	}
	return true
}

recreate_swapchain :: proc(ctx: ^Render_Context, width, height: u32) -> bool {
	vk.DeviceWaitIdle(ctx.device)

	for fb in ctx.framebuffers {
		vk.DestroyFramebuffer(ctx.device, fb, nil)
	}
	delete(ctx.framebuffers, ctx.allocator)

	for view in ctx.swapchain_views {
		vk.DestroyImageView(ctx.device, view, nil)
	}
	delete(ctx.swapchain_views, ctx.allocator)
	delete(ctx.swapchain_images, ctx.allocator)

	old_swapchain := ctx.swapchain
	if !create_swapchain(ctx, width, height) {return false}
	vk.DestroySwapchainKHR(ctx.device, old_swapchain, nil)

	ctx.viewport_size = {f32(width), f32(height)}

	return create_framebuffers(ctx)
}

execute_immediate :: proc(ctx: ^Render_Context, fn: Immediate_Fn, user_data: rawptr = nil) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	cmd: vk.CommandBuffer
	vk.AllocateCommandBuffers(ctx.device, &alloc_info, &cmd)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(cmd, &begin_info)

	fn(cmd, user_data)

	vk.EndCommandBuffer(cmd)

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd,
	}
	vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, {})
	vk.QueueWaitIdle(ctx.graphics_queue)
	vk.FreeCommandBuffers(ctx.device, ctx.command_pool, 1, &cmd)
}
