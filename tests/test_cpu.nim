import pixie, shady, vmath

block:
  proc cpuFragment(uv: Vec2, time: Uniform[float32], fragColor: var Vec4) =
    let pulse = 0.5'f32 + 0.5'f32 * sin(time)
    fragColor = vec4(uv.x, uv.y, pulse, 1.0)

  var color: Vec4
  cpuFragment(vec2(0.25, 0.75), 0.0'f32, color)
  doAssert abs(color.x - 0.25) < 0.0001
  doAssert abs(color.y - 0.75) < 0.0001
  doAssert abs(color.z - 0.5) < 0.0001
  doAssert color.w == 1.0

block:
  var atlas: Uniform[Sampler2d]
  atlas.image = newImage(4, 4)
  atlas.image.fill(color(0.2, 0.4, 0.8, 1.0))

  proc cpuTexture(fragColor: var Vec4) =
    fragColor = texture(atlas, vec2(0.5, 0.5))

  var color: Vec4
  cpuTexture(color)
  doAssert abs(color.x - 0.2) < 0.01
  doAssert abs(color.y - 0.4) < 0.01
  doAssert abs(color.z - 0.8) < 0.01
  doAssert abs(color.w - 1.0) < 0.01

block:
  type CpuVertex = object
    position: Vec3
    uv: Vec2
    color: Vec4

  var atlas: Uniform[Sampler2d]
  atlas.image = newImage(2, 2)
  atlas.image[0, 0] = rgbx(255, 0, 0, 255)
  atlas.image[1, 0] = rgbx(0, 255, 0, 255)
  atlas.image[0, 1] = rgbx(0, 0, 255, 255)
  atlas.image[1, 1] = rgbx(255, 255, 255, 255)

  proc controlTint(texel, tint: Vec4): Vec4 =
    result = texel
    for i in 0 ..< 2:
      result.x += 0.05
    var steps = 0
    while steps < 2:
      result.z += 0.125
      inc steps
    if tint.y > 0.4:
      result.y = result.y * tint.y
    else:
      result.y = 0.0
    result.w = tint.w

  proc cpuImageLayout(vertex: CpuVertex, fragColor: var Vec4) =
    var texel = texelFetch(atlas, ivec2(1, 0), 0)
    if vertex.position.x < 0.0:
      texel = texelFetch(atlas, ivec2(0, 0), 0)
    fragColor = controlTint(texel, vertex.color)

  var color: Vec4
  cpuImageLayout(
    CpuVertex(
      position: vec3(0.25, -0.25, 0.0),
      uv: vec2(0.75, 0.25),
      color: vec4(1.0, 0.5, 0.75, 1.0)
    ),
    color
  )
  doAssert abs(color.x - 0.1) < 0.0001
  doAssert abs(color.y - 0.5) < 0.0001
  doAssert abs(color.z - 0.25) < 0.0001
  doAssert abs(color.w - 1.0) < 0.0001

echo "CPU execution tests passed"
