import opengl, vmath, chroma, pixie, shady, shady/compute, bumpy, print, times, strutils
import pixie/paths {.all.}

initOffscreenWindow(ivec2(900, 900))

# Setup the uniforms.
var inputCommandBuffer*: Uniform[SamplerBuffer]
var outputImageBuffer*: UniformWriteOnly[UImageBuffer]
var dimensions*: Uniform[IVec4] # ivec4(width, height, 0, 0)

var
  ip: int32 = 0
  hitCount: int32 = 0
  hits: array[64, int32]

proc readInt(): uint32 =
  result = uint32(texelFetch(inputCommandBuffer, ip).x)
  ip += 1

proc readFloat(): float32 =
  result = texelFetch(inputCommandBuffer, ip).x
  ip += 1

proc writeColor(pos: Vec2, color: Vec4) =
  let colorValue = uvec4(
    (color.x * 255).uint32,
    (color.y * 255).uint32,
    (color.z * 255).uint32,
    (color.w * 255).uint32
  )
  imageStore(
    outputImageBuffer,
    int32(pos.y.uint32 * uint32(dimensions.x) + pos.x.uint32),
    colorValue
  )

const
  epsilon = 0.0001 * PI ## Tiny value used for some computations.

# The shader itself.
proc commandsToImage() =
  let
    pos = gl_GlobalInvocationID
    scanY = pos.y.float32

  ip = 0
  hitCount = 0

  while true:
    let opcode = readInt()
    # echo "got opcode", opcode

    if opcode == 0:
      break

    if opcode == 2:
      # fill
      let fillColor = vec4(
        readFloat(),
        readFloat(),
        readFloat(),
        readFloat()
      )

      if hitCount > 0:
        var
          atHit = 1
          x = hits[0]
        while x < dimensions.x:
          if x >= hits[atHit]:
            x = hits[atHit + 1]
            atHit += 2
            if atHit > hitCount:
              break
          let pos = uvec2(x.uint32, pos.y).vec2
          writeColor(pos, fillColor)
          x += 1
        hitCount = 0

    if opcode == 1:
      let
        at = vec2(readFloat(), readFloat())
        to = vec2(readFloat(), readFloat())
        m = (at.y - to.y) / (at.x - to.x)
        b = at.y - m * at.x

      if scanY <= min(at.y, to.y) or scanY > max(at.y, to.y):
        discard
      else:
        var x: int32 = 0
        if abs(at.x - to.x) < epsilon:
          x = at.x.int32
        else:
          x = ((scanY - b) / m).int32
        hits[hitCount] = x
        hitCount += 1

        # insertion sort
        var i = hitCount - 1
        while i != 0:
          if hits[i - 1] > hits[i]:
            let tmp = hits[i - 1]
            hits[i - 1] = hits[i]
            hits[i] = tmp
            i -= 1
          else:
            break

proc line(at, to: Vec2) =
  inputCommandBuffer.data.add(1)
  inputCommandBuffer.data.add(at.x)
  inputCommandBuffer.data.add(at.y)
  inputCommandBuffer.data.add(to.x)
  inputCommandBuffer.data.add(to.y)

proc fill(color: Color) =
  inputCommandBuffer.data.add(2)
  inputCommandBuffer.data.add(color.r)
  inputCommandBuffer.data.add(color.g)
  inputCommandBuffer.data.add(color.b)
  inputCommandBuffer.data.add(color.a)

proc finish() =
  inputCommandBuffer.data.add(0)

## lines
# line(vec2(0, 0), vec2(10, 10))
# line(vec2(100, 100), vec2(0, 200))

## heart
# var heart = parsePath("""
#     M 20 60
#     A 40 40 90 0 1 100 60
#     A 40 40 90 0 1 180 60
#     Q 180 120 100 180
#     Q 20 120 20 60
#     z
#   """).commandsToShapes().shapesToSegments()
# for (seg, w) in heart:
#   line(seg.at, seg.to)
# fill(color(1, 0, 0, 1))
# finish()


## tiger
import xmlparser, xmltree
let data = readFile("examples/data/tiger.svg")
let root = parseXml(data)
let mat = mat3(
  1.7656463, 0, 0,
  0, 1.7656463, 0,
  324.90716, 255.00942, 1
)
let start0 = epochTime()
for node in root:
  #echo ".", node.tag
  for node in node:
    #echo "..", node.tag
    #echo "  ", node.attr("fill")
    let fillColor = node.attr("fill")
    if fillColor != "":
      for node in node:
        #echo "...", node.tag
        if node.tag == "path":
          #echo "   ", node.attr("d")
          var path = parsePath(node.attr("d"))
          path.transform(mat)
          let segs = path.commandsToShapes(true, 1.0).shapesToSegments()
          for (seg, w) in segs:
            line(seg.at, seg.to)
          fill(parseHtmlColor(fillColor))
    let
      strokeColor = node.attr("stroke")
      strokeWidth = node.attr("stroke-width")
    if strokeColor != "":
      for node in node:
        #echo "...", node.tag
        if node.tag == "path":
          #echo "   ", node.attr("d")
          var path = parsePath(node.attr("d"))
          path.transform(mat)
          var strokeWidth =
            if strokeWidth != "":
              parseFloat(strokeWidth).float32
            else:
              1.0.float32
          let segs = path.commandsToShapes(true, 1.0).strokeShapes(
            strokeWidth,
            lcButt,
            ljMiter,
            defaultMiterLimit,
            @[],
            1.0
          ).shapesToSegments()
          for (seg, w) in segs:
            line(seg.at, seg.to)
          fill(parseHtmlColor(strokeColor))
finish()
echo "buffer:", (epochTime() - start0) * 1000, "ms"


outputImageBuffer.image = newImage(900, 900)
dimensions = ivec4(
  outputImageBuffer.image.width.int32,
  outputImageBuffer.image.height.int32,
  0,
  0
)

template runComputeOnGpu(computeShader: proc(), invocationSize: UVec3) =

  let computeShaderSrc = toGLSL(
    computeShader,
    "430",
    extra = "layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;\n"
  )

  writeFile("examples/compute1_sh.comp", computeShaderSrc)

  var shaderId = compileComputeShader((
    "examples/compute1_sh.comp",
    computeShaderSrc
  ))
  glUseProgram(shaderId)

  # Setup outputImageBuffer.
  var
    outputBufferId: GLuint
    outputTextureId: GLuint
  glGenBuffers(1, outputBufferId.addr)
  glBindBuffer(GL_TEXTURE_BUFFER, outputBufferId)
  glBufferData(GL_TEXTURE_BUFFER, outputImageBuffer.image.data.len * 4, nil, GL_STATIC_DRAW)
  let outputImageBufferLoc = glGetUniformLocation(shaderId, "outputImageBuffer")
  glUniform1i(outputImageBufferLoc, 0)
  glActiveTexture(GL_TEXTURE0)
  glGenTextures(1, outputTextureId.addr)
  glBindTexture(GL_TEXTURE_BUFFER, outputTextureId)
  glTexBuffer(GL_TEXTURE_BUFFER, GL_RGBA8UI, outputBufferId)
  glBindImageTexture(
    0,
    outputTextureId,
    0,
    GL_FALSE,
    0,
    GL_WRITE_ONLY,
    GL_RGBA8UI
  )
  glBindTexture(GL_TEXTURE_BUFFER, outputTextureId)

  # Setup inputCommandBuffer.
  var
    inputCommandBufferId: GLuint
    commandTextureId: GLuint
  glGenTextures(1, commandTextureId.addr)
  glActiveTexture(GL_TEXTURE1)
  glGenBuffers(1, inputCommandBufferId.addr)
  let byteLength = inputCommandBuffer.data.len * 4
  glBindBuffer(GL_TEXTURE_BUFFER, inputCommandBufferId)
  glBufferData(
    GL_TEXTURE_BUFFER,
    byteLength,
    inputCommandBuffer.data[0].addr,
    GL_STATIC_DRAW
  )
  glBindTexture(GL_TEXTURE_BUFFER, commandTextureId)
  glTexBuffer(
    GL_TEXTURE_BUFFER,
    GL_R32F,
    inputCommandBufferId
  )
  glBindTexture(GL_TEXTURE_BUFFER, commandTextureId)
  let inputCommandBufferLoc = glGetUniformLocation(shaderId, "inputCommandBuffer")
  glUniform1i(inputCommandBufferLoc, 1)

  # Setup dimensions uniform.
  let dimensionsLoc = glGetUniformLocation(shaderId, "dimensions")
  glUniform4i(dimensionsLoc, dimensions.x, dimensions.y, dimensions.z, dimensions.w)

  let start2 = epochTime()
  # Run the shader.
  glDispatchCompute(
    invocationSize.x.GLuint,
    invocationSize.y.GLuint,
    invocationSize.z.GLuint
  )
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)
  echo "gpu finish:", (epochTime() - start2) * 1000, "ms"

  # Read back the outputImageBuffer.
  let p = cast[ptr UncheckedArray[uint8]](
    glMapNamedBuffer(outputBufferId, GL_READ_ONLY)
  )
  copyMem(
    outputImageBuffer.image.data[0].addr,
    p,
    outputImageBuffer.image.data.len * 4
  )
  discard glUnmapNamedBuffer(outputBufferId)

# Run it on CPU.
let start = epochTime()
runComputeOnCpu(commandsToImage, uvec3(1, outputImageBuffer.image.height.uint32, 1))
echo "cpu finish:", (epochTime() - start) * 1000, "ms"
outputImageBuffer.image.writeFile("examples/svg_cpu.png")

# Just in case clear the image before running GPU.
outputImageBuffer.image.fill(rgbx(0, 0, 0, 0))
# Run it on the GPU.

runComputeOnGpu(commandsToImage, uvec3(1, outputImageBuffer.image.height.uint32, 1))
outputImageBuffer.image.writeFile("examples/svg_gpu.png")
