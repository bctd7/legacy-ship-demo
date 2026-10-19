// Metre-space procedural grain; original v2 geometry remains unchanged.
uniform vec3 grain_axis = vec3(1.0, 0.0, 0.0);
uniform vec3 wood_dark : source_color = vec3(0.25, 0.085, 0.043);
uniform vec3 wood_light : source_color = vec3(0.43, 0.185, 0.095);
uniform float variation = 0.0;
uniform float model_scale = 0.1;
uniform bool section_enabled = false;
uniform vec3 section_center = vec3(0.0);
uniform vec3 section_half = vec3(100.0);
uniform bool cutaway_enabled = false;
uniform bool reveal_enabled = false;
uniform float reveal_limit = 100.0;
uniform float context_opacity = 1.0;
varying vec3 world_point;
varying vec3 local_point;

float hash3(vec3 p) {
	return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);
}
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}

void vertex() {
	local_point = VERTEX * model_scale;
	world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}

void fragment() {
#ifdef BOAT_CONTEXT_FADE
 ALPHA = context_opacity;
#endif
 if (section_enabled && any(greaterThan(abs(world_point-section_center),section_half))) { discard; }
 if (cutaway_enabled && world_point.z > section_center.z) { discard; }
 if (reveal_enabled && world_point.x > reveal_limit) { discard; }
	vec3 along = normalize(grain_axis);
	vec3 reference = abs(along.z) > 0.8 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
	vec3 across = normalize(cross(along, reference));
	vec3 radial = cross(along, across);
	float u = dot(local_point, along);
	float v = dot(local_point, across);
	float w = dot(local_point, radial);
	float transverse = v + w * 0.67;
	float natural = noise3(vec3(u*9.0+variation*5.0,v*200.0,w*200.0));
	float warp = sin(u*18.0+variation*13.0)*0.35+natural*1.8;
	float broad = 0.5 + 0.5 * sin(transverse * 1250.0 + warp);
	float fine = pow(0.5 + 0.5 * sin(transverse * 6800.0 + warp * 2.0 + sin(transverse * 400.0)), 10.0);
	float antialias = 1.0 - smoothstep(0.8, 2.5, fwidth(transverse * 6800.0));
	ALBEDO = mix(wood_dark,wood_light,0.40+broad*0.18+natural*0.05)*(0.96+variation*0.07)*(1.0-fine*0.07*antialias);
	ROUGHNESS = 0.67 + broad * 0.12;
	SPECULAR = 0.27;
}
