shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tile_size = 2.0;
uniform float macro_scale = 0.07;
uniform float stripe_width = 2.5;
uniform float stripe_contrast = 0.14;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_size;
	float u = world_pos.x / (stripe_width * 2.0);
	float wave = abs(fract(u) * 2.0 - 1.0);
	float edge = fwidth(u) * 2.0;
	float band = smoothstep(0.5 - edge, 0.5 + edge, wave);
	float macro = texture(albedo_tex, uv * macro_scale).g;
	vec3 base = texture(albedo_tex, uv).rgb * tint * (0.8 + macro * 0.5);
	ALBEDO = base * (1.0 - stripe_contrast * band);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = texture(roughness_tex, uv).r;
}
