import shady, strutils, vmath, chroma, pixie

block:
  echo "--------------------------------------------------"
  echo "Basic fragment shader:"

  proc basicFrag(fragColor: var Color) =
    fragColor = color(1.0, 0.0, 0.0, 1.0)

  echo toShader(basicFrag)

  var c: Color
  basicFrag(c)
  assert c == color(1.0, 0.0, 0.0, 1.0)

block:
  echo "--------------------------------------------------"
  echo "Fragment with a function:"

  proc vec3Fun(output: var Vec3) =
    output = vec3(0.5, 0.3, 0.1)

  proc functionFrag(fragColor: var Color) =
    var v: Vec3
    vec3Fun(v)
    fragColor.r = v.x
    fragColor.g = v.y
    fragColor.b = v.z

  echo toShader(functionFrag)

  var c: Color
  functionFrag(c)
  assert c == color(0.5, 0.3, 0.1, 0.0)

block:
  echo "--------------------------------------------------"
  echo "Using var, let and math operators."

  proc mathFrag(
    uv: Vec2,
    color: Color,
    normal: Vec3,
    texelOffset: int,
    fragColor: var Color
  ) =
    let
      a = vec3(0.5, 0.5, 0.5)
      b = vec3(0.5, 0.5, 0.5)
    var
      c = vec3(1, 1, 1)
      d = vec3(1, 0, 1)
      e = vec3(1, 0, 0)
    fragColor.rgb = color.rgb * dot(normal, normalize(vec3(1.0, 1.0, 1.0)))
    fragColor.a = 1.0

  echo toShader(mathFrag)

  var c: Color
  mathFrag(vec2(0, 0), color(1, 0, 0, 1), vec3(0, 1, 0), 1, c)
  assert c == color(0.5773502588272095, 0.0, 0.0, 1.0)

block:
  echo "--------------------------------------------------"
  echo "Using data buffer and texelFetch."

  var dataBuffer: Uniform[SamplerBuffer]

  proc bufferFrag(fragColor: var Color) =
    if texelFetch(dataBuffer, 0).x == 0:
      fragColor = color(1, 0, 0, 1)
    else:
      fragColor = color(0, 0, 0, 1)

  echo toShader(bufferFrag)

  dataBuffer.data = @[0.float32]
  var c: Color
  bufferFrag(c)
  assert c == color(1.0, 0.0, 0.0, 1.0)

  dataBuffer.data = @[1.float32]
  bufferFrag(c)
  assert c == color(0.0, 0.0, 0.0, 1.0)

block:
  echo "--------------------------------------------------"
  echo "Using textures."

  var textureAtlasSampler: Uniform[Sampler2d]
  var uv = vec2(0.5, 0.5)

  textureAtlasSampler.image = newImage(100, 100)
  textureAtlasSampler.image.fill(color(1, 0.5, 0, 1))

  proc textureFrag(fragColor: var Color) =
    fragColor = texture(textureAtlasSampler, uv)

  echo toShader(textureFrag)

  var c: Color
  textureFrag(c)
  assert c == color(1.0, 0.4980392158031464, 0.0, 1.0)
