import pixie, shady, vmath, os

var masterOutput: string
proc log(args: varargs[string, `$`]) =
  for arg in args:
    masterOutput.add(arg)
  masterOutput.add("\n")

const goldMasterPath = currentSourcePath().parentDir() / "test_shady.txt"

block:
  log "--------------------------------------------------"
  log "Basic fragment shader:"

  proc basicFrag(fragColor: var Vec4) =
    fragColor = vec4(1.0, 0.0, 0.0, 1.0)

  log toGLSL(basicFrag)

  var c: Vec4
  basicFrag(c)
  assert c == vec4(1.0, 0.0, 0.0, 1.0)

block:
  log "--------------------------------------------------"
  log "Fragment with a function:"

  proc vec3Fun(output: var Vec3) =
    output = vec3(0.5, 0.3, 0.1)

  proc functionFrag(fragColor: var Vec4) =
    var v: Vec3
    vec3Fun(v)
    fragColor.x = v.x
    fragColor.y = v.y
    fragColor.z = v.z

  log toGLSL(functionFrag)

  var c: Vec4
  functionFrag(c)
  assert c == vec4(0.5, 0.3, 0.1, 0.0)

block:
  log "--------------------------------------------------"
  log "Using var, let and math operators."

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

  log toGLSL(mathFrag)

  var c: Vec4
  mathFrag(vec2(0, 0), vec4(1, 0, 0, 1), vec3(0, 1, 0), 1, c)
  assert c == vec4(0.5773502588272095, 0.0, 0.0, 1.0)

block:
  log "--------------------------------------------------"
  log "Using data buffer and texelFetch."

  var dataBuffer: Uniform[SamplerBuffer]

  proc bufferFrag(fragColor: var Vec4) =
    if texelFetch(dataBuffer, 0).x == 0:
      fragColor = vec4(1, 0, 0, 1)
    else:
      fragColor = vec4(0, 0, 0, 1)

  log toGLSL(bufferFrag)

  dataBuffer.data = @[0.float32]
  var c: Vec4
  bufferFrag(c)
  assert c == vec4(1.0, 0.0, 0.0, 1.0)

  dataBuffer.data = @[1.float32]
  bufferFrag(c)
  assert c == vec4(0.0, 0.0, 0.0, 1.0)

block:
  log "--------------------------------------------------"
  log "Using textures."

  var textureAtlasSampler: Uniform[Sampler2d]
  var uv = vec2(0.5, 0.5)

  textureAtlasSampler.image = newImage(100, 100)
  textureAtlasSampler.image.fill(color(1, 0.5, 0, 1))

  proc textureFrag(fragColor: var Vec4) =
    fragColor = texture(textureAtlasSampler, uv)

  log toGLSL(textureFrag)

  var c: Vec4
  textureFrag(c)

  assert (c - vec4(1.0, 0.5, 0.0, 1.0)).length < 0.005

block:
  log "--------------------------------------------------"
  log "https://github.com/treeform/shady/issues/4"
  proc vertexShade(position: Vec3, in_color: Vec4, color: var Vec4, gl_Position: var Vec3) =
      color = in_color
      gl_Position = position
  log toGLSL(vertexShade, "300 es")

block:
  log "--------------------------------------------------"
  log "Ternary operator."

  proc ternaryOperator(fragColor: var Vec4, normal: Vec3) =
    fragColor = vec4(
      if normal.x <= 0: 0 else: 1,
      if normal.y <= 0:
        0
      else:
        1,
      if normal.z < -0.5:
        -0.5
      elif normal.z < 0:
        0
      else:
        1,
      1)

  log toGLSL(ternaryOperator)
  var c: Vec4
  ternaryOperator(c, vec3(-1.0, 1.0, -0.6))
  assert c == vec4(0.0, 1.0, -0.5, 1.0)

block:
  log "--------------------------------------------------"
  log "Testin +*() presedence."
  proc presedence(y, r: float32, a: var float32) =
    a = exp(-(y*y).float32/(r*r)*2)
  log toGLSL(presedence)

block:
  log "--------------------------------------------------"
  log "Structs for interleaved buffers:"

  type Vertex = object
    pos: Vec2
    color: ColorRGBX

  proc structShader(v: Vertex, fragColor: var Vec4) =
    fragColor = vec4(v.color)

  log toGLSL(structShader)

block:
  log "--------------------------------------------------"
  log "Structs with arrays (SilkyVertex-like):"

  type SilkyVertex = object
    pos: Vec2
    uvPos: array[2, uint16]
    color: ColorRGBX

  proc silkyShader(v: SilkyVertex, fragColor: var Vec4) =
    fragColor = vec4(v.color)

  log toGLSL(silkyShader)

when defined(gen_master):
  writeFile(goldMasterPath, masterOutput)
else:
  if fileExists(goldMasterPath):
    let expected = readFile(goldMasterPath)
    if expected != masterOutput:
      echo "FAILED: Gold master mismatch!"
      quit(1)
  else:
    echo "FAILED: Gold master file not found! Run with -d:gen_master to create it."
    quit(1)
