module flare.vulkan.swapchain;

import flare.core.memory.temp;
import flare.vulkan.context;
import flare.vulkan.device;
import flare.vulkan.h;

struct Swapchain {
    VkExtent2D size;
    VkPresentModeKHR mode;
    VkSurfaceFormatKHR format;

    VulkanDevice device;
    VkSurfaceKHR surface;
    VkSwapchainKHR swapchain;

    VkImage[] images;
    VkImageView[] image_views;

    @disable this(this);

    ~this() {
        if (swapchain) {
            foreach (view; image_views)
                device.d_destroy_image_view(view);
            device.context.memory.free(image_views);

            device.context.memory.free(images);

            device.d_destroy_swapchain(swapchain);
            vkDestroySurfaceKHR(device.context.instance, surface, null);

            device = null;
            surface = null;
            swapchain = null;
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

void create_swapchain(VulkanDevice device, VkSurfaceKHR surface, VkExtent2D window_size, out Swapchain result) {
    auto mem = TempAllocator(device.context.memory);

    SwapchainSupport swapchain_info;
    load_swapchain_support(device.gpu.device, surface, mem, swapchain_info);
    // TODO: device.gpu.device is ugly. fix?

    auto size = swapchain_size(swapchain_info.capabilities, window_size);
    auto mode = select(swapchain_info.modes);
    auto format = select(swapchain_info.formats);

    VkSwapchainCreateInfoKHR sci = {
        surface: surface,
        imageFormat: format.format,
        imageColorSpace: format.colorSpace,
        imageArrayLayers: 1,
        minImageCount: num_images(swapchain_info.capabilities),
        imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        imageExtent: size,
        presentMode: mode,
        preTransform: VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
        compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        clipped: VK_TRUE
    };

    if (device.graphics_family != device.present_family) {
        auto indices = mem.alloc_array!uint(2);
        indices[0] = device.graphics_family;
        indices[1] = device.present_family;

        sci.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
        sci.queueFamilyIndexCount = 2;
        sci.pQueueFamilyIndices = indices.ptr;
    }
    else {
        sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    }

    result.size = size;
    result.mode = mode;
    result.format = format;
    result.device = device;
    result.surface = surface;
    device.d_create_swapchain(&sci, &result.swapchain);

    uint n_images;
    device.d_get_swapchain_images(result.swapchain, &n_images, null);
    assert(n_images);
    result.images = device.context.memory.alloc_array!VkImage(n_images);
    device.d_get_swapchain_images(result.swapchain, &n_images, result.images.ptr);

    result.image_views = device.context.memory.alloc_array!VkImageView(n_images);

    foreach (i; 0 .. n_images) {
        VkImageViewCreateInfo ivci;
        ivci.image = result.images[i];
        ivci.format = result.format.format;
        ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
        
        ivci.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;

        ivci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        ivci.subresourceRange.baseArrayLayer = 0;
        ivci.subresourceRange.baseMipLevel = 0;
        ivci.subresourceRange.levelCount = 1;
        ivci.subresourceRange.layerCount = 1;

        device.d_create_image_view(&ivci, &result.image_views[i]);
    }
}

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

private:

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
    auto count = capabilities.minImageCount + 1;

    if (capabilities.maxImageCount && count > capabilities.maxImageCount)
        return capabilities.maxImageCount;
    return count;
}
