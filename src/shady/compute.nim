import macros, opengl, shady, windy, strformat, strutils, vmath

macro compute*(n: typed) =
  echo n.repr
  echo n[0].repr
  echo toGLSLInner(
    n[0],
    "#version 430",
    "layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;"
  )
  let params = n[0].getImpl()[3]
  echo n[0].getImpl()[3].treeRepr
  for i, c in n:
    if i == 0: continue
    echo i-1, ": ", params[i].repr, " = ", c.repr

  echo "run the shader"

  echo "copy the buffers back"

var
  windowInitialized = false
  window: Window
proc initOffscreenWindow*(size = ivec2(100, 100)) =
  ## Makes sure there is an off screen openGL window.
  if windowInitialized == false:
    window = newWindow(
      title = "Shady hidden window",
      size = size,
      # style = Undecorated,
      visible = false,
      openglMajorVersion = 4,
      openglMinorVersion = 5,
    )
    window.makeContextCurrent()
    loadExtensions()
    windowInitialized = true

proc getErrorLog*(
  id: GLuint,
  path: string,
  lenProc: typeof(glGetShaderiv),
  strProc: typeof(glGetShaderInfoLog)
): string =
  ## Gets the error log from compiling or linking shaders.
  var length: GLint = 0
  lenProc(id, GL_INFO_LOG_LENGTH, length.addr)
  var log = newString(length.int)
  strProc(id, length, nil, log)
  when defined(emscripten):
    result = log
  else:
    if log.startsWith("Compute info"):
      log = log[25..^1]
    let
      clickable = &"{path}({log[2..log.find(')')]}"
    result = &"{clickable}: {log}"

proc compileComputeShader*(compute: (string, string)): GLuint =
  ## Compiles the compute shader and returns the program id.
  var computeShader: GLuint

  block:
    var computeShaderArray = allocCStringArray([compute[1]])
    defer: dealloc(computeShaderArray)

    var isCompiled: GLint

    computeShader = glCreateShader(GL_COMPUTE_SHADER)
    glShaderSource(computeShader, 1, computeShaderArray, nil)
    glCompileShader(computeShader)
    glGetShaderiv(computeShader, GL_COMPILE_STATUS, isCompiled.addr)

    if isCompiled == 0:
      echo "Compute shader compilation failed:"
      echo getErrorLog(
        computeShader, compute[0], glGetShaderiv, glGetShaderInfoLog
      )
      quit()

  result = glCreateProgram()
  glAttachShader(result, computeShader)

  glLinkProgram(result)

  var isLinked: GLint
  glGetProgramiv(result, GL_LINK_STATUS, isLinked.addr)
  if isLinked == 0:
    echo "Linking compute shader failed:"
    echo getErrorLog(
      result, compute[0], glGetProgramiv, glGetProgramInfoLog
    )
    quit()

var gl_GlobalInvocationID*: UVec3

proc runComputeOnCpu*(computeShader: proc(), invocationSize: UVec3) =
  for z in 0 ..< invocationSize.z:
    for y in 0 ..< invocationSize.y:
      for x in 0 ..< invocationSize.x:
        gl_GlobalInvocationID = uvec3(x, y, z)
        computeShader()
