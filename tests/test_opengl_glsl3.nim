when defined(shadyRunOpenGL):
  import opengl, shady, shady/compute, vmath

  proc compileStage(kind: GLenum, source, label: string): GLuint =
    result = glCreateShader(kind)
    var sourceArray = allocCStringArray([source])
    defer: deallocCStringArray(sourceArray)
    glShaderSource(result, 1.GLsizei, sourceArray, nil)
    glCompileShader(result)

    var ok: GLint
    glGetShaderiv(result, GL_COMPILE_STATUS, ok.addr)
    if ok == 0:
      raise newException(
        Exception,
        label & " shader failed:\n" &
          getErrorLog(result, label, glGetShaderiv, glGetShaderInfoLog)
      )

  proc compileProgram(vertexSource, fragmentSource: string): GLuint =
    let vertexShader = compileStage(GL_VERTEX_SHADER, vertexSource, "glsl3.vert")
    let fragmentShader = compileStage(GL_FRAGMENT_SHADER, fragmentSource, "glsl3.frag")
    result = glCreateProgram()
    glAttachShader(result, vertexShader)
    glAttachShader(result, fragmentShader)
    glLinkProgram(result)

    var ok: GLint
    glGetProgramiv(result, GL_LINK_STATUS, ok.addr)
    if ok == 0:
      raise newException(
        Exception,
        "GLSL3 program failed:\n" &
          getErrorLog(result, "glsl3.program", glGetProgramiv, glGetProgramInfoLog)
      )

  proc enableAttribute(
    program: GLuint,
    name: string,
    size: GLint,
    stride: GLsizei,
    offset: int
  ) =
    let location = glGetAttribLocation(program, name.cstring)
    doAssert location >= 0
    glEnableVertexAttribArray(location.GLuint)
    glVertexAttribPointer(
      location.GLuint,
      size,
      cGL_FLOAT,
      GL_FALSE,
      stride,
      cast[pointer](offset)
    )

  var atlas: Uniform[Sampler2d]

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

  proc texturedFragment(
    fragmentUv: Vec2,
    fragmentColor: Vec4,
    fragColor: var Vec4
  ) =
    let texColor = texture(atlas, fragmentUv)
    fragColor = controlTint(texColor, fragmentColor)

  initOffscreenWindow(ivec2(32, 32))

  let program = compileProgram(
    toShader(layoutVertex, glsl3Desktop, shaderVertex),
    toShader(texturedFragment, glsl3Desktop, shaderFragment)
  )

  var vertexArray: GLuint
  glGenVertexArrays(1, vertexArray.addr)
  glBindVertexArray(vertexArray)

  let vertices = [
    -1.0'f32, -1.0'f32, 0.0'f32, 0.5'f32, 0.5'f32, 1.0'f32, 0.75'f32, 1.0'f32, 1.0'f32,
     3.0'f32, -1.0'f32, 0.0'f32, 0.5'f32, 0.5'f32, 1.0'f32, 0.75'f32, 1.0'f32, 1.0'f32,
    -1.0'f32,  3.0'f32, 0.0'f32, 0.5'f32, 0.5'f32, 1.0'f32, 0.75'f32, 1.0'f32, 1.0'f32
  ]

  var vertexBuffer: GLuint
  glGenBuffers(1, vertexBuffer.addr)
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    vertices.len * sizeof(float32),
    unsafeAddr vertices[0],
    GL_STATIC_DRAW
  )

  const stride = (9 * sizeof(float32)).GLsizei
  enableAttribute(program, "position", 3, stride, 0)
  enableAttribute(program, "uv", 2, stride, 3 * sizeof(float32))
  enableAttribute(program, "vertexColor", 4, stride, 5 * sizeof(float32))

  var textureId: GLuint
  var pixels = [0'u8, 255'u8, 0'u8, 255'u8]
  glGenTextures(1, textureId.addr)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, textureId)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_RGBA.GLint,
    1,
    1,
    0,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    pixels[0].addr
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)

  glViewport(0, 0, 32, 32)
  glClearColor(0, 0, 0, 1)
  glClear(GL_COLOR_BUFFER_BIT)
  glUseProgram(program)
  let atlasLocation = glGetUniformLocation(program, "atlas")
  doAssert atlasLocation >= 0
  glUniform1i(atlasLocation, 0)
  glDrawArrays(GL_TRIANGLES, 0, 3)
  glFinish()

  var pixel: array[4, uint8]
  glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel[0].addr)
  doAssert pixel[0] in 15'u8 .. 45'u8
  doAssert pixel[1] in 170'u8 .. 210'u8
  doAssert pixel[2] in 45'u8 .. 85'u8
  doAssert pixel[3] > 200

  echo "OpenGL GLSL3 execution test passed"
else:
  echo "OpenGL GLSL3 execution test skipped; run with -d:shadyRunOpenGL"
