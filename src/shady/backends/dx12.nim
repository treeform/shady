import strutils, tables

type
  EntryParam* = tuple[name, typ: string, isOut: bool]
  UniformParam* = tuple[name, typ: string]

const hlslHeader* = "// target hlsl dx12\n"

proc hlslTypeRename*(t: string): string =
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

  of "SamplerBuffer": "Buffer<float>"
  of "Sampler2d": "Texture2D<float4>"
  of "USampler2d": "Texture2D<uint4>"
  of "Sampler2dArray": "Texture2DArray<float4>"
  of "ImageBuffer": "RWBuffer<float4>"
  of "UImageBuffer": "RWBuffer<uint4>"
  else: t

proc hlslProcRename*(t: string): string =
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
  of "mix": "lerp"
  of "fract": "frac"
  of "dFdx": "ddx"
  of "dFdy": "ddy"
  of "fmod": "fmod"
  of "mod": "%"
  of "div": "/"
  of "gl_Position": "gl_Position"
  else: t.replace("`", "_")

proc hlslTypeDefault*(t: string): string =
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

proc semanticBase(name: string): string =
  let lower = name.toLowerAscii()
  if name in ["gl_Position", "position", "pos"] or lower.endsWith("position"):
    "POSITION"
  elif name in ["gl_FragCoord"]:
    "SV_POSITION"
  elif "color" in lower or lower.endsWith("col"):
    "COLOR"
  elif "normal" in lower:
    "NORMAL"
  else:
    "TEXCOORD"

proc hlslSemantic*(name: string, index: int, isOutput: bool): string =
  case name
  of "fragColor", "gl_FragColor":
    " : SV_TARGET"
  of "gl_Position":
    " : SV_POSITION"
  of "gl_FragCoord":
    " : SV_POSITION"
  of "gl_VertexID":
    " : SV_VertexID"
  else:
    let base = semanticBase(name)
    if base.startsWith("SV_"):
      " : " & base
    else:
      " : " & base & $index

proc nextSemanticIndex(
  name: string,
  counts: var Table[string, int]
): int =
  case name
  of "fragColor", "gl_FragColor", "gl_Position", "gl_FragCoord", "gl_VertexID":
    return 0
  else:
    let base = semanticBase(name)
    if base.startsWith("SV_"):
      return 0
    result = counts.getOrDefault(base, 0)
    counts[base] = result + 1

proc hlslOutputFieldName*(name: string): string =
  if name == "gl_Position": "pos" else: name

proc hlslTextureDecl*(name, typ: string, register: int): string =
  typ & " " & name & " : register(t" & $register & ");"

proc hlslSamplerDecl*(name: string, register: int): string =
  "SamplerState " & name & "Sampler : register(s" & $register & ");"

proc emitHlslUniformBuffer*(
  uniforms: openArray[UniformParam],
  register = 0
): string =
  if uniforms.len == 0:
    return ""
  result.add "cbuffer ShadyUniforms : register(b"
  result.add $register
  result.add ") {\n"
  for uniform in uniforms:
    result.add "  "
    result.add uniform.typ
    result.add " "
    result.add uniform.name
    result.add ";\n"
  result.add "};\n"

proc hlslResourceCall*(
  name: string,
  args: openArray[string],
  firstArgIsSamplerBuffer: bool
): string =
  case name
  of "texture":
    if args.len != 2: return ""
    args[0] & ".Sample(" & args[0] & "Sampler, " & args[1] & ")"
  of "texelFetch":
    if args.len < 2: return ""
    if firstArgIsSamplerBuffer:
      args[0] & ".Load(" & args[1] & ")"
    else:
      let level = if args.len >= 3: args[2] else: "0"
      args[0] & ".Load(int3(" & args[1] & ", " & level & "))"
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
      result.add hlslTypeDefault(p.typ)
      result.add ";\n"

proc emitHlslEntry*(
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

    result.add "\nstruct VSOutput {\n"
    var outputSemanticCounts: Table[string, int]
    for p in outputs:
      result.add "  "
      result.add p.typ
      result.add " "
      result.add hlslOutputFieldName(p.name)
      result.add hlslSemantic(
        p.name,
        nextSemanticIndex(p.name, outputSemanticCounts),
        true
      )
      result.add ";\n"
    result.add "};\n\n"

    result.add "VSOutput VSMain("
    var inputSemanticCounts: Table[string, int]
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
        result.add hlslSemantic(
          p.name,
          nextSemanticIndex(p.name, inputSemanticCounts),
          false
        )
    if not params.hasParam("gl_VertexID") and "gl_VertexID" in bodyCode:
      if first:
        result.add "\n"
        first = false
      else:
        result.add ",\n"
      result.add "  uint gl_VertexID : SV_VertexID"
    if not first:
      result.add "\n"
    result.add ") {\n"
    result.add "  VSOutput output;\n"
    result.add outputLocals(params, 1)
    result.add bodyCode
    for p in outputs:
      result.add "  output."
      result.add hlslOutputFieldName(p.name)
      result.add " = "
      result.add p.name
      result.add ";\n"
    result.add "  return output;\n"
    result.add "}\n"

  of 2:
    let outputIndex = firstOutput(params)
    let returnType = if outputIndex >= 0: params[outputIndex].typ else: "void"
    result.add "\n"
    result.add returnType
    result.add " PSMain("
    var inputSemanticCounts: Table[string, int]
    var first = true
    if not params.hasParam("gl_FragCoord"):
      result.add "\n  float4 gl_FragCoord : SV_POSITION"
      first = false
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
        result.add hlslSemantic(
          p.name,
          nextSemanticIndex(p.name, inputSemanticCounts),
          false
        )
    if not first:
      result.add "\n"
    result.add ")"
    if outputIndex >= 0:
      result.add hlslSemantic(params[outputIndex].name, 0, true)
    result.add " {\n"
    result.add outputLocals(params, 1)
    result.add bodyCode
    if outputIndex >= 0:
      result.add "  return "
      result.add params[outputIndex].name
      result.add ";\n"
    result.add "}\n"

  of 3:
    result.add "\n[numthreads(1, 1, 1)]\n"
    result.add "void CSMain(uint3 gl_GlobalInvocationID : SV_DispatchThreadID) {\n"
    result.add bodyCode
    result.add "}\n"

  else:
    discard
