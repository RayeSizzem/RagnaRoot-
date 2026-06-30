shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

// One continuous fog sheet. A tiny per-block reveal mask (linear-filtered) is
// sampled in world space, so the fog only softens at the light/dark frontier and
// the interior is a single seamless surface -> no grid, no z-fighting flicker.
uniform sampler2D reveal_mask : filter_linear, repeat_disable;
uniform vec3 fog_color : source_color = vec3(0.05, 0.06, 0.1);
uniform float base_alpha = 1.0;
uniform float block_size = 42.0;
uniform float grid_size = 15.0;
uniform float world_radius = 7.0;
uniform float edge_sharpness = 0.7; // 0 = very soft halo, 1 = tight edge

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz / block_size + world_radius + 0.5) / grid_size;
	float revealed = texture(reveal_mask, uv).r;
	// The mask now fills each revealed block solidly, so the value is ~1 across a
	// block's interior and falls to 0 just outside it. Keeping the clear threshold
	// (hi) at 0.45 means a block's whole footprint stays clear (no build-in-fog),
	// the edge is a crisp ~2px line, and bilinear rounds only the outer corners.
	float soft = mix(0.12, 0.05, edge_sharpness);
	float clear = smoothstep(0.45 - soft, 0.45, revealed);
	ALBEDO = fog_color;
	ALPHA = (1.0 - clear) * base_alpha;
}
