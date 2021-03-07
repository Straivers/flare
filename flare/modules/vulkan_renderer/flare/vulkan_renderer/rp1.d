module flare.vulkan_renderer.rp1;

import flare.core.memory;
import flare.vulkan;

nothrow:

struct AttachmentSpec {
    VkFormat format;
    float[4] clear_color;
}

struct RenderPassSpec {
    AttachmentSpec swapchain_attachment;

    VkShaderModule vertex_shader;
    VkShaderModule fragment_shader;

    VkVertexInputBindingDescription bindings;
    VkVertexInputAttributeDescription[] attributes;
}

struct FrameResources {
    VkFence fence;
    VkSemaphore begin_semaphore;
    VkSemaphore done_semaphore;
}

struct RenderPass1 {
    VkRenderPass handle;

    AttachmentSpec swapchain_attachment;

    VkShaderModule vertex_shader;
    VkShaderModule fragment_shader;

    VkPipelineLayout layout;
    VkPipeline pipeline;

    VkVertexInputBindingDescription bindings;
    VkVertexInputAttributeDescription[] attributes;
}

void create_renderpass_1(VulkanDevice device, ref RenderPassSpec spec, out RenderPass1 renderpass) {
    auto tmp = scoped_arena(device.context.memory);

    {
        renderpass.swapchain_attachment = spec.swapchain_attachment;
    }
    {
        VkAttachmentReference[1] references = [{
            attachment : 0,
            layout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        }];

        VkSubpassDescription subpass = {
            pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
            colorAttachmentCount: cast(uint) references.length,
            pColorAttachments: &references[0]
        };

        VkAttachmentDescription[1] attachments = [{
            format          : spec.swapchain_attachment.format,
            samples         : VK_SAMPLE_COUNT_1_BIT,
            loadOp          : VK_ATTACHMENT_LOAD_OP_CLEAR,
            storeOp         : VK_ATTACHMENT_STORE_OP_STORE,
            stencilLoadOp   : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            stencilStoreOp  : VK_ATTACHMENT_STORE_OP_DONT_CARE,
            initialLayout   : VK_IMAGE_LAYOUT_UNDEFINED,
            finalLayout     : VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        }];

        VkSubpassDependency dependency = {
            srcSubpass: VK_SUBPASS_EXTERNAL,
            srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
        };

        VkRenderPassCreateInfo renderpass_ci = {
            attachmentCount: cast(uint) attachments.length,
            pAttachments: &attachments[0],
            subpassCount: 1,
            pSubpasses: &subpass,
            dependencyCount: 1,
            pDependencies: &dependency
        };

        device.dispatch_table.CreateRenderPass(renderpass_ci, renderpass.handle);
    }
    {
        renderpass.vertex_shader = spec.vertex_shader;
        renderpass.fragment_shader = spec.fragment_shader;
    }
    {
        VkPipelineLayoutCreateInfo layout_ci = {};
        device.dispatch_table.CreatePipelineLayout(layout_ci, renderpass.layout);
    }
    {
        VkPipelineShaderStageCreateInfo[2] shader_stages = [{
            stage: VK_SHADER_STAGE_VERTEX_BIT,
            module_: renderpass.vertex_shader,
            pName: "main"
        }, {
            stage: VK_SHADER_STAGE_FRAGMENT_BIT,
            module_: renderpass.fragment_shader,
            pName: "main"
        }];

        VkPipelineVertexInputStateCreateInfo vertex_input = {
            vertexBindingDescriptionCount: 1,
            pVertexBindingDescriptions: &spec.bindings,
            vertexAttributeDescriptionCount: cast(uint) spec.attributes.length,
            pVertexAttributeDescriptions: spec.attributes.ptr
        };

        VkPipelineInputAssemblyStateCreateInfo input_assembly_info = {
            topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable: VK_FALSE,
        };

        VkPipelineViewportStateCreateInfo viewport_state = {
            viewportCount:  1,
            scissorCount:  1,
        };

        VkPipelineRasterizationStateCreateInfo rasterizer = {
            // depthClampEnable: VK_TRUE,
            depthBiasClamp: 0.0,
            rasterizerDiscardEnable: VK_FALSE,
            polygonMode: VK_POLYGON_MODE_FILL,
            lineWidth: 1.0f,
            cullMode: VK_CULL_MODE_BACK_BIT,
            frontFace: VK_FRONT_FACE_CLOCKWISE,
            depthBiasEnable: VK_FALSE,
        };

        VkPipelineMultisampleStateCreateInfo multisample = {
            sampleShadingEnable: VK_FALSE,
            rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
            minSampleShading: 1.0f,
        };

        VkPipelineColorBlendAttachmentState color_blend_attachment = {
            colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
            blendEnable: VK_FALSE,
            srcColorBlendFactor: VK_BLEND_FACTOR_ONE,
        };

        VkPipelineColorBlendStateCreateInfo color_blending = {
            logicOpEnable: VK_FALSE,
            attachmentCount: 1,
            pAttachments: &color_blend_attachment
        };

        
        VkDynamicState[2] dynamic_states = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR];
        VkPipelineDynamicStateCreateInfo dynamic_state = {
            dynamicStateCount: cast(uint) dynamic_states.length,
            pDynamicStates: dynamic_states.ptr
        };

        VkGraphicsPipelineCreateInfo[1] pipeline_info = [{
            stageCount: cast(uint) shader_stages.length,
            pStages: &shader_stages[0],
            pVertexInputState: &vertex_input,
            pInputAssemblyState: &input_assembly_info,
            pViewportState: &viewport_state,
            pRasterizationState: &rasterizer,
            pMultisampleState: &multisample,
            pDepthStencilState: null,
            pColorBlendState: &color_blending,
            pDynamicState: &dynamic_state,
            layout: renderpass.layout,
            renderPass: renderpass.handle,
            subpass: 0,
            basePipelineHandle: VK_NULL_HANDLE,
            basePipelineIndex: -1,
        }];

        VkPipeline[1] pipeline;
        device.dispatch_table.CreateGraphicsPipelines(null, pipeline_info, pipeline);
        renderpass.pipeline = pipeline[0];
    }

    renderpass.bindings = spec.bindings;
    renderpass.attributes = device.context.memory.make_array!VkVertexInputAttributeDescription(spec.attributes.length);
    renderpass.attributes[] = spec.attributes;
}

void destroy_renderpass(VulkanDevice device, ref RenderPass1 renderpass) {
    with (device.dispatch_table) {
        DestroyRenderPass(renderpass.handle);

        DestroyPipeline(renderpass.pipeline);
        DestroyPipelineLayout(renderpass.layout);
    }

    device.context.memory.dispose(renderpass.attributes);
    renderpass = RenderPass1();
}

VkShaderModule create_shader(VulkanDevice device, ubyte[] data) {
    VkShaderModuleCreateInfo sci = {
        codeSize: data.length,
        pCode: cast(uint*) data.ptr
    };

    VkShaderModule shader;
    device.dispatch_table.CreateShaderModule(sci, shader);
    return shader;
}

VkShaderModule load_shader(VulkanDevice device, string path) {
    import flare.core.os.file: read_file;

    auto bytes = read_file(path, device.context.memory);
    auto shader = device.create_shader(bytes);
    device.context.memory.dispose(bytes);
    return shader;
}

void record_preamble(VulkanDevice device, ref RenderPass1 render_pass, VkCommandBuffer cmd, VkFramebuffer fb, VkExtent2D viewport_size) nothrow {
    auto viewport_rect = VkRect2D(VkOffset2D(0, 0), VkExtent2D(viewport_size.width, viewport_size.height));

    with (device.dispatch_table) {
        {
            VkCommandBufferBeginInfo begin_i;
            BeginCommandBuffer(cmd, begin_i);
        }
        {
            VkViewport viewport = {
                x: 0,
                y: 0,
                width: viewport_size.width,
                height: viewport_size.height,
                minDepth: 0,
                maxDepth: 1
            };
            CmdSetViewport(cmd, viewport);
        }
        {
            CmdSetScissor(cmd, viewport_rect);
        }
        {
            VkClearValue clear_color;
            clear_color.color.float32 = render_pass.swapchain_attachment.clear_color;

            VkRenderPassBeginInfo render_pass_bi = {
                renderPass: render_pass.handle,
                framebuffer: fb,
                renderArea: viewport_rect,
                clearValueCount: 1,
                pClearValues: &clear_color
            };

            CmdBeginRenderPass(cmd, render_pass_bi, VK_SUBPASS_CONTENTS_INLINE);
        }

        CmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, render_pass.pipeline);
    }
}

void record_postamble(VulkanDevice device, ref RenderPass1 render_pass, VkCommandBuffer cmd) nothrow {
    auto vk = device.dispatch_table;
    vk.CmdEndRenderPass(cmd);
    vk.EndCommandBuffer(cmd);
}
