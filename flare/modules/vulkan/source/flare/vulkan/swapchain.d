module flare.vulkan.swapchain;

import flare.vulkan.context;
import flare.vulkan.commands;
import flare.vulkan.device;
import flare.vulkan.h;

nothrow:

/*
 * TODO: Separate out framebuffers, command bufffers, fences, and semaphores
 * because we only need max 3 of them. Swapchains may have more than 3, and we
 * don't need the extra objects.
 */

version (Windows) {
    import core.sys.windows.windows : GetModuleHandle, HWND, NULL;

    VkSurfaceKHR create_surface(VulkanContext ctx, HWND window) {
        VkWin32SurfaceCreateInfoKHR sci = {hwnd: window,
        hinstance: GetModuleHandle(NULL)};

        VkSurfaceKHR handle;
        auto err = vkCreateWin32SurfaceKHR(ctx.instance, &sci, null, &handle);
        if (err == VK_SUCCESS)
            return handle;

        ctx.logger.fatal("Unable to create window surface: %s", err);
        assert(0, "Unable to create window surface.");
    }
}

struct SwapchainProperties {
    VkSurfaceKHR surface;

    uint n_images;

    /// The size of every image in the swapchain.
    VkExtent2D image_size;

    /// The format of the images in the swapchain.
    VkFormat format;

    /// The color space of the images in the swapchain. Probably
    /// VK_COLOR_SPACE_SRGB_NONLINEAR_KHR.
    VkColorSpaceKHR color_space;

    /// The format of the images in the swapchain.
    VkPresentModeKHR present_mode;
}

struct Swapchain {
    VkSwapchainKHR handle;

    SwapchainProperties properties;
    alias properties this;

    VkRenderPass render_pass;

    VkImage[] images;
    VkImageView[] views;

    VkFramebuffer[] framebuffers;
    VkCommandBuffer[] command_buffers;

    VkFence[] frame_fences;
    VkSemaphore[] image_acquire_semaphores;
    VkSemaphore[] render_complete_semaphores;

    VkResult state;
    ushort current_sync_index;
    ushort current_frame_index;
}

struct SwapchainImage {
    uint index;
    VkFramebuffer framebuffer;
    VkCommandBuffer command_buffer;
    VkFence frame_fence;
    VkSemaphore image_acquire;
    VkSemaphore render_complete;
}

/**
 * Initializes a new swapchain.
 *
 * If a surface has no size (if the window is hidden), this function does nothing.
 */
bool create_swapchain(VulkanDevice device, CommandPool command_pool, VkSurfaceKHR surface, out Swapchain swapchain) {
    auto properties = _get_swapchain_properties(device, surface);

    if (properties.image_size == VkExtent2D()) {
        device.context.logger.trace("Attempted to create 0-sized swapchain for surface %s, deferring operation.", surface);
        return false;
    }
    
    swapchain.properties = properties;

    swapchain.handle = _create_swapchain(device, properties, null);
    swapchain.render_pass = _create_render_pass(device, properties.format);
    _get_frame_objects(device, command_pool, swapchain);
    _get_sync_objects(device, swapchain);

    device.context.logger.trace("Created swapchain (%sw, %sh) ID %s for surface %s.", swapchain.image_size.width, swapchain.image_size.height, swapchain.handle, surface);

    return true;
}

/**
 * Recreates a swapchain.
 *
 * If the swapchain was not previously initialized (`create_swapchain()`
 * returned `false` due to a hidden window), `recreate_swapchain()` will create
 * a new swapchain.
 */
void recreate_swapchain(VulkanDevice device, CommandPool command_pool, VkSurfaceKHR surface, ref Swapchain swapchain) {
    if (!swapchain.handle) {
        create_swapchain(device, command_pool, surface, swapchain);
        return;
    }

    device.wait_idle();

    auto properties = _get_swapchain_properties(device, surface);
    Swapchain new_swapchain = {
        handle: _create_swapchain(device, properties, swapchain.handle),
        properties: properties,
    };

    device.d_destroy_swapchain(swapchain.handle);

    if (swapchain.format == new_swapchain.format)
        new_swapchain.render_pass = swapchain.render_pass;
    else {
        device.d_destroy_render_pass(swapchain.render_pass);
        new_swapchain.render_pass = _create_render_pass(device, swapchain.format);
    }

    _free_frame_objects(device, command_pool, swapchain);
    _get_frame_objects(device, command_pool, new_swapchain);

    if (new_swapchain.images.length == swapchain.images.length) {
        new_swapchain.frame_fences = swapchain.frame_fences;
        new_swapchain.image_acquire_semaphores = swapchain.image_acquire_semaphores;
        new_swapchain.render_complete_semaphores = swapchain.render_complete_semaphores;
    }
    else {
        _free_sync_objects(device, swapchain);
        _get_sync_objects(device, new_swapchain);
    }

    device.context.logger.trace("Swapchain for surface %s has been recreated. It is now %s (%sw, %sh).", surface, new_swapchain.handle, properties.image_size.width, properties.image_size.height);

    swapchain = new_swapchain;
}

void destroy_swapchain(VulkanDevice device, CommandPool command_pool, ref Swapchain swapchain) {
    if (!swapchain.handle)
        return;

    device.wait_idle();
    _free_frame_objects(device, command_pool, swapchain);
    _free_sync_objects(device, swapchain);
    device.d_destroy_render_pass(swapchain.render_pass);
    device.d_destroy_swapchain(swapchain.handle);
    swapchain = Swapchain();
}

void acquire_next_image(VulkanDevice device, Swapchain* swapchain, out SwapchainImage image) {
    uint index;
    const err = device.d_acquire_next_image(swapchain.handle, ulong.max, swapchain.image_acquire_semaphores[swapchain.current_sync_index], null, index);
    swapchain.state = err;

    swapchain.current_frame_index = cast(ushort) index;

    device.wait_fences(true, swapchain.frame_fences[index]);
    device.reset_fences(swapchain.frame_fences[index]);

    image.index = index;

    image.framebuffer = swapchain.framebuffers[index];
    image.command_buffer = swapchain.command_buffers[index];
    image.frame_fence = swapchain.frame_fences[index];

    image.image_acquire = swapchain.image_acquire_semaphores[swapchain.current_sync_index];
    image.render_complete = swapchain.render_complete_semaphores[swapchain.current_sync_index];
}

void swap_buffers(VulkanDevice device, Swapchain* swapchain) {
    uint index = swapchain.current_frame_index;
    VkPresentInfoKHR pi = {
        waitSemaphoreCount: 1,
        pWaitSemaphores: &swapchain.render_complete_semaphores[swapchain.current_sync_index],
        swapchainCount: 1,
        pSwapchains: &swapchain.handle,
        pImageIndices: &index,
        pResults: null,
    };

    const err = device.d_queue_present(device.graphics, pi);
    swapchain.state = err;

    swapchain.current_sync_index = cast(ushort) ((swapchain.current_sync_index + 1) % swapchain.images.length);
}

private:
VkSwapchainKHR _create_swapchain(VulkanDevice device, ref SwapchainProperties properties, VkSwapchainKHR old) {
    VkSwapchainCreateInfoKHR ci = {
        surface: properties.surface,
        minImageCount: properties.n_images,
        imageFormat: properties.format,
        imageColorSpace: properties.color_space,
        imageArrayLayers: 1,
        imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        imageExtent: properties.image_size,
        presentMode: properties.present_mode,
        preTransform: VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
        compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        clipped: VK_TRUE,
        oldSwapchain: old
    };

    const uint[2] shared_queue_indices = [device.graphics_family, device.present_family];
    if (device.graphics_family != device.present_family) {
        ci.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
        ci.queueFamilyIndexCount = cast(uint) shared_queue_indices.length;
        ci.pQueueFamilyIndices = shared_queue_indices.ptr;
    }
    else
        ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkSwapchainKHR swapchain;
    device.d_create_swapchain(ci, swapchain);
    return swapchain;
}

VkRenderPass _create_render_pass(VulkanDevice device, VkFormat format) {
    VkAttachmentDescription color_attachment = {
        format: format,
        samples: VK_SAMPLE_COUNT_1_BIT,
        loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp: VK_ATTACHMENT_STORE_OP_STORE,
        stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
        finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    };

    VkAttachmentReference color_attachment_ref = {
        attachment: 0,
        layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    };

    VkSubpassDescription subpass = {
        pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
        colorAttachmentCount: 1,
        pColorAttachments: &color_attachment_ref
    };

    VkSubpassDependency dependency = {
        srcSubpass: VK_SUBPASS_EXTERNAL,
        dstSubpass: 0,
        srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        srcAccessMask: 0,
        dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    VkRenderPassCreateInfo ci = {
        attachmentCount: 1,
        pAttachments: &color_attachment,
        subpassCount: 1,
        pSubpasses: &subpass,
        dependencyCount: 1,
        pDependencies: &dependency
    };

    VkRenderPass render_pass;
    device.d_create_render_pass(ci, render_pass);
    return render_pass;
}

void _get_frame_objects(VulkanDevice device, CommandPool command_pool, ref Swapchain swapchain) {
    uint count;
    device.d_get_swapchain_images(swapchain.handle, count, null);
    swapchain.images = device.context.memory.alloc_array!VkImage(count);
    device.d_get_swapchain_images(swapchain.handle, count, swapchain.images.ptr);

    swapchain.command_buffers = device.context.memory.alloc_array!VkCommandBuffer(count);
    command_pool.allocate(swapchain.command_buffers);

    swapchain.views = device.context.memory.alloc_array!VkImageView(count);
    swapchain.framebuffers = device.context.memory.alloc_array!VkFramebuffer(count);
    foreach (i, ref image; swapchain.images) {
        VkImageViewCreateInfo vci = {
            image: image,
            format: swapchain.format,
            viewType: VK_IMAGE_VIEW_TYPE_2D,
            components: VkComponentMapping(),
            subresourceRange: {
                aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
                baseArrayLayer: 0,
                baseMipLevel: 0,
                levelCount: 1,
                layerCount: 1
            }
        };

        device.d_create_image_view(vci, swapchain.views[i]);

        VkFramebufferCreateInfo fci = {
            renderPass: swapchain.render_pass,
            attachmentCount: 1,
            pAttachments: &swapchain.views[i],
            width: swapchain.image_size.width,
            height: swapchain.image_size.height,
            layers: 1
        };

        device.d_create_framebuffer(fci, swapchain.framebuffers[i]);
    }
}

void _free_frame_objects(VulkanDevice device, CommandPool command_pool, ref Swapchain swapchain) {
    foreach (i; 0 .. swapchain.images.length) {
        device.d_destroy_framebuffer(swapchain.framebuffers[i]);
        device.d_destroy_image_view(swapchain.views[i]);
    }

    command_pool.free(swapchain.command_buffers);
    device.context.memory.free(swapchain.command_buffers);

    device.context.memory.free(swapchain.framebuffers);
    device.context.memory.free(swapchain.views);
    device.context.memory.free(swapchain.images);
}

void _get_sync_objects(VulkanDevice device, ref Swapchain swapchain) {
    swapchain.frame_fences = device.context.memory.alloc_array!VkFence(swapchain.images.length);
    swapchain.image_acquire_semaphores = device.context.memory.alloc_array!VkSemaphore(swapchain.images.length);
    swapchain.render_complete_semaphores = device.context.memory.alloc_array!VkSemaphore(swapchain.images.length);

    foreach (i; 0 .. swapchain.images.length) {
        swapchain.frame_fences[i] = device.create_fence(true);
        swapchain.image_acquire_semaphores[i] = device.create_semaphore();
        swapchain.render_complete_semaphores[i] = device.create_semaphore();
    }
}

void _free_sync_objects(VulkanDevice device, ref Swapchain swapchain) {
    foreach (i; 0 .. swapchain.images.length) {
        device.destroy_fence(swapchain.frame_fences[i]);
        device.destroy_semaphore(swapchain.image_acquire_semaphores[i]);
        device.destroy_semaphore(swapchain.render_complete_semaphores[i]);
    }

    device.context.memory.free(swapchain.frame_fences);
    device.context.memory.free(swapchain.image_acquire_semaphores);
    device.context.memory.free(swapchain.render_complete_semaphores);
}

SwapchainProperties _get_swapchain_properties(VulkanDevice device, VkSurfaceKHR surface) {
    import flare.core.memory.temp: TempAllocator;

    auto mem = TempAllocator(device.context.memory);

    VkSurfaceCapabilitiesKHR capabilities;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device.gpu.handle, surface, &capabilities);

    uint n_formats;
    vkGetPhysicalDeviceSurfaceFormatsKHR(device.gpu.handle, surface, &n_formats, null);
    auto formats = mem.alloc_array!VkSurfaceFormatKHR(n_formats);
    vkGetPhysicalDeviceSurfaceFormatsKHR(device.gpu.handle, surface, &n_formats, formats.ptr);

    uint n_modes;
    vkGetPhysicalDeviceSurfacePresentModesKHR(device.gpu.handle, surface, &n_modes, null);
    auto modes = mem.alloc_array!VkPresentModeKHR(n_modes);
    vkGetPhysicalDeviceSurfacePresentModesKHR(device.gpu.handle, surface, &n_modes, modes.ptr);

    return SwapchainProperties(
        surface,
        _num_images(capabilities),
        _image_size(capabilities),
        _select(formats).format,
        _select(formats).colorSpace,
        _select(modes),
    );
}

VkSurfaceFormatKHR _select(in VkSurfaceFormatKHR[] formats) {
    foreach (ref format; formats) {
        if (format.format == VK_FORMAT_B8G8R8A8_SRGB && format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            return format;
    }

    return formats[0];
}

VkPresentModeKHR _select(in VkPresentModeKHR[] modes) {
    foreach (mode; modes) {
        if (mode == VK_PRESENT_MODE_MAILBOX_KHR)
            return mode;
    }

    return VK_PRESENT_MODE_FIFO_KHR;
}

VkExtent2D _image_size(in VkSurfaceCapabilitiesKHR capabilities) {
    import std.algorithm: min, max;

    if (capabilities.currentExtent.width != uint.max)
        return capabilities.currentExtent;

    VkExtent2D result = {
        width: max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, capabilities.currentExtent.width)),
        height: max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, capabilities.currentExtent.height))
    };

    return result;
}

uint _num_images(in VkSurfaceCapabilitiesKHR capabilities) {
    import std.algorithm: max;

    enum preferred_count = 3;

    // If we can have as many as we like, get 3 or more images
    if (capabilities.maxImageCount == 0) 
        return max(capabilities.minImageCount, preferred_count);

    // If we can have at least 3 images, get as close to 3 images as possible
    if (preferred_count <= capabilities.maxImageCount)
        return max(capabilities.minImageCount, preferred_count);

    // Get as many images as we are allowed
    return capabilities.maxImageCount;
}
