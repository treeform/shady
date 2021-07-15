import chroma, shady, shady/demo, vmath

# from https://www.shadertoy.com/view/XsXXDn by 'Danilo Guanabara'

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
