const
  glsl3DesktopVersion* = "330"
  glsl3DesktopExtra* = ""
  glsl3WebGLVersion* = "300 es"
  glsl3WebGLExtra* = "precision highp float;\n"

proc glsl3NeedsHighp*(samplerType: string): bool =
  samplerType in [
    "sampler2D", "samplerCube", "sampler2DShadow", "usampler2D", "sampler2DArray",
    "samplerBuffer", "imageBuffer", "uimageBuffer"
  ]
