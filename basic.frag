#version 410

in vec3 vertColor;

out vec4 fragColor;

void main() {
  fragColor = vec4(vertColor.x, vertColor.y, vertColor.z, 1.0);
}
