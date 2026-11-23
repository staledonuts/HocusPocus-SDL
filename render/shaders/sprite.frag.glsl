#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec2 v_local;
layout(location = 2) flat in vec4 v_params;

layout(location = 0) out vec4 frag_color;

layout(set = 2, binding = 0) uniform sampler2D u_tex;

void main() {
    int mode = int(v_params.x + 0.5);

    if (mode == 1) {
        frag_color = vec4(v_params.y / 255.0, 1.0, 0.0, 1.0);
        return;
    }

    vec2 s = texture(u_tex, v_uv).rg;
    if (s.g < 0.5) {
        discard;
    }

    if (mode == 2) {
        frag_color = vec4(v_params.y / 255.0, 1.0, 0.0, 1.0);
    } else if (mode == 3) {
        float row = clamp(floor(v_local.y * 8.0), 0.0, 7.0);
        frag_color = vec4((v_params.y + row) / 255.0, 1.0, 0.0, 1.0);
    } else {
        frag_color = vec4(s.r, 1.0, 0.0, 1.0);
    }
}
