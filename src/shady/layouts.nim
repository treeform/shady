import std/[strutils, tables]
import ./errors

type
  UniformField* = object
    name*, kind*: string
    offset*, size*, count*: int
  UniformLayout* = object
    fields*: seq[UniformField]
    offsets*: Table[string, int]
    size*: int

proc aligned(value, alignment: int): int =
  ## Rounds a byte offset to the required native alignment.
  (value + alignment - 1) div alignment * alignment

proc metalUniformLayout*(source: string): UniformLayout =
  ## Describes the native MSL layout emitted for a Shady uniform buffer.
  var
    active = false
    maxAlignment = 1
  for line in source.splitLines():
    if line.startsWith("struct ShadyUniforms"):
      active = true
      continue
    if not active:
      continue
    if line.startsWith("};"):
      break
    let words = line.strip().strip(chars = {';'}).splitWhitespace()
    if words.len != 2:
      raise newException(ShadyError, "Invalid generated uniform field")
    var field = UniformField(name: words[1], kind: words[0], count: 1)
    let bracket = field.name.find('[')
    if bracket >= 0:
      try:
        field.count = parseInt(field.name[bracket + 1 ..< field.name.find(']')])
      except ValueError as error:
        raise newException(ShadyError, error.msg)
      field.name.setLen(bracket)
    var alignment = 4
    field.size = 4
    case field.kind
    of "bool":
      alignment = 1
      field.size = 1
    of "float", "int", "uint":
      discard
    of "float2", "int2", "uint2":
      alignment = 8
      field.size = 8
    of "float3", "float4", "int3", "int4", "uint3", "uint4":
      alignment = 16
      field.size = 16
    of "float3x3":
      alignment = 16
      field.size = 48
    of "float4x4":
      alignment = 16
      field.size = 64
    else:
      raise newException(ShadyError, "Unsupported uniform: " & field.kind)
    field.offset = aligned(result.size, alignment)
    result.size = field.offset + field.size * field.count
    maxAlignment = max(maxAlignment, alignment)
    result.offsets[field.name] = field.offset
    result.fields.add(field)
  result.size = aligned(result.size, maxAlignment)
