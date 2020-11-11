/**
 ```D
 Vulkan.load();

 auto instance_layers = Vulkan.get_instance_layers();
 auto instance_extensions = Vulkan.get_instance_extensions();

 // ... check layers and extensions ...

 auto vk = Vulkan.create_instance(options);
 auto gpus = vk.get_physical_devices();

 // ... filter gpus for required features ...

 auto device = vk.create_device(gpu);

 Vulkan.unload();
 ```
 */
module flare.vulkan.api;

public import flare.vulkan.base;
public import flare.vulkan.devices;
public import flare.vulkan.instance;
public import flare.vulkan.surfaces;
