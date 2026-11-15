shader_type spatial;

uniform vec3 seat_color : source_color;
uniform float seat_width = 0.55;
uniform float row_depth = 0.8;
uniform float occupancy = 0.85;

varying vec3 local_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 grid = vec2(local_pos.x / seat_width, local_pos.z / row_depth);
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	float seated = step(hash(cell), occupancy);
	vec3 hue = 0.5 + 0.5 * cos(6.28318 * (hash(cell + 17.0) + vec3(0.0, 0.33, 0.67)));
	vec3 shirt = mix(vec3(hash(cell + 5.0)), hue, 0.35) * 0.75;
	float person = 1.0 - smoothstep(0.28, 0.38, length(f - vec2(0.5, 0.55)));
	float riser = smoothstep(0.0, 0.12, f.y);
	ALBEDO = mix(seat_color * mix(0.6, 1.0, riser), shirt, seated * person);
	ROUGHNESS = 0.9;
}
