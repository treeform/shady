import chroma, shady, shady/demo, vmath

proc circle(gl_FragColor: var Vec4, uv: Vec2, time: Uniform[float32]) =
  var radius = 300.0 + 100 * sin(time)
  if uv.length < radius:
    gl_FragColor = vec4(1, 1, 1, 1)
  else:
    gl_FragColor = vec4(0, 0, 0, 1)

# both CPU and GPU code:
proc circleSmooth(fragColor: var Vec4, uv: Vec2, time: Uniform[float32]) =
  var a = 0.0
  var radius = 300.0 + 100 * sin(time)
  for x in 0 ..< 8:
    for y in 0 ..< 8:
      if (uv + vec2(x.float32 - 4.0, y.float32 - 4.0) / 8.0).length < radius:
        a += 1
  a = a / (8 * 8)
  fragColor = vec4(a, a, a, 1)

# test on the CPU:
var testColor: Vec4
circleSmooth(testColor, vec2(100, 100), 0.0)
echo testColor

# compile to a GPU shader:
var shader = toGLSL(circleSmooth)
echo shader

run("Circle", shader)
