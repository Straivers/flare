module flare.vulkan.swapchain;

import flare.core.memory;
import flare.vulkan.context;
import flare.vulkan.device;
import flare.vulkan.h;
import std.algorithm : find, min, max;

nothrow:

enum num_preferred_swap_buffers = 3;

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

    VkImage[] images;
    VkImageView[] views;

    uint current_frame_index;
}

struct SwapchainImage {
    size_t index;

    VkImage handle;
    VkFormat format;
    VkImageView view;
    VkExtent2D image_size;
}

void get_swapchain_properties(VulkanDevice device, VkSurfaceKHR surface, bool vsync, out SwapchainProperties result) {
    auto mem = scoped_arena(device.context.memory);

    VkSurfaceCapabilitiesKHR capabilities;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device.gpu.handle, surface, &capabilities);

    uint n_formats;
    vkGetPhysicalDeviceSurfaceFormatsKHR(device.gpu.handle, surface, &n_formats, null);
    auto formats = mem.make_array!VkSurfaceFormatKHR(n_formats);
    vkGetPhysicalDeviceSurfaceFormatsKHR(device.gpu.handle, surface, &n_formats, formats.ptr);

    uint n_modes;
    vkGetPhysicalDeviceSurfacePresentModesKHR(device.gpu.handle, surface, &n_modes, null);
    auto modes = mem.make_array!VkPresentModeKHR(n_modes);
    vkGetPhysicalDeviceSurfacePresentModesKHR(device.gpu.handle, surface, &n_modes, modes.ptr);

    result.n_images = _num_images(capabilities);
    result.image_size = _image_size(capabilities);
    result.format = _select(formats).format;
    result.color_space = _select(formats).colorSpace;
    result.present_mode = _select(modes, vsync);
}

enum SwapchainResizeOp {
    Create,
    Destroy,
    Replace,
}

SwapchainResizeOp resize_swapchain(VulkanDevice device, VkSurfaceKHR surface, bool vsync, ref Swapchain swapchain) {
    SwapchainProperties properties;
    get_swapchain_properties(device, surface, vsync, properties);

    if (properties.image_size == VkExtent2D()) {
        destroy_swapchain(device, swapchain);
        return SwapchainResizeOp.Destroy;
    }
    else {
        auto old_swapchain = _create_swapchain(device, surface, properties, swapchain);
        _update_swapchain_images(device, swapchain.handle, swapchain.format, swapchain.images, swapchain.views);

        if (old_swapchain == null)
            return SwapchainResizeOp.Create;

        device.dispatch_table.DestroySwapchainKHR(old_swapchain);
        return SwapchainResizeOp.Replace;
    }
}

void destroy_swapchain(VulkanDevice device, ref Swapchain swapchain) {
    assert(swapchain.handle);

    foreach (view; swapchain.views)
        device.dispatch_table.DestroyImageView(view);

    device.context.memory.dispose(swapchain.views);
    device.context.memory.dispose(swapchain.images);
    device.dispatch_table.DestroySwapchainKHR(swapchain.handle);

    swapchain = Swapchain();
}

/**
Retrieves the index of the next swapchain image for rendering. If the frame is
still in use, it will wait until the image is free. Because of this behavior,
it is advisable to call this function as late as possible.

Params:
    device      = The device the swapchain was created from.
    swapchain   = The swapchain that has the image to be retrieved.

Returns:
    The index of the next swapchain image.
*/
bool acquire_next_image(VulkanDevice device, Swapchain* swapchain, VkSemaphore acquire_sempahore, out SwapchainImage image) {
    assert(swapchain.handle);

    const err = device.dispatch_table.AcquireNextImageKHR(swapchain.handle, ulong.max, acquire_sempahore, null, swapchain.current_frame_index);

    image.index = swapchain.current_frame_index;
    image.handle = swapchain.images[swapchain.current_frame_index];
    image.format = swapchain.format;
    image.view = swapchain.views[swapchain.current_frame_index];
    image.image_size = swapchain.image_size;

    return err != VK_ERROR_OUT_OF_DATE_KHR;
}

/**
Swaps the current image in the swapchain with a back buffer.

Params:
    device      = The device the swapchain was created from.
    swapchain   = The swapchain to be updated.

Returns:
    `true` if the swapchain images were swapped, `false` if the buffer is out of
    date.
*/
bool swap_buffers(VulkanDevice device, Swapchain* swapchain, VkSemaphore present_semaphore) {
    uint index = swapchain.current_frame_index;
    VkPresentInfoKHR pi = {
        waitSemaphoreCount: 1,
        pWaitSemaphores: &present_semaphore,
        swapchainCount: 1,
        pSwapchains: &swapchain.handle,
        pImageIndices: &index,
        pResults: null,
    };

    // FIXME: Bool does not convey enough information
    return device.dispatch_table.QueuePresentKHR(device.graphics, pi) == VK_SUCCESS;
}

private:

VkSwapchainKHR _create_swapchain(VulkanDevice device, VkSurfaceKHR surface, in SwapchainProperties properties, ref Swapchain swapchain) {
    VkSwapchainCreateInfoKHR ci = {
        surface: surface,
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
        oldSwapchain: swapchain.handle // possibly null
    };

    const uint[2] shared_queue_indices = [device.graphics.family, device.present.family];
    if (device.graphics.family != device.present.family) {
        ci.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
        ci.queueFamilyIndexCount = cast(uint) shared_queue_indices.length;
        ci.pQueueFamilyIndices = shared_queue_indices.ptr;
    }
    else
        ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;

    device.dispatch_table.CreateSwapchainKHR(ci, swapchain.handle);
    swapchain.properties = properties;

    device.log.info("Swapchain for surface %s created; %s images in %s mode", surface, properties.n_images, properties.present_mode);

    return ci.oldSwapchain;
}

void _update_swapchain_images(VulkanDevice device, VkSwapchainKHR swapchain, VkFormat format, ref VkImage[] images, ref VkImageView[] views) {
    uint count;
    device.dispatch_table.GetSwapchainImagesKHR(swapchain, count, null);
    resize_array(device.context.memory, images, count);
    device.dispatch_table.GetSwapchainImagesKHR(swapchain, count, images.ptr);

    foreach (view; views)
        device.dispatch_table.DestroyImageView(view);
    resize_array(device.context.memory, views, count);

    VkImageViewCreateInfo vci = {
        format: format,
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

    foreach (i, image; images) {
        vci.image = image;
        device.dispatch_table.CreateImageView(vci, views[i]);
    }
}

VkSurfaceFormatKHR _select(in VkSurfaceFormatKHR[] formats) {
    auto format = find!(f => f.format == VK_FORMAT_B8G8R8A8_SRGB && f.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)(formats);
    return format.length > 0 ? format[0] : formats[0];
}

VkPresentModeKHR _select(in VkPresentModeKHR[] modes, bool vsync) {
    if (vsync) {
        const mailbox = find(modes, VK_PRESENT_MODE_MAILBOX_KHR);
        if (mailbox.length > 0)
            return mailbox[0];
    }
    else {
        const immediate = find(modes, VK_PRESENT_MODE_IMMEDIATE_KHR);
        if (immediate.length > 0)
            return immediate[0];   
    }

    return VK_PRESENT_MODE_FIFO_KHR;
}

VkExtent2D _image_size(in VkSurfaceCapabilitiesKHR capabilities) {
    if (capabilities.currentExtent.width != uint.max)
        return capabilities.currentExtent;

    VkExtent2D result = {
        width: max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, capabilities.currentExtent.width)),
        height: max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, capabilities.currentExtent.height))
    };

    return result;
}

uint _num_images(in VkSurfaceCapabilitiesKHR capabilities) {
    // If we can have as many as we like, get 3 or more images
    if (capabilities.maxImageCount == 0) 
        return max(capabilities.minImageCount, num_preferred_swap_buffers);

    // If we can have at least 3 images, get as close to 3 images as possible
    if (num_preferred_swap_buffers <= capabilities.maxImageCount)
        return max(capabilities.minImageCount, num_preferred_swap_buffers);

    // Get as many images as we are allowed
    return capabilities.maxImageCount;
}
