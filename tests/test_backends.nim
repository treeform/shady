import shady, shady/backends/dx12, strutils, vmath

block:
  proc fragmentConstant(fragColor: var Vec4) =
    fragColor = vec4(1.0, 0.25, 0.0, 1.0)

  let glsl3Web = toShader(fragmentConstant, glsl3WebGL, shaderFragment)
  doAssert "#version 300 es" in glsl3Web
  doAssert "precision highp float;" in glsl3Web
  doAssert "out vec4 fragColor;" in glsl3Web

  let glsl3DesktopSource = toShader(fragmentConstant, glsl3Desktop, shaderFragment)
  doAssert "#version 330" in glsl3DesktopSource
  doAssert "out vec4 fragColor;" in glsl3DesktopSource

  let glsl4 = toShader(fragmentConstant, glsl4Desktop, shaderFragment)
  doAssert "#version 410" in glsl4
  doAssert "out vec4 fragColor;" in glsl4

  let hlsl = toHLSL(fragmentConstant, shaderFragment)
  doAssert "float4 PSMain(" in hlsl
  doAssert "float4 pos : SV_POSITION;" in hlsl
  doAssert ": SV_TARGET" in hlsl
  doAssert "float4 fragColor = float4(0.0, 0.0, 0.0, 0.0);" in hlsl
  doAssert "return fragColor;" in hlsl

  let msl = toMSL(fragmentConstant, shaderFragment)
  doAssert "#include <metal_stdlib>" in msl
  doAssert "fragment float4 fragmentMain()" in msl
  doAssert "float4 fragColor = float4(0.0, 0.0, 0.0, 0.0);" in msl
  doAssert "return fragColor;" in msl

block:
  proc vertexPass(
    vPos: Vec3,
    vCol: Vec3,
    gl_Position: var Vec4,
    vertColor: var Vec3
  ) =
    gl_Position = vec4(vPos.x, vPos.y, vPos.z, 1.0)
    vertColor = vCol

  let hlsl = toHLSL(vertexPass, shaderVertex)
  doAssert "struct VSOutput" in hlsl
  doAssert "VSOutput VSMain(" in hlsl
  doAssert "float4 pos : SV_POSITION;" in hlsl
  doAssert "output.pos = gl_Position;" in hlsl

  let msl = toMSL(vertexPass, shaderVertex)
  doAssert "struct VertexOut" in msl
  doAssert "vertex VertexOut vertexMain(" in msl
  doAssert "float pointSize [[point_size]];" in msl
  doAssert "output.pointSize = 1.0;" in msl
  doAssert "float4 position [[position]];" in msl
  doAssert "output.position = gl_Position;" in msl

block:
  proc instancedVertex(gl_Position: var Vec4) =
    ## Exercises portable vertex and instance identifiers.
    let
      vertex = float32(gl_VertexID)
      instance = float32(gl_InstanceID)
    gl_Position = vec4(vertex, instance, 0.0, 1.0)

  let glsl = toShader(instancedVertex, glsl4Desktop, shaderVertex)
  doAssert "gl_VertexID" in glsl
  doAssert "gl_InstanceID" in glsl

  let web = toShader(instancedVertex, glsl3WebGL, shaderVertex)
  doAssert "gl_VertexID" in web
  doAssert "gl_InstanceID" in web

  let vulkan = toShader(instancedVertex, vulkanGlsl450, shaderVertex)
  doAssert "gl_VertexIndex" in vulkan
  doAssert "gl_InstanceIndex" in vulkan
  doAssert "int gl_VertexIndex" notin vulkan
  doAssert "int gl_InstanceIndex" notin vulkan

  let hlsl = toHLSL(instancedVertex, shaderVertex)
  doAssert "uint gl_VertexID : SV_VertexID" in hlsl
  doAssert "uint gl_InstanceID : SV_InstanceID" in hlsl

  let msl = toMSL(instancedVertex, shaderVertex)
  doAssert "uint gl_VertexID [[vertex_id]]" in msl
  doAssert "uint gl_InstanceID [[instance_id]]" in msl

block:
  type Params = object
    offset: float32

  proc readOffset(params: Params): float32 =
    ## Returns a field from a shader-local parameter structure.
    params.offset

  proc structuredVertex(gl_Position: var Vec4) =
    ## Exercises an uninitialized shader-local parameter structure.
    var params: Params
    params.offset = gl_InstanceID.float32
    gl_Position = vec4(readOffset(params), 0.0, 0.0, 1.0)

  let glsl = toShader(structuredVertex, glsl4Desktop, shaderVertex)
  doAssert "struct Params" in glsl
  doAssert "Params params;" in glsl

  let hlsl = toHLSL(structuredVertex, shaderVertex)
  doAssert "struct Params" in hlsl
  doAssert "Params params;" in hlsl

  let msl = toMSL(structuredVertex, shaderVertex)
  doAssert "struct Params" in msl
  doAssert "Params params;" in msl

block:
  var atlas: Uniform[Sampler2d]

  proc sampledTexture(uv: Vec2, fragColor: var Vec4) =
    fragColor = texture(atlas, uv)

  let hlsl = toHLSL(sampledTexture, shaderFragment)
  doAssert "Texture2D<float4> atlas : register(t0);" in hlsl
  doAssert "SamplerState atlasSampler : register(s0);" in hlsl
  doAssert "atlas.Sample(atlasSampler, uv)" in hlsl

  let msl = toMSL(sampledTexture, shaderFragment)
  doAssert "texture2d<float> atlas [[texture(0)]]" in msl
  doAssert "atlas.sample(atlasSampler, uv)" in msl

block:
  var shadowMap: Uniform[Sampler2dShadow]

  proc sampledShadow(uvz: Vec3, fragColor: var Vec4) =
    let lit = texture(shadowMap, uvz)
    fragColor = vec4(lit, lit, lit, 1.0)

  let glsl = toShader(sampledShadow, glsl4Desktop, shaderFragment)
  doAssert "uniform sampler2DShadow shadowMap;" in glsl
  doAssert "texture(shadowMap, uvz)" in glsl

  let hlsl = toHLSL(sampledShadow, shaderFragment)
  doAssert "Texture2D<float> shadowMap : register(t0);" in hlsl
  doAssert "SamplerComparisonState shadowMapSampler : register(s0);" in hlsl
  doAssert "shadowMap.SampleCmpLevelZero(shadowMapSampler, uvz.xy, uvz.z)" in hlsl

  let msl = toMSL(sampledShadow, shaderFragment)
  doAssert "depth2d<float> shadowMap [[texture(0)]]" in msl
  doAssert "shadowMap.sample_compare(shadowMapSampler, uvz.xy, uvz.z)" in msl

block:
  var atlas: Uniform[Sampler2d]
  var viewportSize: Uniform[Vec2]

  func controlTint(texColor, vertexColor: Vec4): Vec4 =
    result = vec4(
      texColor.x * vertexColor.x,
      texColor.y * vertexColor.y,
      texColor.z * vertexColor.z,
      texColor.w * vertexColor.w
    )
    for i in 0 ..< 2:
      result.x += 0.05
    var steps = 0
    while steps < 2:
      result.z += 0.125
      inc steps
    if result.w < 0.5:
      result = vec4(0.0, 0.0, 0.0, 1.0)

  proc layoutVertex(
    position: Vec3,
    uv: Vec2,
    vertexColor: Vec4,
    gl_Position: var Vec4,
    fragmentUv: var Vec2,
    fragmentColor: var Vec4
  ) =
    gl_Position = vec4(position.x, position.y, position.z, 1.0)
    fragmentUv = uv
    fragmentColor = vertexColor

  proc layoutFragment(
    fragmentUv: Vec2,
    fragmentColor: Vec4,
    fragColor: var Vec4
  ) =
    let texColor = texture(atlas, fragmentUv)
    fragColor = controlTint(texColor, fragmentColor)

  let glsl3Vertex = toShader(layoutVertex, glsl3Desktop, shaderVertex)
  doAssert "in vec3 position;" in glsl3Vertex
  doAssert "in vec2 uv;" in glsl3Vertex
  doAssert "in vec4 vertexColor;" in glsl3Vertex
  doAssert "out vec2 fragmentUv;" in glsl3Vertex
  doAssert "out vec4 fragmentColor;" in glsl3Vertex

  let glsl3Fragment = toShader(layoutFragment, glsl3Desktop, shaderFragment)
  doAssert "uniform sampler2D atlas;" in glsl3Fragment
  doAssert "vec4 controlTint" in glsl3Fragment
  doAssert "for(int i = 0; i < 2; i++)" in glsl3Fragment
  doAssert "while(steps < 2)" in glsl3Fragment
  doAssert "if (" in glsl3Fragment
  doAssert "texture(atlas, fragmentUv)" in glsl3Fragment

  let glsl4Vertex = toShader(layoutVertex, glsl4Desktop, shaderVertex)
  doAssert "#version 410" in glsl4Vertex
  doAssert "in vec3 position;" in glsl4Vertex

  let vulkanVertex = toShader(layoutVertex, vulkanGlsl450, shaderVertex)
  doAssert "#version 450" in vulkanVertex
  doAssert "layout(location = 0) in vec3 position;" in vulkanVertex
  doAssert "layout(location = 1) in vec2 uv;" in vulkanVertex
  doAssert "layout(location = 2) in vec4 vertexColor;" in vulkanVertex
  doAssert "layout(location = 0) out vec2 fragmentUv;" in vulkanVertex
  doAssert "layout(location = 1) out vec4 fragmentColor;" in vulkanVertex
  doAssert "gl_Position.y = -gl_Position.y;" in vulkanVertex

  let hlslVertex = toHLSL(layoutVertex, shaderVertex)
  doAssert "float3 position : POSITION0" in hlslVertex
  doAssert "float2 uv : TEXCOORD0" in hlslVertex
  doAssert "float4 vertexColor : COLOR0" in hlslVertex
  doAssert "float2 fragmentUv : TEXCOORD0" in hlslVertex
  doAssert "float4 fragmentColor : COLOR0" in hlslVertex

  let hlslFragment = toHLSL(layoutFragment, shaderFragment)
  doAssert "Texture2D<float4> atlas : register(t0);" in hlslFragment
  doAssert "atlas.Sample(atlasSampler, fragmentUv)" in hlslFragment
  doAssert "float4 controlTint" in hlslFragment
  doAssert "for(int i = 0; i < 2; i++)" in hlslFragment
  doAssert "while(steps < 2)" in hlslFragment
  doAssert "if (" in hlslFragment

  let mslVertex = toMSL(layoutVertex, shaderVertex)
  doAssert "float3 position [[attribute(0)]]" in mslVertex
  doAssert "float2 uv [[attribute(1)]]" in mslVertex
  doAssert "float4 vertexColor [[attribute(2)]]" in mslVertex
  doAssert "float2 fragmentUv;" in mslVertex
  doAssert "float4 fragmentColor;" in mslVertex

  let mslFragment = toMSL(layoutFragment, shaderFragment)
  doAssert "texture2d<float> atlas [[texture(0)]]" in mslFragment
  doAssert "atlas.sample(atlasSampler, fragmentUv)" in mslFragment
  doAssert "float4 controlTint" in mslFragment
  doAssert "for(int i = 0; i < 2; i++)" in mslFragment
  doAssert "while(steps < 2)" in mslFragment
  doAssert "if (" in mslFragment

  proc uniformVertex(
    pos: Vec2,
    gl_Position: var Vec4
  ) =
    let clip = pos / viewportSize
    gl_Position = vec4(clip.x, clip.y, 0.0, 1.0)

  let hlslUniformVertex = toHLSL(uniformVertex, shaderVertex)
  doAssert "cbuffer ShadyUniforms0 : register(b0)" in hlslUniformVertex
  doAssert "float2 viewportSize;" in hlslUniformVertex
  doAssert "float2 pos : POSITION0" in hlslUniformVertex

  let vulkanUniformVertex = toShader(uniformVertex, vulkanGlsl450, shaderVertex)
  doAssert "layout(push_constant) uniform ShadyPushConstants" in vulkanUniformVertex
  doAssert "vec2 viewportSize;" in vulkanUniformVertex
  doAssert "#define viewportSize shadyPushConstants.viewportSize" in vulkanUniformVertex
  doAssert "layout(location = 0) in vec2 pos;" in vulkanUniformVertex

  let vulkanFragment = toShader(layoutFragment, vulkanGlsl450, shaderFragment)
  doAssert "layout(set = 0, binding = 0) uniform sampler2D atlas;" in vulkanFragment
  doAssert "layout(location = 0) in vec2 fragmentUv;" in vulkanFragment
  doAssert "layout(location = 1) in vec4 fragmentColor;" in vulkanFragment
  doAssert "layout(location = 0) out vec4 fragColor;" in vulkanFragment

block:
  var normalTransform: Uniform[Mat3]
  proc transformedNormal(normal: Vec3, fragColor: var Vec4) =
    let transformed: Vec3 = normalTransform * normal
    fragColor = vec4(transformed, 1.0'f)
  let source = toHLSL(transformedNormal, shaderFragment)
  doAssert "mul(normalTransform, normal)" in source

block:
  var image: Uniform[Sampler2d]
  var flags: Uniform[USampler2d]
  proc linear(input: Vec3): Vec3 =
    result = input + vec3(0.25'f)
  proc multipleTargets(uv: Vec2, color: var Vec4, flag: var uint32) =
    let value: Vec3 = linear(texture(image, uv).rgb)
    color = vec4(value, 1.0'f)
    flag = texelFetch(flags, ivec2(uv * textureSize(image, 0)), 0).r
    if flag == uint32(0):
      return
    color.rgb = vec3(1.0'f)
  let source = toHLSL(multipleTargets, shaderFragment)
  doAssert "shady_linear" in source
  doAssert "shadyTextureSize(image, 0)" in source
  doAssert "(float3) (1.0)" in source
  doAssert "SV_TARGET0" in source and "SV_TARGET1" in source
  let entry = source[source.find("PSOutput PSMain") .. ^1]
  doAssert "return result" notin entry
  doAssert entry.count("return output;") == 2
  let vulkan = toShader(multipleTargets, vulkanGlsl450, shaderFragment)
  doAssert "vec3 shady_input" in vulkan
  doAssert "result = shady_input +" in vulkan
  let shared = shareHlslSamplers(source, [0, 0])
  doAssert shared.count("SamplerState sharedSampler0") == 1
  doAssert "#define imageSampler sharedSampler0" in shared
  var rejected = false
  try: discard shareHlslSamplers(source, [16, 0])
  except ValueError: rejected = true
  doAssert rejected

echo "Backend codegen tests passed"

block:
  proc escapedEntry(input: Vec2, output: var Vec4) =
    output = vec4(input.x, input.y, 0.0'f, 1.0'f)
  let source = toShader(escapedEntry, vulkanGlsl450, shaderFragment)
  doAssert "in vec2 shady_input;" in source
  doAssert "out vec4 shady_output;" in source
  doAssert "shady_output = vec4(shady_input.x, shady_input.y" in source

block:
  var bitmap: Uniform[Sampler2D]
  proc explicitGradient(uv: Vec2, fragColor: var Vec4) =
    ## Retains explicit image derivatives on every source target.
    fragColor = textureGrad(bitmap, uv, dFdx(uv), dFdy(uv))
  let
    glsl = toShader(explicitGradient, glsl4Desktop, shaderFragment)
    hlsl = toHLSL(explicitGradient, shaderFragment)
    msl = toMSL(explicitGradient, shaderFragment)
  doAssert "textureGrad(bitmap, uv, dFdx(uv), dFdy(uv))" in glsl
  doAssert "bitmap.SampleGrad(bitmapSampler, uv, ddx(uv), ddy(uv))" in hlsl
  doAssert "bitmap.sample(bitmapSampler, uv, metal::gradient2d(" in msl
  doAssert "dfdx(uv), -dfdy(uv)" in msl
  doAssert "textureGrad(" notin hlsl and "textureGrad(" notin msl

block:
  var layers: Uniform[Sampler2DArray]
  proc layerGradient(uvw: Vec3, fragColor: var Vec4) =
    ## Separates an array layer from two-dimensional sampling derivatives.
    fragColor = textureGrad(layers, uvw, dFdx(uvw.xy), dFdy(uvw.xy))
  let
    hlsl = toHLSL(layerGradient, shaderFragment)
    msl = toMSL(layerGradient, shaderFragment)
  doAssert "layers.SampleGrad(layersSampler, uvw," in hlsl
  doAssert "layers.sample(layersSampler, (uvw).xy, uint((uvw).z)," in msl
  doAssert "metal::gradient2d(" in msl

block:
  type ShapeData = object
    point: Vec2
  var line: Uniform[Vec2]
  proc pointValue(shape: ShapeData): Vec2 =
    ## Reads a field whose ordinary Nim name is a target keyword.
    shape.point
  proc reservedNames(point: Vec2, fragColor: var Vec4) =
    ## Uses HLSL primitive keywords as Nim fields, uniforms and local names.
    var triangle: ShapeData
    triangle.point = point + line
    let value = pointValue(triangle)
    fragColor = vec4(value.x, value.y, 0'f, 1'f)
  let hlsl = toHLSL(reservedNames, shaderFragment)
  doAssert "float2 shady_point;" in hlsl
  doAssert "float2 shady_line;" in hlsl
  doAssert "ShapeData shady_triangle;" in hlsl
  doAssert "shady_triangle.shady_point = shady_point + shady_line;" in hlsl

block:
  proc colorTransfer(rgb: Vec3, fragColor: var Vec4) =
    ## Expresses piecewise SVG color transfer through vector intrinsics.
    let linear = mix(rgb / 12.92'f,
      pow((rgb + 0.055'f) / 1.055'f, vec3(2.4'f)),
      step(vec3(0.04045'f), rgb))
    fragColor = vec4(linear, 1'f)
  let
    glsl = toShader(colorTransfer, glsl4Desktop, shaderFragment)
    hlsl = toHLSL(colorTransfer, shaderFragment)
    msl = toMSL(colorTransfer, shaderFragment)
  doAssert "pow(" in glsl and "step(" in glsl
  doAssert "pow(" in hlsl and "step(" in hlsl
  doAssert "pow(" in msl and "step(" in msl
  doAssert pow(vec3(2, 3, 4), vec3(2)) == vec3(4, 9, 16)
