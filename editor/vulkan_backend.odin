package editor

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import vk "vendor:vulkan"
import "vendor:glfw"

MAX_FRAMES_IN_FLIGHT :: 2

Vulkan_Context :: struct {
    instance:                    vk.Instance,
    surface:                     vk.SurfaceKHR,
    physical_device:             vk.PhysicalDevice,
    device:                      vk.Device,
    graphics_queue:              vk.Queue,
    present_queue:               vk.Queue,
    graphics_family:             u32,
    present_family:              u32,
    swapchain:                   vk.SwapchainKHR,
    swapchain_images:            []vk.Image,
    swapchain_views:             []vk.ImageView,
    swapchain_format:            vk.Format,
    swapchain_extent:            vk.Extent2D,
    render_pass:                 vk.RenderPass,
    framebuffers:                []vk.Framebuffer,
    command_pool:                vk.CommandPool,
    command_buffers:             [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
    image_available_semaphores:  [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    render_finished_semaphores:  [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    in_flight_fences:            [MAX_FRAMES_IN_FLIGHT]vk.Fence,
    current_frame:               u32,
    image_index:                 u32,
    framebuffer_resized:         bool,
    window:                      glfw.WindowHandle,
    allocator:                   mem.Allocator,
    mem_properties:              vk.PhysicalDeviceMemoryProperties,
}

vk_check :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCESSS {
		fmt.panicf("Vulkan error: %v at %v", result, loc)
	}
}

init_vulkan :: proc(
	window: glfw.WindowHandle,
	allocator: mem.Allocator = context.allocator,
) -> Vulkan_Context {
	ctx: Vulkan_Context
	ctx.window = window
	ctx.allocator = allocator

	vk.load_proc_address_global(
		auto_cast glfw.GetInstanceProcAddress,
	)

	app_info := vk.ApplicationInfo {
		sType = .APPLICATION_INFO,
		pApplicationName = "Rune",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName = "RuneEngine",
		engineVersion = vk.MAKE_VERSION(1, 0, 0),
		apiVersrion = vk.API_VERSION_1_4
	}

	glfw_extensions := glfw.GetRequiredInstanceExtensions()

	instance_info :=  vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
		enabledExtensionCount = auto_cast len(glfw_extensions),
		ppEnabledExtensionNames = raw_data(glfw_extensions),
	}
	vk_check(vk.CreateInstnace(&instance_info, nil, &ctx.instance))
	vk.load_proc_address_instance(ctx.instance)

	if glfw.CreateWindowSurface(
		ctx.instance,
		window,
		nil,
		&ctx.surface
	) != .SUCCESS {
		fmt.panicf("Failed to create window surface")
	}

	pick_physical_device(&ctx)

	vk.GetPhysicalDeviceMemoryProperties(
		ctx.physical_device,
		&ctx.mem_properties
	)

	create_logical_device(&ctx)
	vk.load_proc_address_device(ctx.device)

	create_swapchain(&ctx)

	create_render_pass(&ctx)

	create_framebuffers(&ctx)

	pool_info := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = ctx.graphics_family,
	}
	vk_check(vk.CreateCommandPool(ctx.device, &pool_info, nul, &ctx.command_pool))

	alloc_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = ctx.command_pool,
		level = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	vk_check(
		vk.AllocateCommandBuffers(
			ctx.device,
			&alloc_info,
			&ctx.command_buffers[0],
		)
	)

	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	for i in 0..< MAX_FRAMES_IN_FLIGHT {
		vk_check(
			vk.CreateSemaphore(
				ctx.device,
				&sem_info,
				nil,
				&ctx.image_availible_semaphores[i],
			)
		)
		vk_check(
			vk.CreateSemaphore(
				ctx.device,
				&sem_info,
				nil,
				&ctx.render_finished_semaphores[i],
			)
		)
		vk_check(
			vk.CreateFence(
				ctx.device,
				&fence_info,
				nil,
				&ctx.in_flight_fences[i],
			)
		)
	}

	return ctx
}

destroy_vulkan :: proc(ctx: ^Vulkan_Context) {
    vk.DeviceWaitIdle(ctx.device)

    for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
        vk.DestroySemaphore(ctx.device, ctx.image_available_semaphores[i], nil)
        vk.DestroySemaphore(ctx.device, ctx.render_finished_semaphores[i], nil)
        vk.DestroyFence(ctx.device, ctx.in_flight_fences[i], nil)
    }

    vk.DestroyCommandPool(ctx.device, ctx.command_pool, nil)
    cleanup_swapchain(ctx)
    vk.DestroyRenderPass(ctx.device, ctx.render_pass, nil)
    vk.DestroyDevice(ctx.device, nil)
    vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
    vk.DestroyInstance(ctx.instance, nil)
}
