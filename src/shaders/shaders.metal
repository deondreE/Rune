#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant float2& viewport_size [[buffer(1)]]) {
    VertexOut out;
    // Map pixels to clip space (-1 to 1)
    float2 clip_space = (in.position / viewport_size) * 2.0 - 1.0;
    out.position = float4(clip_space.x, -clip_space.y, 0.0, 1.0);
    out.uv = in.uv;
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                               texture2d<float> font_texture [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    // FreeType gives us a grayscale mask, use it as alpha
    float mask = font_texture.sample(s, in.uv).r;
    return float4(in.color.rgb, in.color.a * mask);
}