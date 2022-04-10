import opengl, vmath, chroma, pixie, shady, shady/compute, bumpy, print, times, strutils
import pixie/paths {.all.}
import xmlparser, xmltree

initOffscreenWindow(ivec2(900, 900))

# Setup the uniforms.
var inputCommandBuffer*: Uniform[SamplerBuffer]
var outputImageBuffer*: UniformWriteOnly[UImageBuffer]
var dimensions*: Uniform[IVec4] # ivec4(width, height, aa, 0)



proc blendAlpha*(backdrop, source: float32): float32 {.inline.} =
  ## Blends alphas of backdrop, source.
  source + ((backdrop * (1 - source)))

proc blendNormal*(backdrop, source: Vec4): Vec4 =
  # if backdrop.a == 0 or source.a == 1:
  #   return source
  # if source.a == 0:
  #   return backdrop
  #let k = (1 - source.a)
    # result.r = source.r + ((backdrop.r * k))
  # result.g = source.g + ((backdrop.g * k))
  # result.b = source.b + ((backdrop.b * k))
  # result.a = blendAlpha(backdrop.a, source.a)

  result = source + backdrop * (1 - source.a)

var
  ip: int32 = 0
  hitCount: int32 = 0
  hits: array[128, float32]
  hitsWinding: array[128, int32]
  colorBuffer: array[900, Vec4]
  alphas: array[900, float32]

proc readInt(): uint32 =
  result = uint32(texelFetch(inputCommandBuffer, ip).x)
  ip += 1

proc readFloat(): float32 =
  result = texelFetch(inputCommandBuffer, ip).x
  ip += 1

proc writeColor(pos: Vec2, color: Vec4) =
  imageStore(
    outputImageBuffer,
    int32(pos.y.uint32 * uint32(dimensions.x) + pos.x.uint32),
    (color * 255).uvec4
  )

const
  epsilon = 0.0001 * PI ## Tiny value used for some computations.

proc commandsInner(scanY: float32, aa: Vec2) =

  ip = 0
  hitCount = 0

  while true:
    let opcode = readInt()

    if opcode == 0:
      break

    elif opcode == 1:
      # shape

      let number = readFloat().int
      let minX = readFloat().int
      let maxX = readFloat().int


      let ipStart = ip

      let numAA = 5

      for x in minX ..< maxX:
        alphas[x] = 0

      for aaLine in 0 ..< numAA:
        var yAAOffset = (aaLine.float32 + 0.5) / numAA.float32
        ip = ipStart
        for i in 0 ..< number:
          let
            at = vec2(readFloat(), readFloat() + yAAOffset)
            to = vec2(readFloat(), readFloat() + yAAOffset)
            winding = readFloat()
            m = (at.y - to.y) / (at.x - to.x)
            b = at.y - m * at.x

          if scanY <= at.y or scanY > to.y:
            discard
          else:
            var x: float32 = 0
            if abs(at.x - to.x) < epsilon:
              x = at.x
            else:
              x = ((scanY - b) / m)

            hits[hitCount] = x
            hitsWinding[hitCount] = winding.int32
            hitCount += 1

            # insertion sort
            var i = hitCount - 1
            while i != 0:
              if hits[i - 1] > hits[i]:
                let tmp = hits[i - 1]
                hits[i - 1] = hits[i]
                hits[i] = tmp

                let tmpWinding = hitsWinding[i - 1]
                hitsWinding[i - 1] = hitsWinding[i]
                hitsWinding[i] = tmpWinding

                i -= 1
              else:
                break

        # ------ x jumper
        if hitCount > 0:

          #echo hitCount

          var atHit = 0
          while atHit < hitCount:
            #echo "atHit 1 ", atHit
            var
              pen = hitsWinding[atHit]
              xAt = hits[atHit]
              xTo = 0f
            atHit += 1

            while true:
              #echo "atHit 2 ", atHit
              pen += hitsWinding[atHit]
              xTo = hits[atHit]
              atHit += 1
              if pen == 0:
                break
              if atHit >= hitCount:
                break

            if floor(xAt).int32 == floor(xTo).int32:
              alphas[floor(xAt).int32] += xTo - xAt
            else:
              alphas[floor(xAt).int32] += (ceil(xAt) - xAt)
              alphas[floor(xTo).int32] += (xTo - floor(xTo))
            for x in (xAt + 1).int32 ..< xTo.int32:
              alphas[x] += 1.0

          hitCount = 0

      # fill
      let fillColor = vec4(
        readFloat(),
        readFloat(),
        readFloat(),
        readFloat()
      )

      for x in minX ..< maxX:
        colorBuffer[x] = blendNormal(colorBuffer[x], fillColor * alphas[x] / numAA.float32)


    elif opcode == 3:
      let
        yMin = readFloat() + aa.y
        yMax = readFloat() + aa.y
        label = readFloat()

      # if scanY >= 450 and scanY <= 451:
      #   echo "here ", scanY + aa.y, " -> ", yMin, " ... ", yMax

      if scanY < yMin or scanY >= yMax:
        # if scanY == 450:
        #   echo "skip"
        ip = label.int32

    # else:
    #   echo "unknown op code: ", opcode


# The shader itself.
proc commandsToImage() =
  let
    pos = gl_GlobalInvocationID

  # ---- just solid red
  # for x in 0 ..< dimensions.x:
  #   writeColor(vec2(x.float32, pos.y.float32), vec4(1, 0, 0, 1))

  # ----- without AA
  for x in 0 ..< dimensions.x:
    colorBuffer[x] = vec4(0, 0, 0, 0)
  commandsInner(pos.y.float32, vec2(0, 0.5))
  # write colorBufferAA to image
  for x in 0 ..< dimensions.x:
    writeColor(vec2(x.float32, pos.y.float32), colorBuffer[x])

  # # ----- with AA
  # for x in 0 ..< dimensions.x:
  #   colorBufferAA[x] = vec4(0, 0, 0, 0)

  # var aa = 5
  # for aaY in 0 ..< aa:
  #   # clear buffer
  #   for x in 0 ..< dimensions.x:
  #     colorBuffer[x] = vec4(0, 0, 0, 0)

  #   commandsInner(pos.y.float32, vec2(0.float32, aaY.float32 + 0.5) / aa.float32)
  #   #echo vec2(0.float32, aaY.float32 + 0.5) / aa.float32

  #   # write colorBuffer to colorBufferAA
  #   for x in 0 ..< dimensions.x:
  #     colorBufferAA[x] += colorBuffer[x]

  # # write colorBufferAA to image
  # for x in 0 ..< dimensions.x:
  #   writeColor(vec2(x.float32, pos.y.float32), colorBufferAA[x]/(aa).float32)

proc commandFinish() =
  inputCommandBuffer.data.add(0)

proc commandLine(at, to: Vec2, winding: int16) =
  inputCommandBuffer.data.add(at.x)
  inputCommandBuffer.data.add(at.y)
  inputCommandBuffer.data.add(to.x)
  inputCommandBuffer.data.add(to.y)
  inputCommandBuffer.data.add(winding.float32)

proc commandFill(color: Color) =
  inputCommandBuffer.data.add(color.r)
  inputCommandBuffer.data.add(color.g)
  inputCommandBuffer.data.add(color.b)
  inputCommandBuffer.data.add(color.a)

proc commandSkipBoundsGoto(rect: Rect): int =
  inputCommandBuffer.data.add(3)
  inputCommandBuffer.data.add(rect.y.floor())
  inputCommandBuffer.data.add((rect.y + rect.h).ceil())
  result = inputCommandBuffer.data.len
  inputCommandBuffer.data.add(0)

proc commandSkipBoundsGoto(minY, maxY: float32): int =
  inputCommandBuffer.data.add(3)
  inputCommandBuffer.data.add(minY)
  inputCommandBuffer.data.add(maxY)
  result = inputCommandBuffer.data.len
  inputCommandBuffer.data.add(0)

proc commandSkipBoundsLabel(index: int) =
  inputCommandBuffer.data[index] = inputCommandBuffer.data.len.float32

let start0 = epochTime()

proc linesToCommands() =
  ## lines
  # line(vec2(0, 0), vec2(10, 10))
  # line(vec2(100, 100), vec2(0, 200))

  commandLine(vec2(100, 100), vec2(100, 300), 1)
  commandLine(vec2(300, 100), vec2(300, 300), -1)
  # commandLine(vec2(310, 300), vec2(310, 100), -1)
  #commandLine(vec2(320, 300), vec2(320, 100), -1)
  commandFill(color(1, 0, 0, 1))
  commandFinish()

proc pathToCommands() =
  ## heart
  var heart = parsePath("""
      M 20 60
      A 40 40 90 0 1 100 60
      A 40 40 90 0 1 180 60
      Q 180 120 100 180
      Q 20 120 20 60
      z
    """).commandsToShapes(true, 1.0).shapesToSegments()
  for (seg, w) in heart:
    commandLine(seg.at, seg.to, w)
  commandFill(color(1, 0, 0, 1))
  commandFinish()

proc svgToCommands(filePath: string) =

  proc segmentsToCommands(segments: seq[(Segment, int16)]) =

    #let bounds = segments.computeBounds()
    #let idx = commandSkipBoundsGoto(bounds)
    for (segment, w) in segments:
      if segment.at.y < 32:
        commandLine(segment.at, segment.to, w)
    #commandSkipBoundsLabel(idx)

    # let
    #   bounds = computeBounds(segments).snapToPixels()
    #   startX = max(0, bounds.x.int)
    #   startY = max(0, bounds.y.int)
    #   pathWidth =
    #     if startX < 900:
    #       min(bounds.w.int, 900 - startX)
    #     else:
    #       0
    #   pathHeight = min(900, (bounds.y + bounds.h).int)
    #   partitioning = partitionSegments(segments, startY, pathHeight - startY)

    # var startYPart = partitioning.startY.float32
    # for partition in partitioning.partitions:
    #   let idx = commandSkipBoundsGoto(
    #     startYPart,
    #     startYPart + partitioning.partitionHeight.float32
    #   )
    #   startYPart += partitioning.partitionHeight.float32
    #   for entry in partition.entries:
    #     commandLine(entry.segment.at, entry.segment.to, entry.winding)
    #   commandSkipBoundsLabel(idx)


  let data = readFile(filePath)
  let root = parseXml(data)
  let mat = mat3(
    1.7656463, 0, 0,
    0, 1.7656463, 0,
    324.90716, 255.00942, 1
  )
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
            let segments = path.commandsToShapes(true, 1.0).shapesToSegments()
            segments.segmentsToCommands()
            commandFill(parseHtmlColor(fillColor))
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
            let segments = path.commandsToShapes(false, 1.0).strokeShapes(
              strokeWidth,
              ButtCap,
              MiterJoin,
              defaultMiterLimit,
              @[],
              1.0
            ).shapesToSegments()
            segments.segmentsToCommands()
            commandFill(parseHtmlColor(strokeColor))
  commandFinish()



proc svgToCommands2(filePath: string) =
  ## tiger
  ##
  let scanHeight = 16.float32
  let data = readFile(filePath)
  let root = parseXml(data)
  let mat = mat3(
    1, 0, 0,
    0, 1, 0,
    0, 0, 1
  )

  type
    ShapeScan = object
      lines: seq[(Vec2, Vec2, int16)]
      color: Color

  var scanGroups = newSeq[seq[ShapeScan]](ceil(900/scanHeight).int)


  proc makeShapeScan(segments: seq[(Segment, int16)], color: Color) =
    for y in 0 ..< ceil(900/scanHeight).int:
      let yMin = y.float32 * scanHeight
      let yMax = (y.float32 + 1) * scanHeight
      var shapeScan = ShapeScan()
      for (segment, w) in segments:
        if segment.at.y < yMax and segment.to.y > yMin:
          shapeScan.lines.add((segment.at, segment.to, w))
      shapeScan.color = color
      if shapeScan.lines.len > 0:
        scanGroups[y].add(shapeScan)

  proc processNode(node: XMLNode) =
    #echo "tag: ", node.tag
    case node.tag:
      of "svg":
        for child in node:
          processNode(child)
      of "path":
        #echo "..", node.tag
        #echo "  ", node.attr("fill")

        let fillColor = node.attr("fill")
        if fillColor != "":
          #echo "   ", node.attr("d")
          var path = parsePath(node.attr("d"))
          path.transform(mat)
          let segments = path.commandsToShapes(true, 1.0).shapesToSegments()
          makeShapeScan(
            segments,
            parseHtmlColor(fillColor)
          )

        let
          strokeColor = node.attr("stroke")
          strokeWidth = node.attr("stroke-width")
        if strokeColor != "":
          var path = parsePath(node.attr("d"))
          path.transform(mat)
          var strokeWidth =
            if strokeWidth != "":
              parseFloat(strokeWidth).float32
            else:
              1.0.float32
          let segments = path.commandsToShapes(false, 1.0).strokeShapes(
            strokeWidth,
            ButtCap,
            MiterJoin,
            defaultMiterLimit,
            @[],
            1.0
          ).shapesToSegments()
          makeShapeScan(
            segments,
            parseHtmlColor(strokeColor)
          )

  processNode(root)

  for y, scanGroup in scanGroups:
    let yMin = y.float32 * scanHeight
    let yMax = (y.float32 + 1) * scanHeight
    let idx = commandSkipBoundsGoto(yMin, yMax)
    for shapeScan in scanGroup:
      inputCommandBuffer.data.add(1) # shape
      inputCommandBuffer.data.add(shapeScan.lines.len.float32)
      var minX = shapeScan.lines[0][0].x
      var maxX = shapeScan.lines[0][0].x
      for line in shapeScan.lines:
        minX = min(minX, min(line[0].x, line[1].x))
        maxX = max(maxX, max(line[0].x, line[1].x))
      # x bounds
      inputCommandBuffer.data.add(minX.floor)
      inputCommandBuffer.data.add(maxX.ceil)
      for line in shapeScan.lines:
        commandLine(line[0], line[1], line[2])
      commandFill(shapeScan.color)
    commandSkipBoundsLabel(idx)
  commandFinish()

proc nothingCommands() =
  commandFinish()

# linesToCommands()
# pathToCommands()
# svgToCommands("examples/data/tiger.svg")
svgToCommands2("examples/data/tiger_no_group.svg")
# svgToCommands2("examples/data/wad_of_text.svg")
# svgToCommands2("examples/data/shape.svg")

nothingCommands()

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
  glMemoryBarrier(GL_ALL_BARRIER_BITS)
  # echo "gpu barrier:", (epochTime() - start2) * 1000, "ms"

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
  echo "gpu finish:", (epochTime() - start2) * 1000, "ms"

# Run it on CPU.
let start = epochTime()
runComputeOnCpu(commandsToImage, uvec3(1, outputImageBuffer.image.height.uint32, 1))
echo "cpu finish:", (epochTime() - start) * 1000, "ms"
outputImageBuffer.image.writeFile("examples/svg_cpu_aa.png")

# Just in case clear the image before running GPU.
outputImageBuffer.image.fill(rgbx(0, 0, 0, 0))
# Run it on the GPU.


runComputeOnGpu(commandsToImage, uvec3(1, outputImageBuffer.image.height.uint32, 1))
outputImageBuffer.image.writeFile("examples/svg_gpu_aa.png")
