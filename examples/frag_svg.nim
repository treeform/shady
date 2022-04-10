import chroma, shady, vmath

import opengl, shady, windy, times, vmath
let
  vertices: seq[float32] = @[
    -1f, -1f, #1.0f, 0.0f, 0.0f,
    +1f, -1f, #0.0f, 1.0f, 0.0f,
    +1f, +1f, #0.0f, 0.0f, 1.0f,
    +1f, +1f, #1.0f, 0.0f, 0.0f,
    -1f, +1f, #0.0f, 1.0f, 0.0f,
    -1f, -1f, #0.0f, 0.0f, 1.0f
  ]

var
  program: GLuint
  vPosLocation: GLint
  timeLocation: GLint
  window: Window
  startTime: float64
  vertexArrayId: GLuint

proc checkError*(shader: GLuint) =
  var code: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr code)
  if code.GLboolean == GL_FALSE:
    var length: GLint = 0
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr length)
    var log = newString(length.int)
    glGetShaderInfoLog(shader, length, nil, log)
    echo log

proc start(title, vertexShaderText, fragmentShaderText: string) =

  window = newWindow(
      title = "Shady hidden window",
      size = ivec2(900, 900),
      visible = true,
      openglMajorVersion = 4,
      openglMinorVersion = 1,
    )
  # Connect the GL context.
  window.makeContextCurrent()

  when not defined(emscripten):
    # This must be called to make any GL function work
    loadExtensions()

  var vertexShader = glCreateShader(GL_VERTEX_SHADER)
  var vertexShaderTextArr = allocCStringArray([vertexShaderText])
  glShaderSource(vertexShader, 1.GLsizei, vertexShaderTextArr, nil)
  glCompileShader(vertex_shader)
  checkError(vertexShader)

  var fragmentShader = glCreateShader(GL_FRAGMENT_SHADER)
  var fragmentShaderTextArr = allocCStringArray([fragmentShaderText])
  glShaderSource(fragmentShader, 1.GLsizei, fragmentShaderTextArr, nil)
  glCompileShader(fragmentShader)
  checkError(fragment_shader)

  program = glCreateProgram()
  glAttachShader(program, vertexShader)
  glAttachShader(program, fragmentShader)
  glLinkProgram(program)

  vPosLocation = glGetAttribLocation(program, "vPos")
  timeLocation = glGetUniformLocation(program, "time")

  glGenVertexArrays(1, vertexArrayId.addr)
  glBindVertexArray(vertexArrayId)

  var vertexBuffer: GLuint
  glGenBuffers(1, addr vertexBuffer)
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
  glBufferData(
    GL_ARRAY_BUFFER,
    vertices.len * 5 * 4,
    vertices[0].unsafeAddr,
    GL_STATIC_DRAW
  )
  glVertexAttribPointer(
    vPosLocation.GLuint,
    2.GLint,
    cGL_FLOAT,
    GL_FALSE,
    0.GLsizei,
    nil
  )

  glEnableVertexAttribArray(vPosLocation.GLuint)

  startTime = epochTime()

proc display() =
  var ratio: float32

  ratio = window.size.x.float32 / window.size.x.float32
  glViewport(0, 0, window.size.x, window.size.y)
  glClearColor(0, 0, 0, 1)
  glClear(GL_COLOR_BUFFER_BIT)

  glUseProgram(program)
  let now = epochTime() - startTime
  glUniform1f(timeLocation, now.float32)
  glDrawArrays(GL_TRIANGLES, 0, 6)

  # Swap buffers (this will display the red color)
  window.swapBuffers()

proc run*(title, shader: string) =

  proc basicVert(
    gl_Position: var Vec4,
    uv: var Vec2,
    vPos: Vec3
  ) =
    gl_Position = vec4(vPos.x, vPos.y, 0.0, 1.0)
    uv.x = gl_Position.x * 900
    uv.y = gl_Position.y * 900

  const
    vertexShaderText = toGLSL(basicVert)

  start(title, vertexShaderText, shader)

  while not window.closeRequested:
    display()
    pollEvents()


proc flare(fragColor: var Vec4, uv: Vec2, time: Uniform[float32]) =
  var
    c: Vec3
    l: float32
    z = time
  for i in 0 ..< 3:
    var
      p = uv / 500
      pos = p
    z += 0.07
    l = length(p)
    pos += p/l * (sin(z)+1.0) * abs(sin(l*9.0 - z*2.0))
    c[i] = 0.01 / length(abs(vec2(pos) mod vec2(1.0)) - 0.5)
  let v = c/l
  fragColor = vec4(v.x, v.y, v.z, time)

# test on the CPU:
var testColor: Vec4
flare(testColor, vec2(100, 100), 0.0)
echo testColor

# compile to a GPU shader:
var shader = toGLSL(flare)
echo shader

run("flare", shader)
