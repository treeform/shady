import std/strutils, shady, vmath

var
  layers: Uniform[Sampler2dArray]
  data: Uniform[SamplerBuffer]

proc texture(s: Uniform[Sampler2dArray], uvw: Vec3): Vec4 =
  ## Provides the CPU signature for an array texture sample.
  vec4(0.0'f)

proc textureLod(s: Uniform[Sampler2dArray], uvw: Vec3, lod: float32): Vec4 =
  ## Provides the CPU signature for an array texture sample at a fixed LOD.
  vec4(0.0'f)

proc texelFetch(s: Uniform[Sampler2dArray], uvw: IVec3, lod: int): Vec4 =
  ## Provides the CPU signature for an array texture texel read.
  vec4(0.0'f)

proc textureSize(s: Uniform[Sampler2dArray], lod: int): IVec3 =
  ## Provides the CPU signature for all three array texture dimensions.
  ivec3(1)

proc vertex(
  gl_VertexID: int32,
  gl_Position: var Vec4,
  identifier: var int32
) =
  ## Exercises an explicit vertex builtin, integer varying, and early exit.
  identifier = gl_VertexID
  gl_Position = vec4(float32(gl_VertexID), 0.0'f, 0.0'f, 1.0'f)
  if gl_VertexID == 0:
    return
  gl_Position.x = -1.0'f

proc fragment(
  gl_FragCoord: Vec4,
  gl_FrontFacing: bool,
  identifier: int32,
  gl_FragDepth: var float32,
  fragColor: var Vec4
) =
  ## Exercises position, facing, depth, float promotion, and negative modulo.
  let
    promoted = float64(gl_FragCoord.x) * 0.1
    wrapped = float32(promoted) mod 1.0'f
    inverse = inversesqrt(gl_FragCoord.w)
  gl_FragDepth = gl_FragCoord.z * 0.5'f
  fragColor = vec4(wrapped, inverse, float32(identifier), 1.0'f)
  if not gl_FrontFacing:
    return
  fragColor.z = 0.0'f

proc globalFragment(fragColor: var Vec4) =
  ## Exercises builtin variables referenced without entry parameters.
  gl_FragDepth = gl_FragCoord.z
  fragColor = gl_FragCoord

proc sampled(uv: Vec2, fragColor: var Vec4) =
  ## Exercises array sampling, explicit LOD, dimensions, and buffer reads.
  let
    uvw = vec3(uv, 1.0'f)
    size = textureSize(layers, 0)
  fragColor = texture(layers, uvw) + textureLod(layers, uvw, 0.0'f) +
    texelFetch(layers, ivec3(size.x - 1, 0, 0), 0) + texelFetch(data, 0)

const
  Vertex = toShader(vertex, metalMSL, shaderVertex)
  Fragment = toShader(fragment, metalMSL, shaderFragment)
  GlobalFragment = toShader(globalFragment, metalMSL, shaderFragment)
  Sampled = toShader(sampled, metalMSL, shaderFragment)

doAssert "uint shady_gl_VertexID [[vertex_id]]" in Vertex
doAssert "int gl_VertexID = int(shady_gl_VertexID);" in Vertex
doAssert "return;" notin Vertex
doAssert Vertex.count("output.position.z =") == 2
doAssert "int identifier [[flat]]" in Vertex
doAssert "int identifier [[flat]]" in Fragment
for source in [Fragment, GlobalFragment]:
  doAssert "float4 gl_FragCoord [[position]]" in source
  doAssert "float gl_FragDepth [[depth(any)]]" in source
  doAssert "float4 fragColor [[color(0)]]" in source
  doAssert "[[color(1)]]" notin source
doAssert "bool gl_FrontFacing [[front_facing]]" in Fragment
doAssert "double" notin Fragment
doAssert "floor(" in Fragment and "rsqrt(" in Fragment
doAssert "layers.sample(layersSampler," in Sampled
doAssert "layers.read(uint2(" in Sampled
for source in [Vertex, Fragment, GlobalFragment, Sampled]:
  doAssert "shadyMod" notin source
  doAssert "shadyArray" notin source
doAssert "get_array_size()" in Sampled
doAssert "data.read(uint(0))" in Sampled

when defined(macosx):
  import metal4
  let device = MTLCreateSystemDefaultDevice()
  var
    libraries: seq[MTLLibrary]
    error: NSError
  for source in [Vertex, Fragment, GlobalFragment, Sampled]:
    error = 0.NSError
    let library = device.newLibraryWithSource(@source, 0.ID, error.addr)
    doAssert not library.isNil, "Generated Metal builtins failed: " & $error
    libraries.add(library)
  let descriptor = MTLRenderPipelineDescriptor.alloc().init()
  descriptor.setVertexFunction(libraries[0].newFunctionWithName(@"vertexMain"))
  descriptor.setFragmentFunction(libraries[1].newFunctionWithName(@"fragmentMain"))
  descriptor.colorAttachments().objectAtIndexedSubscript(0).
    setPixelFormat(MTLPixelFormatRGBA16Float)
  descriptor.setDepthAttachmentPixelFormat(MTLPixelFormatDepth32Float)
  error = 0.NSError
  let pipeline = device.newRenderPipelineStateWithDescriptor(descriptor, error.addr)
  doAssert not pipeline.isNil, "Generated Metal stage interface failed: " & $error
  echo "Metal builtin, texture, numeric, and stage interface regressions passed"
else:
  echo "Metal builtin generation passed; GPU compiler requires macOS"
