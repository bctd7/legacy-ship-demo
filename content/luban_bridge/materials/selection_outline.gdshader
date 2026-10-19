shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 outline_color : source_color = vec4(0.76,0.55,0.26,0.8);
void vertex() { VERTEX += NORMAL * 0.0012; }
void fragment() { ALBEDO = outline_color.rgb; ALPHA = outline_color.a; }
