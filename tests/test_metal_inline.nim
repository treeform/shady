import std/strutils, shady, vmath

var
  layers: Uniform[Sampler2dArray]
  shadowMap: Uniform[Sampler2dShadow]

proc texture(image: Uniform[Sampler2dArray], coordinate: Vec3): Vec4 =
  ## Provides the CPU signature for an array texture sample.
  vec4(0.0'f)

proc textureLod(
  image: Uniform[Sampler2dArray], coordinate: Vec3, lod: float32
): Vec4 =
  ## Provides the CPU signature for an explicit array texture LOD.
  vec4(0.0'f)

proc texelFetch(
  image: Uniform[Sampler2dArray], coordinate: IVec3, lod: int
): Vec4 =
  ## Provides the CPU signature for an array texture texel read.
  vec4(0.0'f)

proc textureSize(image: Uniform[Sampler2dArray], lod: int): IVec3 =
  ## Provides the CPU signature for an array texture's three dimensions.
  ivec3(1)

proc countedValue(calls: var int32, value: float32): float32 =
  ## Counts each evaluation of a modulo operand.
  calls += 1
  result = value

proc countedCoordinate(calls: var int32): Vec3 =
  ## Counts each evaluation of a coordinate split into UV and array layer.
  calls += 1
  result = vec3(0.5'f, 0.5'f, 1.0'f)

proc countedTexel(calls: var int32): IVec3 =
  ## Counts each evaluation of an integer coordinate split into two parts.
  calls += 1
  result = ivec3(0, 0, 1)

proc countedLod(calls: var int32): int =
  ## Counts each LOD evaluation shared by width and height queries.
  calls += 1
  result = 0

proc mutateValue(value: var float32): float32 =
  ## Mutates a preceding argument after its value should have been captured.
  value = 9.0'f
  result = 1.0'f

proc wrappedValue(calls: var int32): float32 =
  ## Exercises inline lowering inside an ordinary helper function.
  fmod(countedValue(calls, -1.25'f), 1.0'f)

proc vertex(gl_VertexID: int32, gl_Position: var Vec4) =
  ## Covers a one-pixel render target without vertex buffers.
  gl_Position = vec4(-1.0'f, -1.0'f, 0.0'f, 1.0'f)
  if gl_VertexID == 1:
    gl_Position.x = 3.0'f
  if gl_VertexID == 2:
    gl_Position.y = 3.0'f

proc scalarModulo(fragColor: var Vec4) =
  ## Covers negative dividends, negative divisors, and infix modulo.
  fragColor = vec4(
    fmod(-1.25'f, 1.0'f),
    fmod(1.25'f, -1.0'f),
    -1.25'f mod 1.0'f,
    1.25'f mod -1.0'f
  )

proc vectorModulo(fragColor: var Vec4) =
  ## Covers vector and scalar divisors with mixed signs.
  let
    vector = fmod(
      vec4(-1.25'f, 1.25'f, -2.5'f, 2.5'f),
      vec4(1.0'f, -1.0'f, 2.0'f, -2.0'f)
    )
    scalar = fmod(vec3(-1.25'f, 1.25'f, 2.5'f), 1.0'f)
  fragColor = vec4(vector.x, vector.y, vector.z, scalar.x)

proc countedModulo(fragColor: var Vec4) =
  ## Requires both operands of each modulo expression to execute once.
  var calls = 0'i32
  let
    call = fmod(countedValue(calls, -1.25'f), countedValue(calls, 1.0'f))
    infix = countedValue(calls, 1.25'f) mod countedValue(calls, -1.0'f)
  fragColor = vec4(call, infix, float32(calls), 1.0'f)

proc expressionFlow(fragColor: var Vec4) =
  ## Preserves short circuits, ternary branches, and loop condition timing.
  var calls = 0'i32
  if calls < 0 and fmod(countedValue(calls, -1.25'f), 1.0'f) > 0.0'f:
    calls = 99
  let selected =
    if calls == 0:
      fmod(countedValue(calls, -1.25'f), 1.0'f)
    else:
      fmod(countedValue(calls, -1.5'f), 1.0'f)
  var iterations = 0'i32
  while fmod(countedValue(calls, float32(iterations)), 3.0'f) < 2.0'f:
    iterations += 1
  let wrapped = wrappedValue(calls)
  fragColor = vec4(selected, float32(calls), float32(iterations), wrapped)

proc nestedModulo(fragColor: var Vec4) =
  ## Preserves nested evaluation and captures a value before later mutation.
  var
    calls = 0'i32
    value = -1.25'f
  let
    snapshot = fmod(value, mutateValue(value))
    nested = fmod(
      countedValue(calls, -3.25'f),
      fmod(countedValue(calls, 2.0'f), countedValue(calls, 1.25'f))
    )
  fragColor = vec4(snapshot, nested, float32(calls), value)

proc sampled(fragColor: var Vec4) =
  ## Samples one array layer with one coordinate evaluation.
  var calls = 0'i32
  let color = texture(layers, countedCoordinate(calls))
  fragColor = vec4(color.x, color.y, color.z, float32(calls))

proc sampledLod(fragColor: var Vec4) =
  ## Samples an explicit LOD with one coordinate evaluation.
  var calls = 0'i32
  let color = textureLod(layers, countedCoordinate(calls), 0.0'f)
  fragColor = vec4(color.x, color.y, color.z, float32(calls))

proc sampledGradient(fragColor: var Vec4) =
  ## Samples explicit gradients with one coordinate evaluation.
  var calls = 0'i32
  let color = textureGrad(
    layers, countedCoordinate(calls), vec2(0.0'f), vec2(0.0'f)
  )
  fragColor = vec4(color.x, color.y, color.z, float32(calls))

proc fetched(fragColor: var Vec4) =
  ## Reads an array texel with one coordinate evaluation.
  var calls = 0'i32
  let color = texelFetch(layers, countedTexel(calls), 0)
  fragColor = vec4(color.x, color.y, color.z, float32(calls))

proc sized(fragColor: var Vec4) =
  ## Queries all array dimensions with one LOD expression evaluation.
  var calls = 0'i32
  let dimensions = textureSize(layers, countedLod(calls))
  fragColor = vec4(vec3(dimensions), float32(calls))

proc shadowed(fragColor: var Vec4) =
  ## Splits one shadow coordinate into UV and comparison depth.
  var calls = 0'i32
  let value = texture(shadowMap, countedCoordinate(calls))
  fragColor = vec4(value, value, value, float32(calls))

const
  Vertex = toMSL(vertex, shaderVertex)
  ScalarModulo = toMSL(scalarModulo, shaderFragment)
  VectorModulo = toMSL(vectorModulo, shaderFragment)
  CountedModulo = toMSL(countedModulo, shaderFragment)
  ExpressionFlow = toMSL(expressionFlow, shaderFragment)
  NestedModulo = toMSL(nestedModulo, shaderFragment)
  Sampled = toMSL(sampled, shaderFragment)
  SampledLod = toMSL(sampledLod, shaderFragment)
  SampledGradient = toMSL(sampledGradient, shaderFragment)
  Fetched = toMSL(fetched, shaderFragment)
  Sized = toMSL(sized, shaderFragment)
  Shadowed = toMSL(shadowed, shaderFragment)
  Sources = [
    ScalarModulo, VectorModulo, CountedModulo, ExpressionFlow, NestedModulo,
    Sampled, SampledLod, SampledGradient, Fetched, Sized
  ]
  Expected = [
    [0.75'f, -0.75'f, 0.75'f, -0.75'f],
    [0.75'f, -0.75'f, 1.5'f, 0.75'f],
    [0.75'f, -0.75'f, 4.0'f, 1.0'f],
    [0.75'f, 5.0'f, 2.0'f, 0.75'f],
    [0.75'f, 0.5'f, 3.0'f, 9.0'f],
    [0.25'f, 0.5'f, 0.75'f, 1.0'f],
    [0.25'f, 0.5'f, 0.75'f, 1.0'f],
    [0.25'f, 0.5'f, 0.75'f, 1.0'f],
    [0.25'f, 0.5'f, 0.75'f, 1.0'f],
    [1.0'f, 1.0'f, 2.0'f, 1.0'f]
  ]

for source in Sources:
  doAssert "shadyMod" notin source and "shadyArray" notin source
  doAssert "template<" notin source
for source in [ScalarModulo, VectorModulo, CountedModulo]:
  doAssert "floor(" in source
  doAssert "fmod(" notin source
for source in [Sampled, SampledLod, SampledGradient]:
  doAssert "layers.sample(layersSampler," in source
doAssert "level(" in SampledLod
doAssert "gradient2d(" in SampledGradient
doAssert "layers.read(uint2(" in Fetched
doAssert "shadowMap.sample_compare(shadowMapSampler," in Shadowed
doAssert Shadowed.count("countedCoordinate(calls)") == 1
doAssert "layers.get_width(" in Sized
doAssert Sized.count("countedLod(calls)") == 1
for source in [
  toShader(countedModulo, glsl4Desktop, shaderFragment),
  toShader(countedModulo, glsl3WebGL, shaderFragment)
]:
  doAssert "mod(countedValue(calls," in source
  doAssert "shadyMod" notin source
for source in [
  toShader(sampledGradient, glsl4Desktop, shaderFragment),
  toShader(sampledGradient, glsl3WebGL, shaderFragment)
]:
  doAssert "textureGrad(layers, countedCoordinate(calls)," in source
  doAssert ".sample(" notin source

when defined(macosx):
  import metal4

  objc:
    proc setTextureType(self: MTLTextureDescriptor, x: uint) =
      ## Selects the native two-dimensional array texture shape.
    proc setArrayLength(self: MTLTextureDescriptor, x: uint) =
      ## Allocates the two distinct texture layers used by this test.
    proc replaceRegion(
      self: MTLTexture, x: MTLRegion, mipmapLevel: uint, slice: uint,
      withBytes: pointer, bytesPerRow: uint, bytesPerImage: uint
    ) =
      ## Uploads a known color to one array texture layer.

  proc runGpuTests() =
    ## Compiles and evaluates every inline lowering on a native Metal device.
    let device = MTLCreateSystemDefaultDevice()
    doAssert not device.isNil, "A Metal device is required for this test"
    defer: device.release()
    let queue = device.newCommandQueue()
    doAssert not queue.isNil
    defer: queue.release()
    var error: NSError
    let vertexLibrary = device.newLibraryWithSource(@Vertex, 0.ID, error.addr)
    doAssert not vertexLibrary.isNil, "Metal vertex compilation: " & $error
    defer: vertexLibrary.release()
    error = 0.NSError
    let shadowLibrary = device.newLibraryWithSource(@Shadowed, 0.ID, error.addr)
    doAssert not shadowLibrary.isNil, "Metal shadow compilation: " & $error
    defer: shadowLibrary.release()
    let vertexFunction = vertexLibrary.newFunctionWithName(@"vertexMain")
    defer: vertexFunction.release()
    let
      descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
        MTLPixelFormatRGBA32Float, 1, 1, false
      )
      region = MTLRegion(size: MTLSize(width: 1, height: 1, depth: 1))
    descriptor.setStorageMode(MTLStorageModeShared)
    descriptor.setUsage(MTLTextureUsageRenderTarget)
    let target = device.newTextureWithDescriptor(descriptor)
    doAssert not target.isNil
    defer: target.release()
    descriptor.setUsage(MTLTextureUsageShaderRead)
    descriptor.setTextureType(3)
    descriptor.setArrayLength(2)
    let image = device.newTextureWithDescriptor(descriptor)
    doAssert not image.isNil
    defer: image.release()
    let pixels = [
      [0.9'f, 0.8'f, 0.7'f, 1.0'f],
      [0.25'f, 0.5'f, 0.75'f, 1.0'f]
    ]
    for i in 0 ..< pixels.len:
      image.replaceRegion(region, 0, i.uint, pixels[i].unsafeAddr, 16, 16)
    let samplerDescriptor = MTLSamplerDescriptor.alloc().init()
    defer: samplerDescriptor.release()
    samplerDescriptor.setMinFilter(MTLSamplerMinMagFilterNearest)
    samplerDescriptor.setMagFilter(MTLSamplerMinMagFilterNearest)
    let sampler = device.newSamplerStateWithDescriptor(samplerDescriptor)
    doAssert not sampler.isNil
    defer: sampler.release()
    for i, source in Sources:
      error = 0.NSError
      let library = device.newLibraryWithSource(@source, 0.ID, error.addr)
      doAssert not library.isNil,
        "Metal fragment compilation " & $i & ": " & $error & "\n" & source
      defer: library.release()
      let fragmentFunction = library.newFunctionWithName(@"fragmentMain")
      defer: fragmentFunction.release()
      let pipelineDescriptor = MTLRenderPipelineDescriptor.alloc().init()
      defer: pipelineDescriptor.release()
      pipelineDescriptor.setVertexFunction(vertexFunction)
      pipelineDescriptor.setFragmentFunction(fragmentFunction)
      pipelineDescriptor.colorAttachments().objectAtIndexedSubscript(0).
        setPixelFormat(MTLPixelFormatRGBA32Float)
      let pipeline = device.newRenderPipelineStateWithDescriptor(
        pipelineDescriptor, error.addr
      )
      doAssert not pipeline.isNil, "Metal pipeline: " & $error
      defer: pipeline.release()
      let
        command = queue.commandBuffer()
        pass = MTLRenderPassDescriptor.renderPassDescriptor()
        attachment = pass.colorAttachments().objectAtIndexedSubscript(0)
      attachment.setTexture(target)
      attachment.setLoadAction(MTLLoadActionClear)
      attachment.setStoreAction(MTLStoreActionStore)
      let encoder = command.renderCommandEncoderWithDescriptor(pass)
      encoder.setRenderPipelineState(pipeline)
      encoder.setFragmentTexture(image, 0)
      encoder.setFragmentSamplerState(sampler, 0)
      encoder.drawPrimitives(MTLPrimitiveTypeTriangle, 0, 3)
      encoder.endEncoding()
      command.commit()
      command.waitUntilCompleted()
      doAssert command.status() == MTLCommandBufferStatusCompleted,
        "Metal execution: " & $command.error()
      var actual: array[4, float32]
      target.getBytes(actual[0].addr, 16, region, 0)
      for channel in 0 ..< actual.len:
        doAssert abs(actual[channel] - Expected[i][channel]) < 0.0001'f,
          "Shader " & $i & ": " & $actual & " expected " & $Expected[i]
    echo "Metal inline math and texture evaluation passed on the GPU"

  runGpuTests()
else:
  echo "Metal inline generation passed; GPU execution requires macOS"
