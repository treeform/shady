import chroma, shady, shady/demo, vmath

## From: https://www.shadertoy.com/view/sllXRM

proc to_rgb(ycbcr: Vec3): Vec3 =
  # full range bt709 matrix
  let c709 = mat3(
    1.0000000000, 1.0000000000, 1.0000000000,
    0.0000000000, -0.1873242729, 1.8556000000,
    1.5748000000, -0.4681242729, 0.0000000000,
  )
  return c709 * ycbcr

proc rot(uv: Vec2, r: float): Vec2 =
  var
    s = sin(r)
    c = cos(r)
  return vec2(uv.x*c-uv.y*s, uv.x*s+uv.y*c)

proc vsphere(x: float): Vec2 =
  return vec2(sin(x*PI), cos(x*PI))

proc colors(fragColor: var Vec4, uv: Vec2, time: Uniform[float32]) =

  var pos = (uv) / 300.0

  pos = rot(pos, time*PI*0.5)
  var inv = 1.0/length(pos)
  pos *= inv

  var cbcr = vsphere(pos.x+time)*sin(time*0.5)*0.5

  var col = to_rgb(vec3(inv*0.3.float32, cbcr.x, cbcr.y))*inv*0.5
  fragColor = vec4(col.x, col.y, col.z, 1.0)

# test on the CPU:
var testColor: Vec4
colors(testColor, vec2(100, 100), 0.0)
echo testColor

# compile to a GPU shader:
var shader = toGLSL(colors)
echo shader

run("colors", shader)
