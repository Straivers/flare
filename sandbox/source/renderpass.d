module renderpass;

import flare.core.memory;
import flare.vulkan;

struct AttachmentSpec {
    VkFormat format;
    bool swapchain_attachment;
}

struct RenderPassSpec {
    AttachmentSpec[] attachments;

    ubyte[] vertex_shader_blob;
    ubyte[] fragment_shader_blob;

    VkVertexInputBindingDescription bindings;
    VkVertexInputAttributeDescription[] attributes;
}

struct VirtualFrame {
    VkFence fence;
    VkSempahore begin_semaphore;
    VkSemaphore done_sempaphore;
    VkCommandBuffer command_buffer;

    VkFramebuffer framebuffer;
    VkFormat framebuffer_format;
}

struct RenderPass1 {
    VkRenderPass handle;

    AttachmentSpec[] attachments;

    VkShaderModule vertex_shader;
    VkShaderModule fragment_shader;

    VkPipelineLayout layout;
    VkPipeline pipeline;

    VkVertexInputBindingDescription bindings;
    VkVertexInputAttributeDescription[] attributes;
}

void create_renderpass_1(VulkanDevice device, ref RenderPassSpec spec, out RenderPass1 renderpass) {
    auto tmp = temp_arena(device.context.memory);

    {
        auto references = tmp.make_array!VkAttachmentReference(spec.attachments.length);
        foreach (i, ref reference; references) {
            reference.attachment = i;
            reference.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        }

        VkSubpassDescription subpass = {
            pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
            colorAttachmentCount: cast(uint) references.length,
            pColorAttachments: &references[0]
        };

        auto attachments = tmp.make_array!VkAttachmentDescription(spec.attachments.length);
        foreach (i, ref attachment; attachments) with (attachment) {
            format          = spec.attachments[i].format;
            samples         = VK_SAMPLE_COUNT_1_BIT;
            loadOp          = VK_ATTACHMENT_LOAD_OP_CLEAR;
            storeOp         = VK_ATTACHMENT_STORE_OP_STORE;
            stencilLoadOp   = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
            stencilStoreOp  = VK_ATTACHMENT_STORE_OP_DONT_CARE;
            initialLayout   = VK_IMAGE_LAYOUT_UNDEFINED;
            finalLayout     = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        }

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
        VkShaderModuleCreateInfo vertex_ci = {
            codeSize: spec.vertex_shader_blob.length,
            pCode: cast(uint*) spec.vertex_shader_blob.ptr
        };

        device.dispatch_table.CreateShaderModule(vertex_ci, renderpass.vertex_shader);
    }
    {
        VkShaderModuleCreateInfo fragment_ci = {
            codeSize: spec.fragment_shader_blob.length,
            pCode: cast(uint*) spec.fragment_shader_blob.ptr
        };

        device.dispatch_table.CreateShaderModule(fragment_ci, renderpass.fragment_shader);
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
            pVertexBindingDescriptions: spec.bindings.ptr,
            vertexAttributeDescriptionCount: cast(uint) spec.attributes.length,
            pVertexAttributeDescriptions: spec.attributes.ptr
        };

        VkPipelineInputAssemblyStateCreateInfo input_assembly_info = {
            topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable: VK_FALSE,
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
            stageCount: cast(uint) pipeline_stages.length,
            pStages: pipeline_stages.ptr,
            pVertexInputState: &vertex_input,
            pInputAssemblyState: &input_assembly_info,
            pViewportState: null,
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

        device.dispatch_table.CreateGraphicsPipelines(null, pipeline_info, renderpass.pipeline);
    }

    renderpass.bindings = spec.bindings;
    renderpass.attributes = device.context.memory.make_array!VkVertexInputAttributeDescription(spec.attributes.length);
    renderpass.attributes[] = spec.attributes;
}

void destroy_renderpass(VulkanDevice device, ref RenderPass1 renderpass) {
    with (device.dispatch_table) {
        DestroyRenderPass(renderpass.handle);

        DestroyShaderModule(renderpass.vertex_shader);
        DestroyShaderModule(renderpass.fragment_shader);

        DestroyPipeline(renderpass.pipeline);
        DestroyPipelineLayout(renderpass.layout);
    }

    device.context.memory.dispose(renderpass.attributes);
}
