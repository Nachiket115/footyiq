shader_type spatial;
render_mode cull_disabled;

uniform vec3 color : source_color = vec3(1.0);
uniform float thickness = 0.12;
instance uniform vec2 cells = vec2(10.0, 10.0);

void fragment() {
	vec2 f = fract(UV * cells);
	ALBEDO = color;
	ALPHA = max(step(f.x, thickness), step(f.y, thickness));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
