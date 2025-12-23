shader_type canvas_item;

uniform bool enabled = false;

uniform vec4 outline_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float outline_size = 1.0;     // pixels
uniform float pulse_speed = 4.0;      // how fast it pulses
uniform float pulse_amount = 0.35;    // how strong pulsing is
uniform float base_strength = 0.85;   // baseline outline strength

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (enabled) {
		// Alpha of current pixel
		float a = tex.a;

		// Sample neighbors to detect edges
		vec2 px = TEXTURE_PIXEL_SIZE * outline_size;

		float a1 = texture(TEXTURE, UV + vec2( px.x, 0.0)).a;
		float a2 = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
		float a3 = texture(TEXTURE, UV + vec2(0.0,  px.y)).a;
		float a4 = texture(TEXTURE, UV + vec2(0.0, -px.y)).a;

		float edge = max(max(a1, a2), max(a3, a4)) - a;
		edge = clamp(edge * 8.0, 0.0, 1.0);

		// Flow/pulse
		float pulse = base_strength + sin(TIME * pulse_speed) * pulse_amount;
		pulse = clamp(pulse, 0.0, 1.0);

		vec4 outcol = outline_color;
		outcol.a *= edge * pulse;

		// Composite: original sprite + outline
		COLOR = tex + vec4(outcol.rgb * outcol.a, outcol.a);
	} else {
		COLOR = tex;
	}
}
