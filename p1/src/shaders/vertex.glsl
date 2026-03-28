uniform float time;
uniform float uAudioLevel;
uniform float uStripeDensity;
uniform float uNormalIntensity;

varying vec2 vUv;
varying vec3 vPosition;
varying vec3 vNormal;
varying float vHeight;
varying vec3 vSphereDir;

#define SPIRAL_SPEED 0.7
#define DISPLACEMENT_SCALE 0.55

float spiralHeight(vec3 dir) {
  dir = normalize(dir);
  float angle = atan(dir.z, dir.x);
  float latitude = dir.y;
  float radialMask = pow(max(1.0 - abs(latitude), 0.0), 0.55);
  float spacing = clamp(uStripeDensity, 0.0, 1.0);
  float turns = max(1.0, floor(mix(2.0, 18.0, spacing) + 0.5));
  float pitch = mix(3.0, 22.0, spacing) * mix(0.95, 1.25, uAudioLevel);
  float t = time * SPIRAL_SPEED;

  float spiralA = sin(angle * turns + latitude * pitch - t);
  float spiralB = sin(angle * (turns + 2.0) - latitude * (pitch * 0.55) - t * 0.72);
  float spiralC = sin(angle * max(1.0, turns - 1.0) + latitude * (pitch * 1.35) + t * 0.48);
  float wave = spiralA * 0.62 + spiralB * 0.24 + spiralC * 0.14;
  return wave * radialMask;
}

void main() {
  vUv = uv;
  vSphereDir = normalize(position);

  float intensity = clamp(uAudioLevel * (uNormalIntensity * 2.6), 0.0, 1.0);
  float height = spiralHeight(vSphereDir) * intensity;
  vHeight = height;

  vec3 displaced = position + vSphereDir * (height * DISPLACEMENT_SCALE);

  vPosition = vec3(modelMatrix * vec4(displaced, 1.0));
  vNormal = normalize(normalMatrix * normal);

  gl_Position = projectionMatrix * viewMatrix * vec4(vPosition, 1.0);
}
