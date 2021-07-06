import benchy, fidget2/buffers, fidget2/shaders, fidget2/textures, opengl, pixie/demo, print, shady

var commandBuf*: Uniform[SamplerBuffer]
var valuesBuf*: UniformWriteOnly[UImageBuffer]
var dimens*: Uniform[IVec4]; # ivec4(width, height, 0, 0)

var gl_GlobalInvocationID*: UVec3

proc computeShader() =
  let pos = gl_GlobalInvocationID
  let colorValue = uvec4(
    0,
    0,
    uint32(texelFetch(commandBuf, int32(pos.x)).x),
    255
  )
  imageStore(valuesBuf, int32(pos.y * uint32(dimens.x) + pos.x), colorValue)

proc main() =

  let computeShaderSrc = toGLSL(
    computeShader,
    "430",
    extra="layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;\n"
  )
  writeFile("examples/compute_sh.comp", computeShaderSrc)

  var
    commandBuffer: Buffer
    commandTexture: Texture
    # float32 int8
    outputImage = newImage(2560, 1448)
    outputBuffer: Buffer
    outputTexture: Texture

  if init() == 0:
    quit("Failed to Initialize GLFW.")
  windowHint(RESIZABLE, false.cint)

  windowHint(OPENGL_FORWARD_COMPAT, GL_TRUE.cint)
  windowHint(OPENGL_PROFILE, OPENGL_CORE_PROFILE)
  windowHint(CONTEXT_VERSION_MAJOR, 4)
  windowHint(CONTEXT_VERSION_MINOR, 5)

  window = createWindow(
    outputImage.width.cint,
    outputImage.height.cint,
    "",
    nil,
    nil
  )
  if window == nil:
    quit("Failed to create window.")
  makeContextCurrent(window)
  loadExtensions()

  var shader = newShader("examples/compute_sh.comp")
  glUseProgram(shader.programId)

  var commands: seq[float32]
  for i in 0 ..< 512:
    commands.add(i.float32)

  commandBuffer = Buffer()
  commandBuffer.count = commands.len
  commandBuffer.target = GL_TEXTURE_BUFFER
  commandBuffer.componentType = cGL_FLOAT
  commandBuffer.kind = bkSCALAR

  commandTexture = Texture()
  commandTexture.internalFormat = GL_R32F
  commandTexture.bindTextureBufferData(commandBuffer, commands[0].addr)

  outputBuffer = Buffer()
  outputBuffer.count = outputImage.data.len
  outputBuffer.target = GL_SHADER_STORAGE_BUFFER
  outputBuffer.componentType = GL_UNSIGNED_BYTE
  outputBuffer.kind = bkVEC4

  glGenBuffers(1, outputBuffer.bufferId.addr)
  print outputBuffer.bufferId
  glBindBuffer(GL_TEXTURE_BUFFER, outputBuffer.bufferId)
  glBufferData(GL_TEXTURE_BUFFER, outputImage.data.len * 4, nil, GL_STATIC_DRAW)

  outputTexture = Texture()
  outputTexture.internalFormat = GL_RGBA8UI
  glGenTextures(1, outputTexture.textureId.addr)
  print outputTexture.textureId
  glBindTexture(GL_TEXTURE_BUFFER, outputTexture.textureId)
  glTexBuffer(GL_TEXTURE_BUFFER, outputTexture.internalFormat, outputBuffer.bufferId)
  glBindImageTexture(
    0,
    outputTexture.textureId,
    0,
    GL_FALSE,
    0,
    GL_WRITE_ONLY,
    outputTexture.internalFormat
  )

  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_BUFFER, outputTexture.textureId)

  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_BUFFER, commandTexture.textureId)

  shader.setUniform("valuesBuf", 0)
  shader.setUniform("commandBuf", 1)

  shader.setUniform(
    "dimens",
    outputImage.width.int32, outputImage.height.int32, 0, 0
  )

  shader.bindUniforms()

  #timeIt "compute sh":
  glDispatchCompute(
    outputImage.width.GLuint, outputImage.height.GLuint, 1
  )

  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  let p = cast[ptr UncheckedArray[uint8]](
    glMapNamedBuffer(outputBuffer.bufferId, GL_READ_ONLY)
  )

  copyMem(outputImage.data[0].addr, p, outputImage.data.len * 4)

  discard glUnmapNamedBuffer(outputBuffer.bufferId)

  outputImage.writeFile("examples/compute_sh.png")

main()
