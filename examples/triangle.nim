import opengl, shady, staticglfw, vmath

var
  vertices: seq[float32] = @[
    -sin(0.toRadians), -cos(0.toRadians), 1.0f, 0.0f, 0.0f,
    -sin(120.toRadians), -cos(120.toRadians), 0.0f, 1.0f, 0.0f,
    -sin(240.toRadians), -cos(240.toRadians), 0.0f, 0.0f, 1.0f
  ]

proc basicVert(
  gl_Position: var Vec4,
  MVP: Uniform[Mat4],
  vCol: Vec3,
  vPos: Vec3,
  vertColor: var Vec3
) =
  gl_Position = MVP * vec4(vPos.x, vPos.y, 0.0, 1.0)
  vertColor = vCol

proc basicFrag(fragColor: var Vec4, vertColor: Vec3) =
  fragColor = vec4(vertColor.x, vertColor.y, vertColor.z, 1.0)

var
  vertexShaderText = toGLSL(basicVert)
  fragmentShaderText = toGLSL(basicFrag)

echo vertexShaderText
echo fragmentShaderText

proc checkError*(shader: GLuint) =
  var code: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr code)
  if code.GLboolean == GL_FALSE:
    var length: GLint = 0
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr length)
    var log = newString(length.int)
    glGetShaderInfoLog(shader, length, nil, log)
    echo log

# Init GLFW
if init() == 0:
  raise newException(Exception, "Failed to Initialize GLFW")

# Open window.
windowHint(SAMPLES, 0)
windowHint(CONTEXT_VERSION_MAJOR, 4)
windowHint(CONTEXT_VERSION_MINOR, 1)
var window = createWindow(500, 500, "GLFW3 WINDOW", nil, nil)
# Connect the GL context.
window.makeContextCurrent()

when not defined(emscripten):
  # This must be called to make any GL function work
  loadExtensions()

var vertexBuffer: GLuint
glGenBuffers(1, addr vertexBuffer)
glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
glBufferData(GL_ARRAY_BUFFER, vertices.len * 5 * 4, addr vertices[0], GL_STATIC_DRAW)

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

var program = glCreateProgram()
glAttachShader(program, vertexShader)
glAttachShader(program, fragmentShader)
glLinkProgram(program)

var vertexArrayId: GLuint
glGenVertexArrays(1, vertexArrayId.addr)
glBindVertexArray(vertexArrayId)

var
  mvpLocation = glGetUniformLocation(program, "MVP").GLuint
  vposLocation = glGetAttribLocation(program, "vPos").GLuint
  vcolLocation = glGetAttribLocation(program, "vCol").GLuint

glVertexAttribPointer(vposLocation, 2.GLint, cGL_FLOAT, GL_FALSE, (5 *
    4).GLsizei, nil)
glEnableVertexAttribArray(vposLocation)

glVertexAttribPointer(vcolLocation, 3.GLint, cGL_FLOAT, GL_FALSE, (5 *
    4).GLsizei, cast[pointer](4*2))
glEnableVertexAttribArray(vcolLocation.GLuint)

var colorFade = 1.0

proc draw() {.cdecl.} =
  var ratio: float32
  var width, height: cint
  var m, p, v, mvp: Mat4
  getFramebufferSize(window, addr width, addr height)
  ratio = width.float32 / height.float32
  glViewport(0, 0, width, height)
  var a = sin(colorFade)*0.2 + 0.20
  glClearColor(a, a, a, 1)
  colorFade += 0.01
  glClear(GL_COLOR_BUFFER_BIT)

  m = rotateZ(getTime().float32)
  v = scale(vec3(1, ratio, 1))
  p = ortho[float32](-1, 1, 1, -1, -1000, 1000)
  mvp = m * v * p

  glUseProgram(program)
  glUniformMatrix4fv(mvpLocation.GLint, 1, GL_FALSE, cast[ptr float32](
      mvp.unsafeAddr))
  glDrawArrays(GL_TRIANGLES, 0, 3)

  # Swap buffers (this will display the red color)
  window.swapBuffers()

proc onResize(handle: staticglfw.Window, w, h: int32) {.cdecl.} =
  draw()
discard window.setFramebufferSizeCallback(onResize)

# When running native code we can block in an infinite loop.
while windowShouldClose(window) == 0:
  draw()

  # Check for events.
  pollEvents()

  # If you get ESC key quit.
  if window.getKey(KEY_ESCAPE) == 1:
    window.setWindowShouldClose(1)
