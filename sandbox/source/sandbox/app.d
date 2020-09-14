module sandbox.app;

import flare.core.logger;
import flare.platform.vulkan.api;

void main() {
    auto logger = Logger(LogLevel.All);
    logger.add_sink(new ConsoleLogger(true));

    auto vk = Vulkan(&logger);

    destroy(vk);
}
