import std/[strutils, tables], shady, vmath

var tint: Uniform[Vec4]

proc tintColor(color: Vec4): Vec4 =
  ## Exercises global capture alongside uniforms passed to the entry point.
  color * tint

proc matrixValue(matrix: Mat4): Mat4 =
  ## Keeps matrix constructor arguments as function calls in generated code.
  matrix

proc parameters(
  uv: Vec2,
  fragColor: var Vec4,
  image, mask: Uniform[Sampler2d],
  inverseView: Uniform[Mat4],
  strength: Uniform[float32],
  weights: Uniform[array[2, Vec4]]
) =
  ## Combines uniform entry resources, arrays, captures, and matrix narrowing.
  let
    basis = mat3(matrixValue(inverseView))
    position = basis * vec3(uv, 1.0'f)
  fragColor = tintColor(texture(image, uv) * texture(mask, uv) *
    strength * weights[1] + vec4(position, 1.0'f))

const
  Source = toShader(parameters, metalMSL, shaderFragment)
  Desktop = toShader(parameters, glsl4Desktop, shaderFragment)
  WebGL = toShader(parameters, glsl3WebGL, shaderFragment)

let
  layout = metalUniformLayout(Source)
  stageIn = Source.split("struct FragmentIn {")[1].split("};")[0]

doAssert "float2 uv;" in stageIn
doAssert "image" notin stageIn and "inverseView" notin stageIn
doAssert "strength" notin stageIn and "weights" notin stageIn
doAssert "texture2d<float> image [[texture(0)]]" in Source
doAssert "texture2d<float> mask [[texture(1)]]" in Source
doAssert "constant ShadyUniforms1 &shadyUniforms1 [[buffer(1)]]" in Source
doAssert "float4 weights[2];" in Source
for uniform in ["inverseView", "strength", "weights", "tint"]:
  doAssert layout.offsets.hasKey(uniform)
doAssert "shadyMat3FromMat4(matrixValue(inverseView))" in Source
doAssert "float3x3(value[0].xyz, value[1].xyz, value[2].xyz)" in Source
for source in [Desktop, WebGL]:
  doAssert "sampler2D image;" in source
  doAssert "uniform mat4 inverseView;" in source
  doAssert "mat3(matrixValue(inverseView))" in source
  doAssert "shadyMat3FromMat4" notin source

when defined(macosx):
  import metal4
  let device = MTLCreateSystemDefaultDevice()
  var error: NSError
  let library = device.newLibraryWithSource(@Source, 0.ID, error.addr)
  doAssert not library.isNil, "Generated Metal parameters failed: " & $error
  doAssert not library.newFunctionWithName(@"fragmentMain").isNil
  echo "Metal uniform entry parameters and matrix narrowing compiled"
else:
  echo "Metal parameter generation passed; GPU compiler requires macOS"
