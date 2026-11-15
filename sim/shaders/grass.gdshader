shader_type spatial;

uniform vec3 color_a : source_color;
uniform vec3 color_b : source_color;
uniform float stripe_width = 2.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = world_pos.x / (stripe_width * 2.0);
	float wave = abs(fract(u) * 2.0 - 1.0);
	float edge = fwidth(u) * 2.0;
	ALBEDO = mix(color_a, color_b, smoothstep(0.5 - edge, 0.5 + edge, wave));
	ROUGHNESS = 0.95;
}
