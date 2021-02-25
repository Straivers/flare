module mesh;

import mem.buffer;
import mem.device;
/+
import flare.core.math.vector : float2, float3;
import flare.core.handle : Handle32, HandlePool;
import flare.vulkan;

struct MeshInfo {
    struct Vertex {
        float2 position;
        float3 colour;

        immutable VkVertexInputBindingDescription binding_description = {
            binding: 0,
            stride: Vertex.sizeof,
            inputRate: VK_VERTEX_INPUT_RATE_VERTEX
        };

        immutable VkVertexInputAttributeDescription[2] attribute_descriptions = [
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

public:
    Vertex[] vertices;
    ushort indices;
    DeviceHeap heap;
}

enum mesh_handle_name = "vulkan_static_mesh_handle";
alias MeshId = Handle32!mesh_handle_name;

struct Mesh {
    DeviceMemory vertices;
    DeviceMemory indices;
    uint num_indices;
}

struct ResourceManager {
    MeshId create_mesh(ref MeshInfo mesh_i) {
        // check device local budget
        // if device has space
            // create buffers on device
            // arrange copy
        // return id
        assert(0);
    }

    Mesh* get(MeshId handle) {
        // automatically marks mesh as used this frame
        assert(0);
    }

private:
    struct MeshData {
        Mesh mesh;
        // ... other data
    }

    alias MeshPool = HandlePool!(MeshData, mesh_handle_name);

    MeshPool _static_meshes;
    // DeviceMemory _device_memory;
}
+/