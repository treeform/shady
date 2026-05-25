import strutils

type EntryParam* = tuple[name, typ: string, isOut: bool]

const metalHeader* = "#include <metal_stdlib>\nusing namespace metal;\n"

proc metalTypeRename*(t: string): string =
  case t
  of "Mat2": "float2x2"
  of "Mat3": "float3x3"
  of "Mat4": "float4x4"

  of "Vec2": "float2"
  of "Vec3": "float3"
  of "Vec4": "float4"

  of "IVec2": "int2"
  of "IVec3": "int3"
  of "IVec4": "int4"

  of "UVec2": "uint2"
  of "UVec3": "uint3"
  of "UVec4": "uint4"

  of "DVec2": "double2"
  of "DVec3": "double3"
  of "DVec4": "double4"

  of "int32": "int"
  of "uint32": "uint"

  of "float32": "float"
  of "float64": "double"
  of "ColorRGBX": "float4"

  of "SamplerBuffer": "texture_buffer<float>"
  of "Sampler2d": "texture2d<float>"
  of "USampler2d": "texture2d<uint>"
  of "Sampler2dArray": "texture2d_array<float>"
  of "ImageBuffer": "device float4*"
  of "UImageBuffer": "device uint4*"
  else: t

proc metalProcRename*(t: string): string =
  case t
  of "not": "!"
  of "and": "&&"
  of "or": "||"
  of "vec2": "float2"
  of "vec3": "float3"
  of "vec4": "float4"
  of "mat2": "float2x2"
  of "mat3": "float3x3"
  of "mat4": "float4x4"
  of "uvec2": "uint2"
  of "uvec3": "uint3"
  of "uvec4": "uint4"
  of "ivec2": "int2"
  of "ivec3": "int3"
  of "ivec4": "int4"
  of "dFdx": "dfdx"
  of "dFdy": "dfdy"
  of "fmod": "fmod"
  of "mod": "%"
  of "div": "/"
  else: t.replace("`", "_")

proc metalTypeDefault*(t: string): string =
  case t
  of "float2x2": "float2x2(0.0)"
  of "float3x3": "float3x3(0.0)"
  of "float4x4": "float4x4(0.0)"
  of "float4": "float4(0.0, 0.0, 0.0, 0.0)"
  of "float3": "float3(0.0, 0.0, 0.0)"
  of "float2": "float2(0.0, 0.0)"

  of "uint2": "uint2(0, 0)"
  of "uint3": "uint3(0, 0, 0)"
  of "uint4": "uint4(0, 0, 0, 0)"
  of "int2": "int2(0, 0)"
  of "int3": "int3(0, 0, 0)"
  of "int4": "int4(0, 0, 0, 0)"

  of "float": "0.0"
  of "double": "0.0"
  of "int": "0"
  of "uint": "0"
  else: ""

proc metalAttribute*(name: string, index: int, isOutput: bool): string =
  case name
  of "fragColor", "gl_FragColor":
    " [[color(0)]]"
  of "gl_Position":
    " [[position]]"
  of "gl_VertexID":
    " [[vertex_id]]"
  else:
    if isOutput:
      ""
    else:
      " [[attribute(" & $index & ")]]"

proc metalOutputFieldName*(name: string): string =
  if name == "gl_Position": "position" else: name

proc metalResourceCall*(
  name: string,
  args: openArray[string],
  firstArgIsSamplerBuffer: bool
): string =
  case name
  of "texture":
    if args.len != 2: return ""
    args[0] & ".sample(" & args[0] & "Sampler, " & args[1] & ")"
  of "texelFetch":
    if args.len < 2: return ""
    if firstArgIsSamplerBuffer:
      "float4(" & args[0] & ".read(uint(" & args[1] & ")), 0.0, 0.0, 0.0)"
    else:
      let level = if args.len >= 3: args[2] else: "0"
      args[0] & ".read(uint2(" & args[1] & "), uint(" & level & "))"
  of "imageLoad":
    if args.len != 2: return ""
    args[0] & "[" & args[1] & "]"
  of "imageStore":
    if args.len != 3: return ""
    args[0] & "[" & args[1] & "] = " & args[2]
  else:
    ""

proc firstOutput(params: openArray[EntryParam]): int =
  result = -1
  for i, p in params:
    if p.isOut:
      return i

proc hasParam(params: openArray[EntryParam], name: string): bool =
  for p in params:
    if p.name == name:
      return true

proc outputLocals(params: openArray[EntryParam], level: int): string =
  let indent = repeat("  ", level)
  for p in params:
    if p.isOut:
      result.add indent
      result.add p.typ
      result.add " "
      result.add p.name
      result.add " = "
      result.add metalTypeDefault(p.typ)
      result.add ";\n"

proc emitMetalEntry*(
  params: openArray[EntryParam],
  bodyCode: string,
  stage: int
): string =
  case stage
  of 1:
    var outputs: seq[EntryParam]
    for p in params:
      if p.isOut:
        outputs.add p

    result.add "\nstruct VertexOut {\n"
    for p in outputs:
      result.add "  "
      result.add p.typ
      result.add " "
      result.add metalOutputFieldName(p.name)
      result.add metalAttribute(p.name, 0, true)
      result.add ";\n"
    result.add "};\n\n"

    result.add "vertex VertexOut vertexMain("
    var inputIndex = 0
    var first = true
    for p in params:
      if not p.isOut:
        if first:
          result.add "\n"
          first = false
        else:
          result.add ",\n"
        result.add "  "
        result.add p.typ
        result.add " "
        result.add p.name
        result.add metalAttribute(p.name, inputIndex, false)
        inc inputIndex
    if not params.hasParam("gl_VertexID") and "gl_VertexID" in bodyCode:
      if first:
        result.add "\n"
        first = false
      else:
        result.add ",\n"
      result.add "  uint gl_VertexID [[vertex_id]]"
    if not first:
      result.add "\n"
    result.add ") {\n"
    result.add "  VertexOut output;\n"
    result.add outputLocals(params, 1)
    result.add bodyCode
    for p in outputs:
      result.add "  output."
      result.add metalOutputFieldName(p.name)
      result.add " = "
      result.add p.name
      result.add ";\n"
    result.add "  return output;\n"
    result.add "}\n"

  of 2:
    let outputIndex = firstOutput(params)
    let returnType = if outputIndex >= 0: params[outputIndex].typ else: "void"
    result.add "\nfragment "
    result.add returnType
    result.add " fragmentMain("
    var inputIndex = 0
    var first = true
    for p in params:
      if not p.isOut:
        if first:
          result.add "\n"
          first = false
        else:
          result.add ",\n"
        result.add "  "
        result.add p.typ
        result.add " "
        result.add p.name
        result.add metalAttribute(p.name, inputIndex, false)
        inc inputIndex
    if not first:
      result.add "\n"
    result.add ") {\n"
    result.add outputLocals(params, 1)
    result.add bodyCode
    if outputIndex >= 0:
      result.add "  return "
      result.add params[outputIndex].name
      result.add ";\n"
    result.add "}\n"

  of 3:
    result.add "\nkernel void computeMain(uint3 gl_GlobalInvocationID [[thread_position_in_grid]]) {\n"
    result.add bodyCode
    result.add "}\n"

  else:
    discard
