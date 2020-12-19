module flare.vulkan.swapchain;

import flare.core.memory.temp;
import flare.vulkan.commands;
import flare.vulkan.context;
import flare.vulkan.device;
import flare.vulkan.h;

nothrow:

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

struct Frame {
    uint index;
    VkFramebuffer framebuffer;

    VkFence frame_complete_fence;
    VkSemaphore image_acquire;
    VkSemaphore render_complete;

    bool opCast(T: bool)() const {
        return framebuffer !is null;
    }
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

/// The information required to draw to a single frame buffer.
struct SwapchainImage {
    /// 
    uint index;

    /// The image memory backing the framebuffer.
    VkImage image;

    /// The image view used by the framebuffer.
    VkImageView view;

    /// The framebuffer for this frame.
    VkFramebuffer framebuffer;

    /// Fence to set when the frame has been presented.
    VkFence frame_complete_fence;
}

struct Swapchain {
nothrow:

    /// The swapchain of images that will be displayed to the surface.
    VkSwapchainKHR handle;

    /// 
    VkRenderPass render_pass;

    /// Per-frame information for rendering.
    SwapchainImage[] frames;

    FrameSemaphores[] semaphores;

    /// The size of every image in the swapchain.
    VkExtent2D image_size;

    /// The format of the images in the swapchain.
    VkFormat format;

    /// The color space of the images in the swapchain. Probably
    /// VK_COLOR_SPACE_SRGB_NONLINEAR_KHR.
    VkColorSpaceKHR color_space;

    /// The format of the images in the swapchain.
    VkPresentModeKHR present_mode;

    /// The number of images in the swapchain.
    // uint num_frames;
    size_t num_frames() { return frames.length; }

    Frame get_frame(VulkanDevice device) {
        auto sync_pair = &semaphores[_current_semaphore_index];

        device.d_acquire_next_image(handle, ulong.max, sync_pair.image_acquire, null, &_current_frame_index);
        auto frame = &frames[_current_frame_index];

        device.wait_fences(true, frame.frame_complete_fence);
        device.reset_fences(frame.frame_complete_fence);

        return Frame(
            _current_frame_index,
            frame.framebuffer,
            frame.frame_complete_fence,
            sync_pair.image_acquire,
            sync_pair.render_complete);
    }

    void swap_buffers(VulkanDevice device) {
        VkPresentInfoKHR pi = {
            waitSemaphoreCount: 1,
            pWaitSemaphores: &semaphores[_current_semaphore_index].render_complete,
            swapchainCount: 1,
            pSwapchains: &handle,
            pImageIndices: &_current_frame_index,
            pResults: null,
        };

        device.d_queue_present(device.graphics, &pi);

        _current_semaphore_index = (_current_semaphore_index + 1) % num_frames;
    }

    bool opCast(T: bool)() const {
        return handle != null;
    }

private:
    uint _current_frame_index;
    uint _current_semaphore_index;
}

void create_swapchain(VulkanDevice device, VkSurfaceKHR surface, out Swapchain swapchain) {
    auto mem = TempAllocator(device.context.memory);

    uint num_frames;
    { // Swapchain format and size information
        SwapchainSupport support;
        load_swapchain_support(device.gpu.handle, surface, mem, support);

        swapchain.image_size = swapchain_size(support.capabilities, support.capabilities.currentExtent);

        auto format = select(support.formats);
        swapchain.format = format.format;
        swapchain.color_space = format.colorSpace;

        swapchain.present_mode = select(support.modes);

        num_frames = num_images(support.capabilities);
    }

    { // Create swapchain
        VkSwapchainCreateInfoKHR ci = {
            surface: surface,
            imageFormat: swapchain.format,
            imageColorSpace: swapchain.color_space,
            imageArrayLayers: 1,
            minImageCount: num_frames,
            imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            imageExtent: swapchain.image_size,
            presentMode: swapchain.present_mode,
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

        device.d_create_swapchain(&ci, &swapchain.handle);
    }

    { // Create render pass
        VkAttachmentDescription color_attachment = {
            format: swapchain.format,
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

        device.d_create_render_pass(&ci, &swapchain.render_pass);
    }

    { // Create per-frame objects
        swapchain.frames = device.context.memory.alloc_array!SwapchainImage(num_frames);

        device.d_get_swapchain_images(swapchain.handle, &num_frames, null);
        auto images = mem.alloc_array!VkImage(num_frames);
        device.d_get_swapchain_images(swapchain.handle, &num_frames, images.ptr);

        foreach (i, ref frame; swapchain.frames[0 .. num_frames]) {
            frame.index = cast(uint) i;
            frame.image = images[i];
            frame.frame_complete_fence = device.create_fence(true);

            {
                VkImageViewCreateInfo vci = {
                    image: images[i],
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

                device.d_create_image_view(&vci, &frame.view);
            }

            {
                VkFramebufferCreateInfo fci = {
                    renderPass: swapchain.render_pass,
                    attachmentCount: 1,
                    pAttachments: &frame.view,
                    width: swapchain.image_size.width,
                    height: swapchain.image_size.height,
                    layers: 1
                };

                device.d_create_framebuffer(&fci, &frame.framebuffer);
            }
        }

        swapchain.semaphores = device.context.memory.alloc_array!FrameSemaphores(num_frames);

        foreach (ref pair; swapchain.semaphores) {
            pair.image_acquire = device.create_semaphore();
            pair.render_complete = device.create_semaphore();
        }
    }
}

void destroy_swapchain(VulkanDevice device, ref Swapchain swapchain) {
    device.wait_idle();

    foreach (ref frame; swapchain.frames) {
        device.d_destroy_image_view(frame.view);
        device.d_destroy_framebuffer(frame.framebuffer);
        device.destroy_fence(frame.frame_complete_fence);
    }
    device.context.memory.free(swapchain.frames);

    foreach (ref pair; swapchain.semaphores) {
        device.destroy_semaphore(pair.image_acquire);
        device.destroy_semaphore(pair.render_complete);
    }
    device.context.memory.free(swapchain.semaphores);

    device.d_destroy_render_pass(swapchain.render_pass);
    device.d_destroy_swapchain(swapchain.handle);

    swapchain = Swapchain();
}

private:

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
