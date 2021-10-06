{.
  passC: "-D_GLFW_COCOA",
  passL: "-framework Cocoa -framework OpenGL -framework Metal -framework QuartzCore",
  compile: "triangle_metal.m",
.}
import staticglfw, print

proc metalSetup(window: clong, shader: cstring): cint {.importc.}
proc metalDraw(width: cint, height: cint): cint {.importc.}


print sizeof(pointer)
print sizeof(clong)
#discard main2()

var
  window: Window

proc start(title, shader: string) =
  # Init GLFW
  if init() == 0:
    raise newException(Exception, "Failed to Initialize GLFW")

  # Open window.
  windowHint(CLIENT_API, NO_API);
  window = createWindow(500, 500, title, nil, nil)
  # Connect the GL context.
  window.makeContextCurrent()

  print window.getCocoaWindow()
  print metalSetup(window.getCocoaWindow(), shader)

proc run*(title, shader: string) =

  let
    metalHeader = """
#include <metal_stdlib>
using namespace metal;
"""
    vertexShader = """
vertex float4 vertexShader(
  constant float4* in [[buffer(0)]],
  uint vid [[vertex_id]])
{
  return in[vid];
}
    """
#     fragmentShader = """
# #define vec4 float4
# fragment
# float4 fragmentShader(
#   float4 input [[stage_in]])
# {
#   float4 result;
#   result = vec4(1, 0, 0, 1);
#   return result;
# }
#     """

  start(title, metalHeader & vertexShader & shader)

  # When running native code we can block in an infinite loop.
  while windowShouldClose(window) == 0:

    var
      width, height: cint
    window.getFramebufferSize(width.addr, height.addr);
    discard metalDraw(width, height)

    # Check for events.
    pollEvents()

    # If you get ESC key quit.
    if window.getKey(KEY_ESCAPE) == 1:
      window.setWindowShouldClose(1)

import shady, vmath
proc circle(gl_FragColor: var Vec4, uv: Vec2, time: Uniform[float32]) =
  var radius = 300.0 + 100 * sin(time)
  if uv.length < radius:
    gl_FragColor = vec4(1, 1, 1, 1)
  else:
    gl_FragColor = vec4(0, 0, 0, 1)

proc fragmentShader(input: StageIn[Vec4]): Vec4 =
  #return vec4(0, 1, 0, 1)

  var time = 1.0
  var uv = vec2(0, 0)
  var radius = 300.0 + 100 * sin(time)
  if uv.length < radius:
    return vec4(1, 1, 1, 1)
  else:
    return vec4(0, 0, 0, 1)

var shader = toMetal(fragmentShader, qualification = "fragment")
echo shader

run("test", shader)
