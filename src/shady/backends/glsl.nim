import strutils

proc glslTypeRename*(t: string): string =
  case t
  of "Mat2": "mat2"
  of "Mat3": "mat3"
  of "Mat4": "mat4"

  of "Vec2": "vec2"
  of "Vec3": "vec3"
  of "Vec4": "vec4"

  of "IVec2": "ivec2"
  of "IVec3": "ivec3"
  of "IVec4": "ivec4"

  of "UVec2": "uvec2"
  of "UVec3": "uvec3"
  of "UVec4": "uvec4"

  of "DVec2": "dvec2"
  of "DVec3": "dvec3"
  of "DVec4": "dvec4"

  of "int32": "int"
  of "uint32": "uint"

  of "float32": "float"
  of "float64": "float"
  of "Uniform": "uniform"
  of "UniformWriteOnly": "writeonly uniform"
  of "Attribute": "attribute"
  of "ColorRGBX": "vec4"

  of "SamplerBuffer": "samplerBuffer"
  of "Sampler2d": "sampler2D"
  of "USampler2d": "usampler2D"
  of "Sampler2dArray": "sampler2DArray"
  of "ImageBuffer": "imageBuffer"
  of "UImageBuffer": "uimageBuffer"
  else: t

proc glslProcRename*(t: string): string =
  case t
  of "not": "!"
  of "and": "&&"
  of "or": "||"
  of "fmod": "mod"
  of "mod": "%"
  of "div": "/"
  else: t.replace("`", "_")

proc glslTypeDefault*(t: string): string =
  case t
  of "mat2": "mat2(0.0)"
  of "mat3": "mat3(0.0)"
  of "mat4": "mat4(0.0)"
  of "vec4": "vec4(0.0)"
  of "vec3": "vec3(0.0)"
  of "vec2": "vec2(0.0)"

  of "uvec2": "uvec2(0)"
  of "uvec3": "uvec3(0)"
  of "uvec4": "uvec4(0)"
  of "ivec2": "ivec2(0)"
  of "ivec3": "ivec3(0)"
  of "ivec4": "ivec4(0)"

  of "float": "0.0"
  of "int": "0"
  of "uint": "0"
  else: ""

const glslGlobals* = [
  "gl_Position", "gl_FragCoord", "gl_GlobalInvocationID",
  "gl_VertexID",
]

const glslFunctions* = [
  "bool", "array",
  "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
  "Vec2", "Vec3", "Vec4", "mat2", "Mat3", "Mat4",
  "uvec2", "uvec3", "uvec4",
  "UVec2", "UVec3", "UVec4",
  "ivec2", "ivec3", "ivec4",
  "IVec2", "IVec3", "IVec4",

  "abs", "clamp", "min", "max", "dot", "sqrt", "mix", "length",
  "texelFetch", "imageStore", "imageLoad", "texture", "textureSize",
  "textureGrad",
  "normalize",
  "floor", "ceil", "round", "exp", "inversesqrt",
  "[]", "[]=",
  "inverse",
  "sin", "cos", "tan", "pow",
  "fmod",
  "lessThan", "lessThanEqual", "greaterThan", "greaterThanEqual",
  "equal", "notEqual",
  "dFdx", "dFdy", "fract", "fwidth",
  "smoothstep", "inc", "dec", "discardFragment"
]
