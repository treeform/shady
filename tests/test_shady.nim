import pixie, shady, strutils, vmath

block:
  echo "--------------------------------------------------"
  echo "Basic fragment shader:"

  proc basicFrag(fragColor: var Vec4) =
    fragColor = vec4(1.0, 0.0, 0.0, 1.0)

  echo toGLSL(basicFrag)

  var c: Vec4
  basicFrag(c)
  assert c == vec4(1.0, 0.0, 0.0, 1.0)

block:
  echo "--------------------------------------------------"
  echo "Fragment with a function:"

  proc vec3Fun(output: var Vec3) =
    output = vec3(0.5, 0.3, 0.1)

  proc functionFrag(fragColor: var Vec4) =
    var v: Vec3
    vec3Fun(v)
    fragColor.x = v.x
    fragColor.y = v.y
    fragColor.z = v.z

  echo toGLSL(functionFrag)

  var c: Vec4
  functionFrag(c)
  assert c == vec4(0.5, 0.3, 0.1, 0.0)

block:
  echo "--------------------------------------------------"
  echo "Using var, let and math operators."

  proc mathFrag(
    uv: Vec2,
    color: Vec4,
    normal: Vec3,
    texelOffset: int,
    fragColor: var Vec4
  ) =
    let
      a = vec3(0.5, 0.5, 0.5)
      b = vec3(0.5, 0.5, 0.5)
    var
      c = vec3(1, 1, 1)
      d = vec3(1, 0, 1)
      e = vec3(1, 0, 0)
    let f = color.xyz * dot(normal, normalize(vec3(1.0, 1.0, 1.0)))
    fragColor.x = f.x
    fragColor.y = f.y
    fragColor.z = f.z
    fragColor.w = 1.0

  echo toGLSL(mathFrag)

  var c: Vec4
  mathFrag(vec2(0, 0), vec4(1, 0, 0, 1), vec3(0, 1, 0), 1, c)
  assert c == vec4(0.5773502588272095, 0.0, 0.0, 1.0)

block:
  echo "--------------------------------------------------"
  echo "Using data buffer and texelFetch."

  var dataBuffer: Uniform[SamplerBuffer]

  proc bufferFrag(fragColor: var Vec4) =
    if texelFetch(dataBuffer, 0).x == 0:
      fragColor = vec4(1, 0, 0, 1)
    else:
      fragColor = vec4(0, 0, 0, 1)

  echo toGLSL(bufferFrag)

  dataBuffer.data = @[0.float32]
  var c: Vec4
  bufferFrag(c)
  assert c == vec4(1.0, 0.0, 0.0, 1.0)

  dataBuffer.data = @[1.float32]
  bufferFrag(c)
  assert c == vec4(0.0, 0.0, 0.0, 1.0)

block:
  echo "--------------------------------------------------"
  echo "Using textures."

  var textureAtlasSampler: Uniform[Sampler2d]
  var uv = vec2(0.5, 0.5)

  textureAtlasSampler.image = newImage(100, 100)
  textureAtlasSampler.image.fill(color(1, 0.5, 0, 1))

  proc textureFrag(fragColor: var Vec4) =
    fragColor = texture(textureAtlasSampler, uv)

  echo toGLSL(textureFrag)

  var c: Vec4
  textureFrag(c)
  assert c == vec4(1.0, 0.4980392158031464, 0.0, 1.0)
