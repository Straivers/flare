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
    VkExtent2D image_size;
    VkFramebuffer framebuffer;
    VkImageView[] framebuffer_attachments;

    VkFence frame_complete_fence;
    VkSemaphore image_acquire;
    VkSemaphore render_complete;

    VkCommandBuffer graphics_commands;
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

    frame.image_size = spec.framebuffer_size;
    frame.frame_complete_fence = device.create_fence(true);
    frame.image_acquire = device.create_semaphore();
    frame.render_complete = device.create_semaphore();
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

void resize_frame(VulkanDevice device, ref Frame frame, VkExtent2D size, FramebufferAttachmentSpec[] attachments, VkRenderPass render_pass) nothrow {
    device.dispatch_table.DestroyFramebuffer(frame.framebuffer);

    assert(frame.framebuffer_attachments.length == attachments.length, "resize_frame() is not the place to change attachments!");

    foreach (i, ref attachment; attachments)
        frame.framebuffer_attachments[i] = attachment.image_view;

    VkFramebufferCreateInfo framebuffer_ci = {
        renderPass: render_pass,
        attachmentCount: cast(uint) frame.framebuffer_attachments.length,
        pAttachments: frame.framebuffer_attachments.ptr,
        width: size.width,
        height: size.height,
        layers: 1
    };

    device.dispatch_table.CreateFramebuffer(framebuffer_ci, frame.framebuffer);
    frame.image_size = size;
}
