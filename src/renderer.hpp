#pragma once
#include "shared.hpp"
#include <vector>
#include <string>

enum class RenderBackend {
    Metal,
    DirectX11,
    Vulkan
};

struct RenderConfig {
    IColor4 clear_color = {32, 32, 32, 255};
    bool vsync = true;
};

class IRenderer {
public:
    virtual ~IRenderer() = default;

    // Lifecycle: Uses the handle already stored in the Editor
    virtual bool initialize(WindowHandle handle, RenderConfig config) = 0;
    virtual void shutdown() = 0;

    // High-Level Commands
    virtual void begin_frame() = 0;
    virtual void end_frame() = 0;

    // Logic-to-Native Drawing
    virtual void draw_rect(IVec2 pos, IVec2 size, IColor4 color) = 0;
    virtual void draw_text(const std::string& text, IVec2 pos, float32 size, IColor4 color) = 0;

    // Font metrics — useful for cursor positioning, line layout, etc.
    virtual float line_height() const = 0;
    virtual float space_width() const = 0;
    virtual void  set_tab_width(int spaces) = 0;

    virtual void on_resize(u32 width, u32 height) = 0;
    virtual float32 get_text_width(const std::string& text, float32 size) = 0;
};

// Global Factory
IRenderer* create_renderer(RenderBackend backend);