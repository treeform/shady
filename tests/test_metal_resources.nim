import std/[strutils, tables], shady, vmath

var
  enabled: Uniform[bool]
  strength: Uniform[float32]
  image: Uniform[Sampler2d]
  environment: Uniform[SamplerCube]

proc sampled(uv: Vec2): Vec4 =
  ## Reads a texture and scalar captured from module-level shader uniforms.
  result = texture(image, uv) * strength

proc nested(uv: Vec2): Vec4 =
  ## Exercises transitive resource capture through a second helper.
  result = sampled(uv)

proc resources(uv: Vec2, fragColor: var Vec4, flags: var uint32) =
  ## Exercises multiple outputs, early return, dimensions, and LOD name scope.
  if not enabled:
    fragColor = nested(uv)
    flags = uint32(1)
    return
  let
    level = 0.0'f
    dimensions = vec2(textureSize(image, 0))
  fragColor = nested(uv / dimensions) +
    textureLod(environment, vec3(0.0'f, 0.0'f, 1.0'f), level)
  flags = uint32(2)

const Source = toShader(resources, metalMSL, shaderFragment)
let
  shared = shareMetalSamplers(Source, [0, 0])
  layout = metalUniformLayout(Source)
doAssert layout.offsets.hasKey("enabled")
doAssert layout.offsets.hasKey("strength")
doAssert layout.offsets["strength"] mod 4 == 0
doAssert shared.count("[[sampler(") == 1
doAssert "[[color(1)]]" in shared
doAssert "return FragmentOut{fragColor, flags};" in shared

when defined(macosx):
  import metal4
  let device = MTLCreateSystemDefaultDevice()
  var error: NSError
  let library = device.newLibraryWithSource(@shared, 0.ID, error.addr)
  doAssert not library.isNil, "Generated Metal resources failed: " & $error
  doAssert not library.newFunctionWithName(@"fragmentMain").isNil
  echo "Metal resource capture, shared samplers and multiple outputs compiled"
else:
  echo "Metal resource generation passed; GPU compiler requires macOS"
