#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_color;

layout(set = 2, binding = 0) uniform sampler2D u_screen;
layout(set = 2, binding = 1) uniform sampler2D u_palette;

layout(std140, set = 3, binding = 0) uniform PresentUniforms {
    vec4 fade_color;
    vec4 video_opts;
};

void main() {
    vec2 idx_sample = texture(u_screen, v_uv).rg;
    int pal_index = clamp(int(round(idx_sample.r * 255.0)), 0, 255);
    vec3 rgb = texelFetch(u_palette, ivec2(pal_index, 0), 0).rgb;

    if (video_opts.x > 0.001) {
        float wave = 0.5 - 0.5 * cos(v_uv.y * video_opts.y * 6.2831853);
        rgb *= 1.0 - video_opts.x * wave;
    }

    rgb = mix(rgb, fade_color.rgb, clamp(fade_color.a, 0.0, 1.0));
    frag_color = vec4(rgb, 1.0);
}
