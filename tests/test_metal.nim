when defined(macosx) and defined(shadyRunMetal):
  import shady, vmath
  import metal4

  proc vertexMain(
    vPos: Vec3,
    vCol: Vec3,
    gl_Position: var Vec4,
    vertColor: var Vec3
  ) =
    gl_Position = vec4(vPos.x, vPos.y, vPos.z, 1.0)
    vertColor = vCol

  proc fragmentMain(fragColor: var Vec4) =
    fragColor = vec4(1.0, 0.0, 0.0, 1.0)

  let device = MTLCreateSystemDefaultDevice()
  checkNil(device, "Could not create a Metal device")

  var error: NSError
  let vertexSource = toMSL(vertexMain, shaderVertex)
  let vertexLibrary = device.newLibraryWithSource(@vertexSource, 0.ID, error.addr)
  checkNSError(error, "Could not compile Shady Metal vertex shader")
  checkNil(vertexLibrary, "Metal vertex library was nil")
  checkNil(
    vertexLibrary.newFunctionWithName(@"vertexMain"),
    "Could not load generated Metal vertexMain"
  )

  error = 0.NSError
  let fragmentSource = toMSL(fragmentMain, shaderFragment)
  let fragmentLibrary =
    device.newLibraryWithSource(@fragmentSource, 0.ID, error.addr)
  checkNSError(error, "Could not compile Shady Metal fragment shader")
  checkNil(fragmentLibrary, "Metal fragment library was nil")
  checkNil(
    fragmentLibrary.newFunctionWithName(@"fragmentMain"),
    "Could not load generated Metal fragmentMain"
  )

  echo "Metal compiler test passed"
elif defined(macosx):
  echo "Metal test skipped; run with -d:shadyRunMetal and metal4 on Nim path"
else:
  echo "Metal test skipped; macOS is required"
