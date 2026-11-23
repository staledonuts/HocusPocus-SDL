#version 450

struct QuadInstance {
    vec4 dst_rect;
    vec4 uv_rect;
    vec4 params;
};

layout(std430, set = 0, binding = 0) readonly buffer QuadBuffer {
    QuadInstance quads[];
};

layout(std140, set = 1, binding = 0) uniform SceneUniforms {
    vec4 screen_size;
};

layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec2 v_local;
layout(location = 2) flat out vec4 v_params;

const vec2 CORNERS[6] = vec2[6](
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0),
    vec2(0.0, 0.0),
    vec2(1.0, 1.0),
    vec2(0.0, 1.0)
);

void main() {
    QuadInstance q = quads[gl_InstanceIndex];
    vec2 corner = CORNERS[gl_VertexIndex];

    vec2 px = q.dst_rect.xy + corner * q.dst_rect.zw;
    vec2 ndc = vec2(
        (px.x / screen_size.x) * 2.0 - 1.0,
        1.0 - (px.y / screen_size.y) * 2.0
    );

    gl_Position = vec4(ndc, 0.0, 1.0);
    v_uv = mix(q.uv_rect.xy, q.uv_rect.zw, corner);
    v_local = corner;
    v_params = q.params;
}
