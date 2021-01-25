module flare.vulkan_renderer.frame;

// import flare.core.memory.temp;
import flare.core.memory;
import flare.vulkan;

struct FramebufferAttachmentSpec {
    VkImageView image_view;
}

struct FrameSpec {
    VkRenderPass render_pass;
    VkExtent2D framebuffer_size;
    FramebufferAttachmentSpec[] framebuffer_attachments;

    VkCommandBuffer graphics_commands;
}

struct Frame {
    uint index;
    VkExtent2D image_size;
    VkFramebuffer framebuffer;
    VkImageView[] framebuffer_attachments;

    VkFence frame_complete_fence;
    VkSemaphore image_acquire;
    VkSemaphore render_complete;

    VkRenderPass render_pass;
    VkCommandBuffer graphics_commands;

    void resize(VulkanDevice device, VkExtent2D new_size) nothrow {
        device.dispatch_table.DestroyFramebuffer(framebuffer);

        VkFramebufferCreateInfo framebuffer_ci = {
            renderPass: render_pass,
            attachmentCount: cast(uint) framebuffer_attachments.length,
            pAttachments: framebuffer_attachments.ptr,
            width: new_size.width,
            height: new_size.height,
            layers: 1
        };

        device.dispatch_table.CreateFramebuffer(framebuffer_ci, framebuffer);
        image_size = new_size;
    }
}

void init_frame(VulkanDevice device, ref FrameSpec spec, out Frame frame) nothrow {
    // get attachment info
    frame.framebuffer_attachments = device.context.memory.make_array!VkImageView(spec.framebuffer_attachments.length);
    
    foreach (i, ref attachment; spec.framebuffer_attachments)
        frame.framebuffer_attachments[i] = attachment.image_view;

    assert(frame.framebuffer_attachments.length == 1, "Handling multiple attachments not implemented");

    // create framebuffer
    VkFramebufferCreateInfo framebuffer_ci = {
        renderPass: spec.render_pass,
        attachmentCount: cast(uint) frame.framebuffer_attachments.length,
        pAttachments: frame.framebuffer_attachments.ptr,
        width: spec.framebuffer_size.width,
        height: spec.framebuffer_size.height,
        layers: 1
    };

    device.dispatch_table.CreateFramebuffer(framebuffer_ci, frame.framebuffer);

    frame.frame_complete_fence = device.create_fence(true);
    frame.image_acquire = device.create_semaphore();
    frame.render_complete = device.create_semaphore();
    frame.render_pass = spec.render_pass;
    frame.graphics_commands = spec.graphics_commands;
}

void destroy_frame(VulkanDevice device, ref Frame frame) nothrow {
    wait_fence(device, frame.frame_complete_fence);

    destroy_semaphore(device, frame.image_acquire);
    destroy_semaphore(device, frame.render_complete);
    destroy_fence(device, frame.frame_complete_fence);
    device.dispatch_table.DestroyFramebuffer(frame.framebuffer);
    device.context.memory.dispose(frame.framebuffer_attachments);
}

void resize_frame(VulkanDevice device, ref Frame frame, VkExtent2D size) nothrow {
    device.dispatch_table.DestroyFramebuffer(frame.framebuffer);

    VkFramebufferCreateInfo framebuffer_ci = {
        renderPass: frame.render_pass,
        attachmentCount: cast(uint) frame.framebuffer_attachments.length,
        pAttachments: frame.framebuffer_attachments.ptr,
        width: size.width,
        height: size.height,
        layers: 1
    };

    device.dispatch_table.CreateFramebuffer(framebuffer_ci, frame.framebuffer);
    frame.image_size = size;
}
