module mem.buffer;

import flare.vulkan;
import mem.device;

enum BufferType : ubyte {
    Index,
    Vertex,
    Uniform,
}

// struct DeviceBufferSlice {
//     DeviceMemory alloc_id;
//     VkBuffer handle;
//     uint offset;
//     uint size;

//     // dfmt off
//     DeviceBufferSlice opIndex() { return this; }
//     uint opDollar() { return size; }
//     // dfmt on

//     DeviceBufferSlice opSlice(uint lo, uint hi) {
//         assert(handle && lo < hi && offset + hi <= size);
//         return DeviceBufferSlice(alloc_id, handle, offset + lo, hi - lo);
//     }
// }

// DeviceBufferSlice allocate_vertex_buffer(T)(ref DeviceMemoryAllocator allocator, DeviceHeap heap, T[] buffer_data) {
//     VkBufferCreateInfo buffer_ci = {
//         size: size,
//         usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
//         sharingMode: VK_SHARING_MODE_EXCLUSIVE
//     };

//     if (heap == DeviceHeap.Readback)
//         buffer_ci.usage |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;

//     // create buffer

//     // do copy???
// }

// DeviceBufferSlice allocate_buffer(ref DeviceMemoryAllocator allocator, DeviceHeap heap, size_t size, VkBufferUsageFlags usage_flags) {
//     VkBufferCreateInfo buffer_ci = {
//         size: size,
//         usage: usage_flags,
//         sharingMode: VK_SHARING_MODE_EXCLUSIVE
//     };

//     DeviceBufferSlice buffer;
//     allocator.device.dispatch_table.CreateBuffer(buffer_ci, buffer.handle);

//     VkMemoryRequirements reqs;
//     allocator.device.dispatch_table.GetBufferMemoryRequirements(buffer.handle, reqs);

//     DeviceAllocInfo* alloc_info;
//     buffer.alloc_id = allocator.allocate(reqs, heap, alloc_info);

//     allocator.device.dispatch_table.BindBufferMemory(buffer.handle, alloc_info.handle, alloc_info.offset);

//     return buffer;
// }
