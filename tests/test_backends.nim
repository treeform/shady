import shady, strutils, vmath

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
  doAssert "float4 gl_FragCoord : SV_POSITION" in hlsl
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
  doAssert "float4 position [[position]];" in msl
  doAssert "output.position = gl_Position;" in msl

block:
  var atlas: Uniform[Sampler2d]

  proc sampledTexture(uv: Vec2, fragColor: var Vec4) =
    fragColor = texture(atlas, uv)

  let hlsl = toHLSL(sampledTexture, shaderFragment)
  doAssert "Texture2D<float4> atlas : register(t0);" in hlsl
  doAssert "SamplerState atlasSampler : register(s0);" in hlsl
  doAssert "atlas.Sample(atlasSampler, uv)" in hlsl

  let msl = toMSL(sampledTexture, shaderFragment)
  doAssert "texture2d<float> atlas;" in msl
  doAssert "atlas.sample(atlasSampler, uv)" in msl

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
  doAssert "texture2d<float> atlas;" in mslFragment
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
  doAssert "cbuffer ShadyUniforms : register(b0)" in hlslUniformVertex
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

echo "Backend codegen tests passed"
