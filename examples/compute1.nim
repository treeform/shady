import opengl, pixie/demo, shady, shady/compute

initOffscreenWindow()

# Setup the uniforms.
var inputCommandBuffer*: Uniform[SamplerBuffer]
var outputImageBuffer*: UniformWriteOnly[UImageBuffer]
var dimensions*: Uniform[IVec4] # ivec4(width, height, 0, 0)

# The shader itself.
proc commandsToImage() =
  var pos = gl_GlobalInvocationID
  for x in 0 ..< dimensions.x:
    pos.x = x.uint32
    let value = uint32(texelFetch(inputCommandBuffer, int32(pos.x)).x)
    #echo pos.x, " ", value
    let colorValue = uvec4(
      128,
      0,
      value,
      255
    )
    imageStore(outputImageBuffer, int32(pos.y * uint32(dimensions.x) + pos.x), colorValue)

# Setup the input and output data.
for i in 0 ..< 256:
  inputCommandBuffer.data.add(i.float32)
outputImageBuffer.image = newImage(256, 256)
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

  # Run the shader.
  glDispatchCompute(
    invocationSize.x.GLuint,
    invocationSize.y.GLuint,
    invocationSize.z.GLuint
  )
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

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
runComputeOnCpu(commandsToImage, uvec3(1, outputImageBuffer.image.height.uint32, 1))
outputImageBuffer.image.writeFile("examples/compute1_output_cpu.png")

# Just in case clear the image before running GPU.
outputImageBuffer.image.fill(rgbx(0, 0, 0, 0))

# Run it on the GPU.
runComputeOnGpu(commandsToImage, uvec3(1, outputImageBuffer.image.height.uint32, 1))
outputImageBuffer.image.writeFile("examples/compute1_output_gpu.png")
