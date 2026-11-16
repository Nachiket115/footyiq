shader_type spatial;

uniform sampler2D albedo_map : source_color;
uniform sampler2D normal_map : hint_normal;
uniform sampler2D roughness_map : hint_default_white;
uniform vec3 shirt : source_color;
uniform vec3 shorts : source_color;
uniform vec3 socks : source_color;
uniform vec3 boots : source_color;
uniform float cloth_roughness = 0.8;
uniform float region[80];

varying vec4 kit;

void vertex() {
	kit = vec4(0.0);
	for (int i = 0; i < 4; i++) {
		int r = int(region[int(BONE_INDICES[i])] + 0.5);
		if (r > 0) {
			kit[r - 1] += BONE_WEIGHTS[i];
		}
	}
}

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb;
	float cloth = 0.0;
	vec3 colors[4] = {shirt, shorts, socks, boots};
	for (int i = 0; i < 4; i++) {
		float on = step(0.5, kit[i]);
		base = mix(base, colors[i], on);
		cloth = max(cloth, on);
	}
	ALBEDO = base;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	ROUGHNESS = mix(texture(roughness_map, UV).g, cloth_roughness, cloth);
}
