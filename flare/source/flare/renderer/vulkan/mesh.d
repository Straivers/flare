module flare.renderer.vulkan.mesh;

import flare.renderer.vulkan.api;
import flare.renderer.vulkan.buffer;
import flare.math.vector : float2, float3;

struct Vertex {
    float2 position;
    float3 colour;

    static immutable VkVertexInputBindingDescription binding_description = {
        binding: 0,
        stride: Vertex.sizeof,
        inputRate: VK_VERTEX_INPUT_RATE_VERTEX
    };

    static immutable VkVertexInputAttributeDescription[2] attribute_descriptions = [
        {
            binding: 0,
            location: 0,
            format: VK_FORMAT_R32G32_SFLOAT,
            offset: Vertex.position.offsetof,
        },
        {
            binding: 0,
            location: 1,
            format: VK_FORMAT_R32G32B32_SFLOAT,
            offset: Vertex.colour.offsetof,
        }
    ];
}

struct Mesh {
    Vertex[] vertices;
    ushort[] indices;
}

struct GpuMesh {
    BufferHandle vertices;
    BufferHandle indices;
    ushort num_indices;
}

void create_mesh_buffers(ref BufferManager buffers, in Mesh info, out GpuMesh mesh) {
    BufferAllocInfo[2] alloc_i = [{
        size: cast(uint) (info.vertices.length * Vertex.sizeof),
        type: BufferType.Vertex,
        transferable: Transferability.Receive
    }, {
        size: cast(uint) (info.indices.length * ushort.sizeof),
        type: BufferType.Index,
        transferable: Transferability.Receive
    }];

    BufferHandle[2] handles;
    buffers.create_buffers(alloc_i, handles);

    mesh.vertices = handles[0];
    mesh.indices = handles[1];
    mesh.num_indices = cast(ushort) info.indices.length;
}

void record_mesh_draw(DispatchTable* vk, VkCommandBuffer cmd, ref BufferManager buffers, ref GpuMesh mesh) {
    VkBuffer[1] v = [buffers.get(mesh.vertices).handle];
    VkDeviceSize[1] o = [buffers.get(mesh.vertices).offset];

    vk.CmdBindVertexBuffers(cmd, v, o);
    vk.CmdBindIndexBuffer(cmd, buffers.get(mesh.indices).handle, buffers.get(mesh.indices).offset, VK_INDEX_TYPE_UINT16);
    vk.CmdDrawIndexed(cmd, mesh.num_indices, 1, 0, 0, 0);
}
