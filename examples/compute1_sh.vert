#version 410

// from vertShaderSrc



in vec3 vertexPos;
out vec3 pos;

void main() {
  pos = vertexPos;
  gl_Position.x = pos.x;
  gl_Position.y = pos.y;
  gl_Position.z = pos.z;
}
