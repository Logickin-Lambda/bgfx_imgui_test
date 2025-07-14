# Now, Here Is The Hard Part
This should be the one of the if not the most difficult part of building a gui application, trying to load imgui into a bgfx project with zig. In theory, by reading the original C++ example, it is possible and in fact, their official examples do use imgui to control their shaders program, but loading imgui into bgfx in a zig program seems like a rarity, and there are not much examples taking both of the libraries into a single zig project in action.

Thus, this will take probably take quite a lot of time, but unlike SuperBible sb7object.h, the current tools I used are not some random in-house libraries that no one really used with questionable quality, but a widely adopted, comprehensive libraries which are used in many games and production tools, so it worths the time to figure them out.

Hopefully, by this week, I will have my first imgui window loaded into a window, starting a whole new page of my adventure.