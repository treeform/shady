#version 410

in vec3 vertColor;

out vec4 fragColor;

void main() {
  fragColor = vec4(fragColor.x, fragColor.y, fragColor.z, 1.0);
}
