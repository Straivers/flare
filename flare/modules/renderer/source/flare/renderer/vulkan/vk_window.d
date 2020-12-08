module flare.renderer.vulkan.vk_window;

import flare.core.memory.temp;
import flare.renderer.vulkan.commands;
import flare.renderer.vulkan.context;
import flare.renderer.vulkan.device;
import flare.renderer.vulkan.h;

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

/**
 Vulkan-specific information about how to present to a window.
 */
struct VulkanWindow {
    /// Triple buffered
    enum num_images_preferred = 3;

    /// The information required to draw to a single frame buffer.
    struct Frame {
        /// The image memory backing the framebuffer.
        VkImage image;

        /// The image view used by the framebuffer.
        VkImageView view;

        /// The framebuffer for this frame.
        VkFramebuffer framebuffer;

        /// The buffer to write commands to for this frame.
        /// TODO: Figure out how to get this out of VulkanWindow
        VkCommandBuffer command_buffer;
        
        /// Fence to set when the frame has been presented.
        VkFence frame_complete_fence;
    }

    /// Primitives to coordinate the order of operations for a frame to be rendered.
    struct FrameSemaphores {
        /// Semaphore to set when an image is available to be rendered to. See
        /// `vkAcquireNextImage` and `VkSubmitInfo` for details.
        VkSemaphore image_acquire;

        /// Semaphore to set when the render pipeline for this frame has
        /// completed.
        VkSemaphore render_complete;
    }

    /// The logical device which created this window.
    VulkanDevice device;

    /// The surface representing the window.
    VkSurfaceKHR surface;

    /// The swapchain of images that will be displayed to the surface.
    VkSwapchainKHR swapchain;

    /// 
    VkRenderPass render_pass;

    /// Per-frame information for rendering.
    Frame* frames;

    /// Rotating buffer of semaphores for frame synchronization.
    FrameSemaphores* frame_semaphores;
    
    /// The format of the images in the swapchain.
    VkFormat format;

    /// The color space of the images in the swapchain. Probably
    /// VK_COLOR_SPACE_SRGB_NONLINEAR_KHR.
    VkColorSpaceKHR color_space;

    /// The format of the images in the swapchain.
    VkPresentModeKHR present_mode;

    /// The size of every image in the swapchain.
    VkExtent2D image_size;

    /// The number of images in the swapchain.
    uint num_frames;

    ref Frame current_frame() {
        return frames[_frame_index];
    }

    ref FrameSemaphores current_semaphores() {
        return frame_semaphores[_semaphore_index];
    }

    Frame* acquire_next_frame() {
        // Get the index of the next frame.
        uint index;
        device.d_acquire_next_image(swapchain, ulong.max, current_semaphores.image_acquire, null, &index);

        // If the frame is still in use, wait for it.
        device.wait_fences(true, frames[index].frame_complete_fence);
        device.reset_fences(frames[index].frame_complete_fence);

        // Finalize the frame acquisition by making it accessible by current_frame().
        _frame_index = index;
        return &frames[_frame_index];
    }

    void swap_buffers() {
        VkPresentInfoKHR pi = {
            waitSemaphoreCount: 1,
            pWaitSemaphores: &current_semaphores.render_complete,
            swapchainCount: 1,
            pSwapchains: &swapchain,
            pImageIndices: &_frame_index,
            pResults: null,
        };

        device.d_queue_present(device.graphics, &pi);

        // Make the next set of semaphores available for the subsequent frame.
        _semaphore_index = (_semaphore_index + 1) % num_frames;
    }

private:
    /// The index into frames.
    uint _frame_index;

    /// The index into frame_semaphores.
    uint _semaphore_index;
}

void create_vulkan_window(VulkanDevice device, VkSurfaceKHR surface, CommandPool cmd_pool, out VulkanWindow window) {
    create_swapchain(device, surface, cmd_pool, window);
}

void destroy_vulkan_window(CommandPool cmd_pool, ref VulkanWindow window) {
    foreach (ref frame; window.frames[0 .. window.num_frames]) {
        cmd_pool.free(frame.command_buffer);
        window.device.d_destroy_framebuffer(frame.framebuffer);
        window.device.d_destroy_image_view(frame.view);
        window.device.destroy_fence(frame.frame_complete_fence);
    }

    window.device.context.memory.free(window.frames[0 .. window.num_frames]);

    foreach (ref sync; window.frame_semaphores[0 .. window.num_frames]) {
        window.device.destroy_semaphore(sync.image_acquire);
        window.device.destroy_semaphore(sync.render_complete);
    }

    window.device.context.memory.free(window.frame_semaphores[0 .. window.num_frames]);

    window.device.d_destroy_render_pass(window.render_pass);
    window.device.d_destroy_swapchain(window.swapchain);
    vkDestroySurfaceKHR(window.device.context.instance, window.surface, null);
}

private:

void create_swapchain(VulkanDevice device, VkSurfaceKHR surface, CommandPool cmd_pool, out VulkanWindow window) {
    auto mem = TempAllocator(device.context.memory);

    window.device = device;
    window.surface = surface;

    { // Swapchain format and size information
        SwapchainSupport support;
        load_swapchain_support(device.gpu.device, surface, mem, support);

        window.image_size = swapchain_size(support.capabilities, support.capabilities.currentExtent);

        auto format = select(support.formats);
        window.format = format.format;
        window.color_space = format.colorSpace;

        window.present_mode = select(support.modes);

        window.num_frames = num_images(support.capabilities);
    }

    { // Create swapchain
        VkSwapchainCreateInfoKHR ci = {
            surface: surface,
            imageFormat: window.format,
            imageColorSpace: window.color_space,
            imageArrayLayers: 1,
            minImageCount: window.num_frames,
            imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            imageExtent: window.image_size,
            presentMode: window.present_mode,
            preTransform: VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
            compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            clipped: VK_TRUE
        };

        if (device.graphics_family != device.present_family) {
            // Allocate indices on temp allocator
            auto indices = mem.alloc_array!uint(2);
            indices[0] = device.graphics_family;
            indices[1] = device.present_family;

            ci.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
            ci.queueFamilyIndexCount = 2;
            ci.pQueueFamilyIndices = indices.ptr;
        }
        else
            ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
        
        device.d_create_swapchain(&ci, &window.swapchain);
    }

    { // Create render pass
        VkAttachmentDescription color_attachment = {
            format: window.format,
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

        device.d_create_render_pass(&ci, &window.render_pass);
    }

    { // Create per-frame objects
        device.d_get_swapchain_images(window.swapchain, &window.num_frames, null);
        auto images = mem.alloc_array!VkImage(window.num_frames);
        device.d_get_swapchain_images(window.swapchain, &window.num_frames, images.ptr);

        auto cmd_buffers = mem.alloc_array!VkCommandBuffer(window.num_frames);
        cmd_pool.allocate(cmd_buffers);

        with (device.context.memory) {
            window.frames = alloc_array!(VulkanWindow.Frame)(window.num_frames).ptr;
            window.frame_semaphores = alloc_array!(VulkanWindow.FrameSemaphores)(window.num_frames).ptr;
        }

        foreach (i, ref frame; window.frames[0 .. window.num_frames]) {
            frame.image = images[i];
            frame.command_buffer = cmd_buffers[i];
            frame.frame_complete_fence = device.create_fence(true);

            {
                VkImageViewCreateInfo vci = {
                    image: images[i],
                    format: window.format,
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

                device.d_create_image_view(&vci, &frame.view);
            }

            {
                VkFramebufferCreateInfo fci = {
                    renderPass: window.render_pass,
                    attachmentCount: 1,
                    pAttachments: &frame.view,
                    width: window.image_size.width,
                    height: window.image_size.height,
                    layers: 1
                };

                device.d_create_framebuffer(&fci, &frame.framebuffer);
            }
        }

        foreach (ref sync; window.frame_semaphores[0 .. window.num_frames]) {
            sync.image_acquire = device.create_semaphore();
            sync.render_complete = device.create_semaphore();
        }
    }
}

struct SwapchainSupport {
    VkSurfaceKHR target;
    VkSurfaceCapabilitiesKHR capabilities;
    VkSurfaceFormatKHR[] formats;
    VkPresentModeKHR[] modes;
}

void load_swapchain_support(
    VkPhysicalDevice gpu,
    VkSurfaceKHR target,
    ref TempAllocator mem,
    out SwapchainSupport result
) {
    assert(target);
    result.target = target;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, target, &result.capabilities);

    uint n_formats;
    vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, target, &n_formats, null);
    result.formats = mem.alloc_array!VkSurfaceFormatKHR(n_formats);
    vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, target, &n_formats, result.formats.ptr);

    uint n_modes;
    vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, target, &n_modes, null);
    result.modes = mem.alloc_array!VkPresentModeKHR(n_modes);
    vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, target, &n_modes, result.modes.ptr);
}

VkSurfaceFormatKHR select(in VkSurfaceFormatKHR[] formats) {
    foreach (ref format; formats) {
        if (format.format == VK_FORMAT_B8G8R8A8_SRGB && format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            return format;
    }

    return formats[0];
}

VkPresentModeKHR select(in VkPresentModeKHR[] modes) {
    foreach (mode; modes) {
        if (mode == VK_PRESENT_MODE_MAILBOX_KHR)
            return mode;
    }

    return VK_PRESENT_MODE_FIFO_KHR;
}

VkExtent2D swapchain_size(in VkSurfaceCapabilitiesKHR capabilities, VkExtent2D window_size) {
    import std.algorithm: min, max;

    if (capabilities.currentExtent.width != uint.max)
        return capabilities.currentExtent;

    VkExtent2D result = {
        width: max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, window_size.width)),
        height: max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, window_size.height))
    };

    return result;
}

uint num_images(in VkSurfaceCapabilitiesKHR capabilities) {
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
