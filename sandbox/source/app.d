module app;

import sandbox;
import flare.application;

void main() {
    FlareAppSettings settings = {
        name: "Flare Sandbox",
        main_window_width: 1920,
        main_window_height: 1080
    };

    // run_app!Sandbox(settings);
    run_app!Test(settings);
}

class Test : FlareApp {
    import flare.core.memory: AllocatorApi, BuddyAllocator, mib;
    import flare.vulkan : ContextOptions, init_vulkan, VulkanContext, VkVersion, VK_LAYER_KHRONOS_VALIDATION_NAME, SwapchainImage;
    import flare.vulkan_renderer.display_manager : DisplayId, VulkanDisplayManager, VulkanDisplayProperties, KeyCode, ButtonState;
    import std.stdio : writefln, writeln;

public:
    this(ref FlareAppSettings settings) {
        super(settings);
    }

    override void on_init() {
        ContextOptions options = {
            api_version: VkVersion(1, 2, 0),
            memory: new AllocatorApi!BuddyAllocator(new void[](16.mib)),
            parent_logger: &log,
            layers: [VK_LAYER_KHRONOS_VALIDATION_NAME],
            extensions: VulkanDisplayManager.required_instance_extensions
        };

        _display_manager = new VulkanDisplayManager(init_vulkan(options));

        {
            VulkanDisplayProperties display_properties = {
                display_properties: {
                    title: app_settings.name,
                    width: app_settings.main_window_width,
                    height: app_settings.main_window_height,
                    is_resizable: true,
                    callbacks: {
                        on_key: (src, key, state) nothrow {
                            if (key == KeyCode.Escape && state == ButtonState.Released)
                                src.manager.close(src.display_id);
                        },
                        on_resize: (src, width, height) nothrow {
                            debug writefln("Resizing window to (%s, %s)", width, height);
                        },
                        on_create: (src) nothrow {
                            debug writeln("Creating window");
                        },
                        on_destroy: (src) nothrow {
                            debug writeln("Destroying window");
                        }
                    }
                },
                on_swapchain_create: (src, swapchain) nothrow {
                    debug writefln("Creating new swapchain. ID = %s", swapchain.handle);
                },
                on_swapchain_destroy: (src, swapchain) nothrow {
                    debug writefln("Destroying swapchain. ID = %s", swapchain.handle);
                },
                on_swapchain_resize: (src, swapchain) nothrow {
                    debug writefln("Recreating swapchain. Id = %s", swapchain.handle);
                }
            };

            _display_id = _display_manager.create(display_properties);
        }
    }

    override void on_shutdown() {
        destroy(_display_manager);
    }

    override void run() {
        while (_display_manager.is_live(_display_id)) {
            _display_manager.process_events(false);

            if (_display_manager.is_close_requested(_display_id)) {
                _display_manager.destroy(_display_id);
            }
            else {
                SwapchainImage swapchain_image;
                _display_manager.get_next_image(_display_id);
                // auto device = _display_manager.device;

                // render_pass.write_commands(command_buffers[swapchain_image.index]);

                // wait_fence(device, swapchain_image.render_fence);

                // submit_buffer(device, device.graphics, command_buffers[swapchain_image.index], swapchain_image.render_fence);
            }
        }
    }

private:
    DisplayId _display_id;
    VulkanDisplayManager _display_manager;
}
