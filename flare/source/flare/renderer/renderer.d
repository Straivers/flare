module flare.renderer.renderer;

import flare.util.handle_pool;

enum swapchain_handle_name = "flare_swapchain_handle_id";
alias SwapchainId = Handle32!swapchain_handle_name;

interface Renderer {
    /**
     * Creates a new swapchain associated with a window.
     */
    SwapchainId create_swapchain(void*, bool vsync);

    /**
     * Destroys a swapchain. This function may cause the GPU to stall until the
     * swapchain's resources are no longer in use.
     */
    void destroy_swapchain(SwapchainId);

    /**
     * Resizes the swapchain.
     */
    void resize_swapchain(SwapchainId);

    /**
     * Causes the swapchain to display the currently rendered image.
     */
    void present_swapchain(SwapchainId);
}
