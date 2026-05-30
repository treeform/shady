import strutils

type UniformParam* = tuple[name, typ: string]

const
  vulkanGlsl450Version* = "450"
  vulkanGlsl450Extra* = ""
  vulkanUniformSet* = 1
  vulkanVertexUniformBinding* = 0
  vulkanFragmentUniformBinding* = 1
  vulkanMaxPushConstantBytes* = 128

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
    let defineName = uniform.name.split("[", 1)[0]
    result.add "#define "
    result.add defineName
    result.add " shadyPushConstants."
    result.add defineName
    result.add "\n"

proc emitVulkanUniformBuffer*(
  uniforms: openArray[UniformParam],
  binding: int
): string =
  if uniforms.len == 0:
    return ""
  result.add "layout(set = "
  result.add $vulkanUniformSet
  result.add ", binding = "
  result.add $binding
  result.add ", std140) uniform ShadyUniforms"
  result.add $binding
  result.add " {\n"
  for uniform in uniforms:
    result.add "  "
    result.add uniform.typ
    result.add " "
    result.add uniform.name
    result.add ";\n"
  result.add "} shadyUniforms"
  result.add $binding
  result.add ";\n"
  for uniform in uniforms:
    let defineName = uniform.name.split("[", 1)[0]
    result.add "#define "
    result.add defineName
    result.add " shadyUniforms"
    result.add $binding
    result.add "."
    result.add defineName
    result.add "\n"

proc uniformArrayLength(name: string): int =
  let openBracket = name.find('[')
  if openBracket < 0:
    return 1
  let closeBracket = name.find(']', openBracket + 1)
  if closeBracket < 0:
    return 1
  try:
    parseInt(name[openBracket + 1 ..< closeBracket])
  except ValueError:
    1

proc uniformStd140Size(uniform: UniformParam): int =
  let count = uniformArrayLength(uniform.name)
  let elementSize =
    case uniform.typ
    of "mat4": 64
    of "mat3": 48
    of "mat2": 32
    of "vec4", "ivec4", "uvec4": 16
    of "vec3", "ivec3", "uvec3": 12
    of "vec2", "ivec2", "uvec2": 8
    else: 4
  if count > 1:
    count * (((elementSize + 15) div 16) * 16)
  else:
    elementSize

proc uniformStd140Align(uniform: UniformParam): int =
  if uniformArrayLength(uniform.name) > 1:
    return 16
  case uniform.typ
  of "mat4", "mat3", "mat2", "vec4", "ivec4", "uvec4",
      "vec3", "ivec3", "uvec3":
    16
  of "vec2", "ivec2", "uvec2":
    8
  else:
    4

proc align(value, alignment: int): int =
  ((value + alignment - 1) div alignment) * alignment

proc vulkanUniformBytes*(uniforms: openArray[UniformParam]): int =
  for uniform in uniforms:
    result = align(result, uniformStd140Align(uniform))
    result += uniformStd140Size(uniform)
  result = align(result, 4)

proc useVulkanUniformBuffer*(uniforms: openArray[UniformParam]): bool =
  vulkanUniformBytes(uniforms) > vulkanMaxPushConstantBytes
