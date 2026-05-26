type UniformParam* = tuple[name, typ: string]

const
  vulkanGlsl450Version* = "450"
  vulkanGlsl450Extra* = ""

proc vulkanSamplerDecl*(name, typ: string, binding: int): string =
  "layout(set = 0, binding = " & $binding & ") uniform " & typ & " " &
    name & ";"

proc emitVulkanPushConstants*(
  uniforms: openArray[UniformParam]
): string =
  if uniforms.len == 0:
    return ""
  result.add "layout(push_constant) uniform ShadyPushConstants {\n"
  for uniform in uniforms:
    result.add "  "
    result.add uniform.typ
    result.add " "
    result.add uniform.name
    result.add ";\n"
  result.add "} shadyPushConstants;\n"
  for uniform in uniforms:
    result.add "#define "
    result.add uniform.name
    result.add " shadyPushConstants."
    result.add uniform.name
    result.add "\n"
