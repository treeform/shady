import chroma, shady, shady/demo, vmath

proc mandelbrot(gl_FragColor: var Vec4, uv: Vec2, time: Uniform[float32]) =
  var o = vec4(0, 0, 0, 0)
  var zoom = (uv / 700.0 - 0.2) * (1.0 + cos(time))
  while o.w < 98.0:
    o.w += 1
    let v = 0.55f - mat2(-o.y, o.x, o.x, o.y) * vec2(o.y, o.x) + zoom
    o.x = v.x
    o.y = v.y
  gl_FragColor = vec4(o.x + 1f, o.y, 0, 1.0)

proc mandelbrotInner(zoom: Vec2): Vec2 =
  var o = vec2(0, 0)
  var w = 0.0
  while w < 98.0:
    w += 1
    let v = 0.55f - mat2(-o.y, o.x, o.x, o.y) * vec2(o.y, o.x) + zoom
    o.x = v.x
    o.y = v.y
  return o

proc mandelbrotSmooth(fragColor: var Vec4, uv: Vec2, time: Uniform[float32]) =
  var a: Vec2
  var samples = 8
  for x in 0 ..< samples:
    for y in 0 ..< samples:
      let pos = uv + vec2(x.float32, y.float32) / samples.float32
      var zoom = (pos / 700.0 - 0.2) * (2.0 / pow(2, time))
      a += mandelbrotInner(zoom)
  a = a / (samples * samples).float32
  var b = 0.0
  if a.x < 0 and a.y < 0:
    b = - a.x - a.y
  fragColor = vec4(a.x + 1f, a.y, b, 1)

var shader = toGLSL(mandelbrotSmooth)
echo shader

run("Mandelbrot", shader)
