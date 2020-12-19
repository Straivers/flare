module flare.renderer.renderer;

struct SwapchainId {
    ulong value;
}

interface Renderer {
    import flare.core.os.types: OsWindow;

    enum max_swapchains = 64;

nothrow:
    /**
     * Creates a new swapchain associated with a window. The window is expected
     * to outlive the swapchain.
     */
    SwapchainId create_swapchain(OsWindow);

    /**
     * Destroys a swapchain. This function may cause the GPU to stall until the
     * swapchain's resources are no longer in use.
     */
    void destroy(SwapchainId);

    /**
     * Resizes the swapchain.
     */
    void resize(SwapchainId, ushort width, ushort height);

    /**
     * Causes the swapchain to display switch out the current image for a
     * freshly rendered one.
     */
    void swap_buffers(SwapchainId);
}
