#version 410

in vec3 vCol;
in vec3 vPos;

uniform mat4 MVP;

out vec3 vertColor;

void main() {
  gl_Position = MVP * vec4(vPos.x, vPos.y, 0.0, 1.0);
  vertColor = vCol;
}
