module pipeline;

import flare.core.memory;
import flare.core.os.file;
import flare.vulkan;

VkPipeline create_graphics_pipeline(
    VulkanDevice device,
    ref Swapchain swapchain,
    VkShaderModule vert,
    VkShaderModule frag,
    VkVertexInputBindingDescription[] binding_descs,
    VkVertexInputAttributeDescription[] attrib_descs,
    VkPipelineLayout layout) {
    VkPipelineShaderStageCreateInfo[2] pipeline_stages = [{
        stage: VK_SHADER_STAGE_VERTEX_BIT,
        module_: vert,
        pName: "main",
    }, {
        stage: VK_SHADER_STAGE_FRAGMENT_BIT,
        module_: frag,
        pName: "main",
    }];

    VkPipelineVertexInputStateCreateInfo vertex_input = {
        vertexBindingDescriptionCount: 1,
        pVertexBindingDescriptions: binding_descs.ptr,
        vertexAttributeDescriptionCount: cast(uint) attrib_descs.length,
        pVertexAttributeDescriptions: attrib_descs.ptr
    };

    VkPipelineInputAssemblyStateCreateInfo input_assembly_info = {
        topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        primitiveRestartEnable: VK_FALSE,
    };

    VkViewport viewport = {
        x: 0,
        y: 0,
        width: swapchain.image_size.width,
        height: swapchain.image_size.height,
        minDepth: 0.0f,
        maxDepth: 1.0f,
    };

    VkRect2D scissor = {
        extent: swapchain.image_size
    };

    VkPipelineViewportStateCreateInfo viewport_state = {
        viewportCount:  1,
        pViewports:  &viewport,
        scissorCount:  1,
        pScissors:  &scissor,
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

    VkDynamicState[1] dynamic_states = [VK_DYNAMIC_STATE_VIEWPORT];
    VkPipelineDynamicStateCreateInfo dynamic_state = {
        dynamicStateCount: cast(uint) dynamic_states.length,
        pDynamicStates: dynamic_states.ptr
    };

    VkGraphicsPipelineCreateInfo[1] pipeline_info = [{
        stageCount: cast(uint) pipeline_stages.length,
        pStages: pipeline_stages.ptr,
        pVertexInputState: &vertex_input,
        pInputAssemblyState: &input_assembly_info,
        pViewportState: &viewport_state,
        pRasterizationState: &rasterizer,
        pMultisampleState: &multisample,
        pDepthStencilState: null,
        pColorBlendState: &color_blending,
        pDynamicState: &dynamic_state,
        layout: layout,
        renderPass: swapchain.render_pass,
        subpass: 0,
        basePipelineHandle: VK_NULL_HANDLE,
        basePipelineIndex: -1,
    }];

    VkPipeline[1] pipeline;
    device.dispatch_table.CreateGraphicsPipelines(VK_NULL_HANDLE, pipeline_info, pipeline);
    return pipeline[0];
}

VkPipelineLayout create_pipeline_layout(VulkanDevice device) {
    VkPipelineLayoutCreateInfo ci = {

    };

    VkPipelineLayout result;
    device.dispatch_table.CreatePipelineLayout(ci, result);
    return result;
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
    auto bytes = read_file(path, device.context.memory);
    auto shader = device.create_shader(bytes);
    device.context.memory.dispose(bytes);
    return shader;
}
