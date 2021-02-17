module flare.vulkan.swapchain;

import flare.core.memory;
import flare.vulkan.commands;
import flare.vulkan.context;
import flare.vulkan.device;
import flare.vulkan.h;
import flare.vulkan.sync;

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

    /// Fences that are passed to vkQueueSubmit, and are signalled upon queue completion.
    VkFence[num_preferred_swap_buffers] render_fences;

    /// Semaphores that are signalled when a swapchain image is ready to be rendered to.
    VkSemaphore[num_preferred_swap_buffers] acquire_semaphores;
    
    /// Semaphores that are signalled when a swapchain image is ready to be presented.
    VkSemaphore[num_preferred_swap_buffers] present_semaphores;

    VkResult state;

    ubyte sync_object_index;
    ushort current_frame_index;
}

struct SwapchainImage {
    size_t index;

    VkImage handle;
    VkFormat format;
    VkImageView view;
    VkExtent2D image_size;

    VkFence render_fence;

    VkSemaphore acquire_semaphore;
    VkSemaphore present_semaphore;
}

void get_swapchain_properties(VulkanDevice device, VkSurfaceKHR surface, out SwapchainProperties result) {
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
    result.present_mode = _select(modes);
}

/**
 * Initializes a new swapchain.
 *
 * If a surface has no size (if the window is hidden), this function does nothing.
 */
void create_swapchain(VulkanDevice device, VkSurfaceKHR surface, in SwapchainProperties properties, out Swapchain swapchain) {
    assert(properties.image_size != VkExtent2D(), "It is invalid to create a 0-sized swapchain");

    swapchain.properties = properties;

    swapchain.handle = _create_swapchain(device, surface, properties, null);
    _get_swapchain_images(device, swapchain);

    foreach (i; 0 .. num_preferred_swap_buffers) {
        swapchain.render_fences[i] = create_fence(device, true);
        swapchain.acquire_semaphores[i] = create_semaphore(device);
        swapchain.present_semaphores[i] = create_semaphore(device);
    }

    device.context.logger.trace("Created swapchain (%sw, %sh) ID %s for surface %s.", swapchain.image_size.width, swapchain.image_size.height, swapchain.handle, surface);
}

/**
 * Recreates a swapchain.
 *
 * If the swapchain was not previously initialized (`create_swapchain()`
 * returned `false` due to a hidden window), `recreate_swapchain()` will create
 * a new swapchain.
 */
void resize_swapchain(VulkanDevice device, VkSurfaceKHR surface, in SwapchainProperties properties, ref Swapchain swapchain) {
    assert(swapchain.handle);
    assert(properties.image_size != VkExtent2D(), "It is invalid to attempt to resize a swapchain to (0, 0)!");

    wait_fences(device, true, ulong.max, swapchain.render_fences);

    Swapchain new_swapchain = {
        handle: _create_swapchain(device, surface, properties, swapchain.handle),
        properties: properties,
        render_fences: swapchain.render_fences,
        acquire_semaphores: swapchain.acquire_semaphores,
        present_semaphores: swapchain.present_semaphores
    };

    _free_swapchain_images(device, swapchain);
    device.dispatch_table.DestroySwapchainKHR(swapchain.handle);

    _get_swapchain_images(device, new_swapchain);

    device.context.logger.trace("Swapchain for surface %s has been recreated. It is now %s (%sw, %sh).", surface, new_swapchain.handle, properties.image_size.width, properties.image_size.height);

    swapchain = new_swapchain;
}

void destroy_swapchain(VulkanDevice device, ref Swapchain swapchain) {
    assert(swapchain.handle);

    wait_fences(device, true, ulong.max, swapchain.render_fences);

    foreach (i; 0 .. num_preferred_swap_buffers) {
        destroy_fence(device, swapchain.render_fences[i]);
        destroy_semaphore(device, swapchain.acquire_semaphores[i]);
        destroy_semaphore(device, swapchain.present_semaphores[i]);
    }

    _free_swapchain_images(device, swapchain);
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
void acquire_next_image(VulkanDevice device, Swapchain* swapchain, out SwapchainImage image) {
    assert(swapchain.handle);

    uint index;
    const err = device.dispatch_table.AcquireNextImageKHR(swapchain.handle, ulong.max, swapchain.acquire_semaphores[swapchain.sync_object_index], null, index);
    swapchain.state = err;

    swapchain.current_frame_index = cast(ushort) index;

    image.index = index;
    image.handle = swapchain.images[index];
    image.format = swapchain.format;
    image.view = swapchain.views[index];
    image.image_size = swapchain.image_size;

    image.render_fence = swapchain.render_fences[index];

    image.acquire_semaphore = swapchain.acquire_semaphores[swapchain.sync_object_index];
    image.present_semaphore = swapchain.present_semaphores[swapchain.sync_object_index];
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
bool swap_buffers(VulkanDevice device, Swapchain* swapchain) {
    uint index = swapchain.current_frame_index;
    VkPresentInfoKHR pi = {
        waitSemaphoreCount: 1,
        pWaitSemaphores: &swapchain.present_semaphores[swapchain.sync_object_index],
        swapchainCount: 1,
        pSwapchains: &swapchain.handle,
        pImageIndices: &index,
        pResults: null,
    };

    const err = device.dispatch_table.QueuePresentKHR(device.graphics, pi);
    
    swapchain.sync_object_index = (swapchain.sync_object_index + 1) % num_preferred_swap_buffers;

    return err == VK_SUCCESS;
}

private:
VkSwapchainKHR _create_swapchain(VulkanDevice device, VkSurfaceKHR surface, in SwapchainProperties properties, VkSwapchainKHR old) {
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
    device.dispatch_table.CreateSwapchainKHR(ci, swapchain);
    return swapchain;
}

void _get_swapchain_images(VulkanDevice device, ref Swapchain swapchain) {
    uint count;
    device.dispatch_table.GetSwapchainImagesKHR(swapchain.handle, count, null);
    swapchain.images = device.context.memory.make_array!VkImage(count);
    device.dispatch_table.GetSwapchainImagesKHR(swapchain.handle, count, swapchain.images.ptr);

    swapchain.views = device.context.memory.make_array!VkImageView(count);
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

        device.dispatch_table.CreateImageView(vci, swapchain.views[i]);
    }
}

void _free_swapchain_images(VulkanDevice device, ref Swapchain swapchain) {
    foreach (i; 0 .. swapchain.images.length)
        device.dispatch_table.DestroyImageView(swapchain.views[i]);

    device.context.memory.dispose(swapchain.views);
    device.context.memory.dispose(swapchain.images);
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

    // If we can have as many as we like, get 3 or more images
    if (capabilities.maxImageCount == 0) 
        return max(capabilities.minImageCount, num_preferred_swap_buffers);

    // If we can have at least 3 images, get as close to 3 images as possible
    if (num_preferred_swap_buffers <= capabilities.maxImageCount)
        return max(capabilities.minImageCount, num_preferred_swap_buffers);

    // Get as many images as we are allowed
    return capabilities.maxImageCount;
}
