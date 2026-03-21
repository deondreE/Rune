#version 450

layout (push_constant) uniform PushConstants {
    vec2 screen_size;
} pc;

layout (location = 0) in vec2 in_pos;
layout (location = 1) in vec2 in_uv;
layout (location = 2) in vec4 in_color;

layout (location = 0) out vec2 frag_uv;
layout (location = 1) out vec4 frag_color;

void main() {
    vec2 ndc = (in_pos / pc.screen_size) * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, ndc.y, 0.0, 1.0);
    frag_uv = in_uv;
    frag_color = in_color;
}
