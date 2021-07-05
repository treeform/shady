import shadytoy, shady, chroma, vmath

proc mandelbrot(gl_FragColor: var Color, uv: Vec2) =
  var o = vec4(0, 0, 0, 0)
  while o.w < 98.0:
    o.w += 1
    let v: Vec2 = 0.55f - mat2(-o.y, o.x, o.x, o.y) * vec2(o.y, o.x) + (uv / 700.0 - 0.2) * (1.0 + cos(0.1))
    o.x = v.x
    o.y = v.y
  gl_FragColor = color(o.x + 1f, o.y, 0, 1.0)

var shader = toShader(mandelbrot)
echo shader

run("Mandelbrot", shader)
