## Shader macro, converts Nim code into shader source.

import macros, pixie, strutils, tables, vmath
import shady/backends/[glsl, glsl3, glsl4, dx12, metal4, vulkan]
from chroma import ColorRGBX

type
  ShaderTarget* = enum
    glsl3WebGL    ## OpenGL ES 3.0 / WebGL 2.0 compatibility profile.
    glsl3Desktop  ## Desktop GLSL 3.30 / OpenGL 3.3 compatibility profile.
    glsl4Desktop  ## Explicit desktop GLSL for OpenGL 4.1+.
    vulkanGlsl450 ## GLSL 4.50 source shaped for Vulkan/SPIR-V.
    hlslDX12      ## HLSL for DirectX 12.
    metalMSL      ## Metal Shading Language.

  GlslTarget* = ShaderTarget

  ShaderStage* = enum
    shaderAuto
    shaderVertex
    shaderFragment
    shaderCompute

  ShaderLanguage = enum
    langGlsl
    langHlsl
    langMetal

const
  glslDesktop* = glsl4Desktop
  glslES3* = glsl3WebGL

var useResult {.compiletime.}: bool
var shaderTarget* {.compiletime.}: ShaderTarget
var shaderStage* {.compiletime.}: ShaderStage

const shaderSamplerTypes = [
  "Sampler2d", "SamplerCube", "Sampler2dShadow", "USampler2d",
  "Sampler2dArray"
]

template glslTarget*(): untyped =
  shaderTarget

proc err(msg: string, n: NimNode) {.noreturn.} =
  error("[Shady] " & msg, n)

proc language(target: ShaderTarget): ShaderLanguage =
  case target
  of glsl3WebGL, glsl3Desktop, glsl4Desktop, vulkanGlsl450:
    langGlsl
  of hlslDX12:
    langHlsl
  of metalMSL:
    langMetal

proc isGlsl(): bool =
  shaderTarget.language == langGlsl

proc isVulkan(): bool =
  shaderTarget == vulkanGlsl450

proc isHlsl(): bool =
  shaderTarget.language == langHlsl

proc isMetal(): bool =
  shaderTarget.language == langMetal

proc typeRename(t: string): string =
  ## Some shader type names don't match Nim names, rename here.
  case shaderTarget.language
  of langGlsl:
    glslTypeRename(t)
  of langHlsl:
    hlslTypeRename(t)
  of langMetal:
    metalTypeRename(t)

proc typeString(n: NimNode): string =
  if n.kind != nnkBracketExpr:
    typeRename(n.strVal)
  else:
    case n.repr:
    of "GMat2[float32]": typeRename("Mat2")
    of "GMat3[float32]": typeRename("Mat3")
    of "GMat4[float32]": typeRename("Mat4")
    of "GVec2[float32]": typeRename("Vec2")
    of "GVec3[float32]": typeRename("Vec3")
    of "GVec4[float32]": typeRename("Vec4")
    of "GMat2[float64]": (if isGlsl(): "dmat2" else: "double2x2")
    of "GMat3[float64]": (if isGlsl(): "dmat3" else: "double3x3")
    of "GMat4[float64]": (if isGlsl(): "dmat4" else: "double4x4")
    of "GVec2[float64]": typeRename("DVec2")
    of "GVec3[float64]": typeRename("DVec3")
    of "GVec4[float64]": typeRename("DVec4")
    of "GVec2[uint32]": typeRename("UVec2")
    of "GVec3[uint32]": typeRename("UVec3")
    of "GVec4[uint32]": typeRename("UVec4")
    of "GVec2[int32]": typeRename("IVec2")
    of "GVec3[int32]": typeRename("IVec3")
    of "GVec4[int32]": typeRename("IVec4")
    of "Uniform[float32]": typeRename("float32")
    of "Uniform[int]": typeRename("int")
    else:
      if n[0].repr == "array":
        var length = 0
        if n[1].kind == nnkIntLit:
          length = n[1].intVal.int
        elif n[1].kind == nnkBracketExpr and n[1].len == 3 and n[1][0].repr == "..":
           # array[0..1, T] case
           length = n[1][2].intVal.int - n[1][1].intVal.int + 1
        elif n[1].kind == nnkInfix and n[1].len == 3 and n[1][0].repr == "..":
           # array[0..1, T] case
           length = n[1][2].intVal.int - n[1][1].intVal.int + 1

        if length == 2:
          if n[2].repr == "uint16": return typeRename("Vec2")
          if n[2].repr in ["uint32"]: return typeRename("UVec2")
          if n[2].repr in ["int16", "int32"]: return typeRename("IVec2")
          if n[2].repr in ["float32", "float64"]: return typeRename("Vec2")
        elif length == 3:
          if n[2].repr == "uint16": return typeRename("Vec3")
          if n[2].repr in ["uint32"]: return typeRename("UVec3")
          if n[2].repr in ["int16", "int32"]: return typeRename("IVec3")
          if n[2].repr in ["float32", "float64"]: return typeRename("Vec3")
        elif length == 4:
          if n[2].repr == "uint16": return typeRename("Vec4")
          if n[2].repr in ["uint32"]: return typeRename("UVec4")
          if n[2].repr in ["int16", "int32"]: return typeRename("IVec4")
          if n[2].repr in ["float32", "float64"]: return typeRename("Vec4")

      err "can't figure out type: " & n.repr, n

proc arrayLength(n: NimNode): int =
  if n.kind != nnkBracketExpr or n[0].repr != "array":
    return 0
  if n[1].kind == nnkIntLit:
    return n[1].intVal.int
  if n[1].kind == nnkBracketExpr and n[1].len == 3 and n[1][0].repr == "..":
    return n[1][2].intVal.int - n[1][1].intVal.int + 1
  if n[1].kind == nnkInfix and n[1].len == 3 and n[1][0].repr == "..":
    return n[1][2].intVal.int - n[1][1].intVal.int + 1
  err "can't figure out array length: " & n.repr, n

proc splitArrayType(n: NimNode): tuple[baseType, suffix: string] =
  if n.kind == nnkBracketExpr and n[0].repr == "array":
    let length = n.arrayLength()
    result.baseType = typeString(n[2])
    result.suffix = "[" & $length & "]"
  else:
    result.baseType = typeString(n)
    result.suffix = ""

## Default constructor for different shader types.
proc typeDefault(t: string, n: NimNode): string =
  result =
    case shaderTarget.language
    of langGlsl:
      glslTypeDefault(t)
    of langHlsl:
      hlslTypeDefault(t)
    of langMetal:
      metalTypeDefault(t)
  if result.len == 0:
    err "no typeDefault " & t, n

## Simply SKIP these functions.
const ignoreFunctions = [
  "echo", "print", "debugEcho", "$"
]

proc isVectorAccess(s: string): bool =
  ## is it a x,y,z or swizzle rgba=
  for flavor in ["xyzw", "rgba", "stpq"]:
    if s[0] in flavor:
      for i, c in s:
        if c notin flavor:
          if c == '=' and i == s.len - 1:
            return true
          else:
            return false
      return true
  return  false

proc procRename(t: string): string =
  ## Some shader proc names don't match Nim names, rename here.
  case shaderTarget.language
  of langGlsl:
    glslProcRename(t)
  of langHlsl:
    hlslProcRename(t)
  of langMetal:
    metalProcRename(t)

proc opPrecedence(op: string): int =
  ## Given an operator return its precedence.
  ## Used to decide if () are needed.
  ## See: https://learnwebgl.brown37.net/12_shader_language/glsl_mathematical_operations.html
  case op:
  of "*", "/": 4
  of "+", "-": 5
  of "<", ">", "<=", ">=": 7
  of "==", "!=": 8
  of "&&": 12
  of "^^": 13
  of "||": 14
  of "=", "+=", "-=", "*=", "/=": 16
  else: -1

proc getPrecedence(n: NimNode): int =
  ## Return the opPrecedence of the node operator or -1.
  if n.kind == nnkInfix:
    n[0].strVal.opPrecedence()
  else:
    -1

proc addIndent(res: var string, level: int) =
  ## Add indent (only if its needed).
  if res.len == 0:
    for i in 0 ..< level:
      res.add "  "
    return
  var
    idx = res.len - 1
    spaces = 0
  while idx >= 0 and res[idx] == ' ':
    dec idx
    inc spaces
  if idx < 0:
    let level = max(0, level - spaces div 2)
    for i in 0 ..< level:
      res.add "  "
    return
  if spaces == 0 and res[idx] != '\n':
    res.add '\n'
  let level = level - spaces div 2
  for i in 0 ..< level:
    res.add "  "

proc addGap(res: var string) =
  if res.len > 0:
    if not res.endsWith("\n\n"):
      if res.endsWith("\n"):
        res.add "\n"
      else:
        res.add "\n\n"

proc addSmart(res: var string, c: char, others = {'}'}) =
  ## Ads a char but first checks if its already here.
  var idx = res.len - 1
  while res[idx] in Whitespace:
    dec idx
  if res[idx] != c and res[idx] notin others:
    res.add c

proc toCode(n: NimNode, res: var string, level = 0)
proc toCodeStmts(n: NimNode, res: var string, level = 0)

proc isIntegerType(t: string): bool =
  t in ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64"]

proc typeInstRepr(n: NimNode): string =
  try:
    n.getTypeInst().repr
  except:
    ""

proc isSamplerBufferExpr(n: NimNode): bool =
  "SamplerBuffer" in n.typeInstRepr()

proc isShadowSamplerExpr(n: NimNode): bool =
  "Sampler2dShadow" in n.typeInstRepr()

proc codeExpr(n: NimNode): string =
  n.toCode(result)

proc emitBackendCall(n: NimNode, res: var string): bool =
  ## Builtin resource operations are where the shader languages differ most.
  if isGlsl() or n.kind notin {nnkCall, nnkCommand}:
    return false

  let name = n[0].strVal
  if name notin [
    "texture", "textureLod", "textureSize", "texelFetch", "imageLoad",
    "imageStore"
  ]:
    return false
  var args: seq[string]
  for i in 1 ..< n.len:
    args.add n[i].codeExpr()

  let call =
    if isHlsl():
      hlslResourceCall(
        name,
        args,
        n.len > 1 and n[1].isSamplerBufferExpr,
        n.len > 1 and n[1].isShadowSamplerExpr
      )
    else:
      metalResourceCall(
        name,
        args,
        n.len > 1 and n[1].isSamplerBufferExpr,
        n.len > 1 and n[1].isShadowSamplerExpr
      )
  if call.len == 0:
    return false
  res.add call
  return true

proc toCode(n: NimNode, res: var string, level = 0) =
  ## Inner code block.

  case n.kind

  of nnkAsgn:
    res.addIndent level
    n[0].toCode(res)
    res.add " = "
    n[1].toCode(res)
    res.addSmart ';'

  of nnkInfix:
    if n[0].repr in ["mod"] and not isIntegerType(n[1].getType().repr):
      # In Nim float mod and integer made are same thing.
      # In GLSL mod(float, float) is a function while % is for integers.
      if isGlsl():
        res.add "mod"
      else:
        res.add "fmod"
      res.add "("
      n[1].toCode(res)
      res.add ", "
      n[2].toCode(res)
      res.add ")"

    elif n[0].repr in ["+=", "-=", "*=", "/="]:
      res.addIndent level
      n[1].toCode(res)
      res.add " "
      n[0].toCode(res)
      res.add " "
      n[2].toCode(res)
      res.addSmart ';'

    else:
      let
        a = n.getPrecedence()
        l = n[1].getPrecedence()
        r = n[2].getPrecedence()
      if l >= a:
        res.add "("
        n[1].toCode(res)
        res.add ")"
      else:
        n[1].toCode(res)
      res.add " "
      n[0].toCode(res)
      res.add " "
      if r >= a:
        res.add "("
        n[2].toCode(res)
        res.add ")"
      else:
        n[2].toCode(res)

  of nnkHiddenDeref, nnkHiddenAddr:
    n[0].toCode(res)

  of nnkCall, nnkCommand:
    if n[0].strVal == "discardFragment":
      # Special case for discarding the fragment.
      # Because both Nim discard and GLSL discard are keywords that do different things.
      if isMetal():
        res.add "discard_fragment()"
      else:
        res.add "discard"
      return
    if n[0].strVal == "inc":
      n[1].toCode(res)
      if n.len == 3:
        res.add " += "
        n[2].toCode(res)
      else:
        res.add "++"
      return
    if n[0].strVal == "dec":
      n[1].toCode(res)
      if n.len == 3:
        res.add " -= "
        n[2].toCode(res)
      else:
        res.add "--"
      return
    if n.emitBackendCall(res):
      return
    var procName = procRename(n[0].strVal)
    if procName in ignoreFunctions:
      return
    if procName == "[]=":
      n[1].toCode(res)
      for i in 2 ..< n.len - 1:
        res.add "["
        n[i].toCode(res)
        res.add "]"
      res.add " = "
      n[n.len - 1].toCode(res)
      res.addSmart ';'

    elif procName == "[]":
      n[1].toCode(res)
      for i in 2 ..< n.len:
        res.add "["
        n[i].toCode(res)
        res.add "]"

    elif isVectorAccess(procName):
      if n[1].kind == nnkSym:
        n[1].toCode(res)
      else:
        res.add "("
        n[1].toCode(res)
        res.add ")"
      res.add "."
      res.add procName.replace("=", " = ")
      if n.len == 3:
        n[2].toCode(res)
    else:
      res.add procName
      res.add "("
      for j in 1 ..< n.len:
        if j != 1: res.add ", "
        n[j].toCode(res)
      res.add ")"

  of nnkDotExpr:
    n[0].toCode(res)
    res.add "."
    n[1].toCode(res)

  of nnkBracketExpr:
    if n[0].len == 2 and n[0][1].repr == "arr":
      # Fastest vmath translates `obj.x` to `obj.arr[x]` for speed.
      # Translate expanded the `obj.arr[x]` back to `.x` for shader.
      let field = case n[1].repr:
        of "0": ".x"
        of "1": ".y"
        of "2": ".z"
        of "3": ".w"
        else: "[" & n[1].repr & "]"
      n[0][0].toCode(res)
      res.add field
    else:
      n[0].toCode(res)
      res.add "["
      n[1].toCode(res)
      res.add "]"

  of nnkIdent, nnkSym:
    res.add procRename(n.strVal)

  of nnkStmtListExpr:
    for j in 0 ..< n.len:
      n[j].toCode(res, level)

  of nnkStmtList:
    for j in 0 ..< n.len:
      if n[j].kind in [nnkCall, nnkCommand]:
        res.addIndent level
      n[j].toCode(res, level)
      if n[j].kind notin [nnkLetSection, nnkVarSection, nnkCommentStmt]:
        res.addSmart ';'
        res.add "\n"

  of nnkIfStmt:
    res.addIndent level
    res.add "if ("
    n[0][0].toCode(res)
    res.add ") {\n"
    n[0][1].toCodeStmts(res, level + 1)
    res.addIndent level
    res.add "}"
    var i = 1
    while n.len > i:
      if n[i].kind == nnkElse:
        res.add " else {\n"
        n[i][0].toCodeStmts(res, level + 1)
        res.addIndent level
        res.add "}"
      elif n[i].kind == nnkElifBranch:
        res.add " else if ("
        n[i][0].toCode(res)
        res.add ") {\n"
        n[i][1].toCodeStmts(res, level + 1)
        res.addIndent level
        res.add "}"
      else:
        err "Not supported if branch", n
      inc i

  # of nnkIfExpr:
  #   res.add "("
  #   n[0][0].toCode(res)
  #   res.add ") ? ("
  #   n[1][0].toCode(res)
  #   res.add ") : ("
  #   n[2][0].toCode(res)
  #   res.add ")"

  of nnkConv:
    res.add typeRename(n[0].strVal)
    res.add "("
    n[1].toCode(res)
    res.add ")"

  of nnkHiddenStdConv:
    var typeStr = typeRename(n.getType.repr)
    if typeStr.startsWith("range["):
      n[1].toCode(res)
    elif typeStr == "float" and n[1].kind == nnkIntLit:
      res.add $n[1].intVal.float64
    elif typeStr == "float" and n[1].kind == nnkFloatLit:
      res.add $n[1].floatVal.float64
    elif typeStr in ["int", "uint"] and n[1].kind in {nnkIntLit .. nnkInt64Lit}:
      n[1].toCode(res)
    else:
      for j in 1 .. n.len-1:
        res.add typeStr
        res.add "("
        n[j].toCode(res)
        res.add ")"

  of nnkNone:
    assert false

  of nnkEmpty, nnkNilLit, nnkDiscardStmt, nnkPragma:
    # Skip all nil, empty and discard statements.
    discard

  of nnkIntLit .. nnkInt64Lit:
    var iv = $n.intVal
    res.add iv

  of nnkFloatLit .. nnkFloat64Lit:
    var fv = $n.floatVal
    res.add fv

  of nnkStrLit .. nnkTripleStrLit:
    res.add $n.strVal.newLit.repr

  of nnkCommentStmt:
    # preserve comments
    for line in n.strVal.split("\n"):
      res.addIndent level
      res.add "// "
      res.add line
      res.add "\n"

  of nnkVarSection, nnkLetSection:
    ## var and let ares the same in GLSL
    for j in 0 ..< n.len:
      res.addIndent level
      n[j].toCode(res, level)
      res.addSmart ';'
      res.add "\n"

  of nnkIdentDefs:
    for j in countup(0, n.len - 1, 3):
      var typeStr = ""
      if n[1].kind == nnkBracketExpr and
        n[1][0].kind == nnkSym and
        n[1][0].strVal == "array":
        typeStr = typeRename(n[1][2].strVal)
        typeStr.add "["
        typeStr.add n[1][1].repr
        typeStr.add "]"

        res.add typeStr
        res.add " "
        n[0].toCode(res)
      else:
        typeStr = typeString(n[j].getTypeInst())
        res.add typeStr
        res.add " "
        n[j].toCode(res)
        if n[j + 2].kind != nnkEmpty:
          res.add " = "
          n[j + 2].toCode(res)
        else:
          res.add " = "
          res.add typeDefault(typeStr, n[j])

  of nnkReturnStmt:
    res.addIndent level
    if n[0].kind == nnkAsgn:
      n[0].toCode(res)
      res.add "\n"
      res.addIndent level
      res.add "return result"
    elif n[0].kind != nnkEmpty:
      res.add "return "
      n[0][1].toCode(res)
    elif useResult:
      res.add "return result"
    else:
      res.add "return"

  of nnkPrefix:
    res.add procRename(n[0].strVal) & " ("
    n[1].toCode(res)
    res.add ")"

  of nnkWhileStmt:
    res.addIndent level
    res.add "while("
    n[0].toCode(res)
    res.add ") {\n"
    n[1].toCode(res, level + 1)
    res.addIndent level
    res.add "}"

  of nnkForStmt:
    res.addIndent level
    res.add "for("
    res.add "int "
    res.add n[0].strVal
    res.add " = "
    n[1][1].toCode(res)
    res.add "; "
    res.add n[0].strVal
    if n[1][0].strVal == "..<":
      res.add " < "
    elif n[1][0].strVal == "..":
      res.add " <= "
    else:
      err "For loop only supports integer .. or ..<.", n
    n[1][2].toCode(res)
    res.add "; "
    res.add n[0].strVal
    res.add "++"
    res.add ") {\n"
    if n[2].kind == nnkStmtList:
      n[2].toCode(res, level + 1)
    else:
      res.addIndent level
      n[2].toCode(res, level + 1)
      res.add ";"
    res.addIndent level
    res.add "}"

  of nnkBreakStmt:
    res.addIndent level
    res.add "break"

  of nnkProcDef:
    err "Nested proc definitions are not allowed.", n

  of nnkCaseStmt:
    res.addIndent level
    res.add "switch("
    n[0].toCode(res)
    res.add ") {\n"
    for branch in n[1 .. ^1]:
      if branch.kind == nnkOfBranch:
        res.addIndent level
        res.add "case "
        branch[0].toCode(res)
        res.add ":{\n"
        branch[1].toCodeStmts(res, level + 1)
        res.addIndent level
        if branch[1].kind == nnkReturnStmt or branch[1].kind == nnkBreakStmt:
          res.add "};\n"
        else:
          res.add "}; break;\n"
      elif branch.kind == nnkElse:
        res.addIndent level
        res.add "default: {\n"
        branch[0].toCodeStmts(res, level + 1)
        res.addIndent level
        if branch[0].kind == nnkReturnStmt or branch[0].kind == nnkBreakStmt:
          res.add "};\n"
        else:
          res.add "}; break;\n"
      else:
        err "Can't compile branch", n
    res.addIndent level
    res.add "}"

  of nnkChckRange:
    # skip check range and treat it as a hidden cast instead
    var typeStr = typeRename(n.getType.repr)
    res.add typeStr
    res.add "("
    n[0].toCode(res)
    res.add ")"

  of nnkObjConstr:
    if repr(n[0][0]) == "[]":
      # probably a swizzle call.
      res.add n[1][1][1][1][0][0].strval
      res.add "."
      for part in n[1][1]:
        res.add "xyzw"[part[1][1][1].intVal]
    else:
      echo n.treeRepr
      err "Some sort of object constructor", n

  of nnkIfExpr:
    var gotElse = false
    res.add "("
    for subn in n:
      case subn.kind
      of nnkElifExpr, nnkElifBranch:
        if gotElse:
          echo n.treeRepr
          err "Cannot have elif after else", n
        res.add "("
        subn[0].toCode(res)
        res.add ") ? ("
        subn[1].toCode(res)
        res.add ") : "
      of nnkElseExpr, nnkElse:
        gotElse = true
        res.add "("
        subn[0].toCode(res)
        res.add ")"
      else:
        echo n.treeRepr
        err "Invalid child of nnkIfExpr: " & subn.kind.repr, n
    res.add ")"
    if not gotElse:
      echo n.treeRepr
      err "nnkIfExpr is missing an else clause", n

  else:
    echo n.treeRepr
    err "Can't compile", n

proc toCodeStmts(n: NimNode, res: var string, level = 0) =
  if n.kind != nnkStmtList:
    res.addIndent level
    n.toCode(res, level)
    res.addSmart ';'
    res.add "\n"
  else:
    n.toCode(res, level)

type EntryParam = tuple[name, typ: string, isOut: bool]

proc typeFromNode(typeNode: NimNode): string =
  if typeNode.kind == nnkBracketExpr:
    typeString(typeNode)
  else:
    typeRename(typeNode.strVal)

proc innerTypeFromVar(typeNode: NimNode): string =
  if typeNode[0].kind == nnkBracketExpr:
    typeString(typeNode[0])
  else:
    typeRename(typeNode[0].strVal)

proc gatherEntryParams(formalParams: NimNode): seq[EntryParam] =
  for paramDefs in formalParams:
    if paramDefs.kind == nnkIdentDefs:
      let typeNode = paramDefs[^2]
      for i in 0 ..< paramDefs.len - 2:
        let param = paramDefs[i]
        if typeNode.kind == nnkVarTy:
          result.add (
            name: param.strVal,
            typ: innerTypeFromVar(typeNode),
            isOut: true
          )
        else:
          result.add (
            name: param.strVal,
            typ: typeFromNode(typeNode),
            isOut: false
          )

proc resolvedStage(params: seq[EntryParam]): ShaderStage =
  if shaderStage != shaderAuto:
    return shaderStage
  for p in params:
    if p.name == "gl_Position":
      return shaderVertex
  shaderFragment

proc stageId(stage: ShaderStage): int =
  case stage
  of shaderVertex: 1
  of shaderFragment: 2
  of shaderCompute: 3
  of shaderAuto: 0

proc emitBackendEntry(params: seq[EntryParam], body: NimNode, res: var string) =
  var bodyCode = ""
  body.toCodeStmts(bodyCode, 1)
  let stage = resolvedStage(params).stageId()
  if isHlsl():
    res.add dx12.emitHlslEntry(params, bodyCode, stage)
  else:
    res.add metal4.emitMetalEntry(params, bodyCode, stage)

proc toCodeTopLevel(topLevelNode: NimNode, res: var string, level = 0) =
  ## Top level block such as in and out params.
  ## Generates the main function (which is not like all the other functions)

  assert topLevelNode.kind == nnkProcDef

  if not isGlsl():
    var formalParams = newEmptyNode()
    var body = newEmptyNode()
    for n in topLevelNode:
      case n.kind
      of nnkFormalParams:
        formalParams = n
      of nnkEmpty, nnkSym, nnkPragma:
        discard
      else:
        body = n
    let params = gatherEntryParams(formalParams)
    emitBackendEntry(params, body, res)
    return

  var entryStage = shaderAuto
  for n in topLevelNode:
    case n.kind
    of nnkEmpty:
      discard
    of nnkSym:
      discard
    of nnkFormalParams:
      ## Main function parameters are different in they they go in as globals.
      res.addGap()
      entryStage = resolvedStage(gatherEntryParams(n))
      var inLocation = 0
      var outLocation = 0
      for paramDefs in n:
        if paramDefs.kind == nnkIdentDefs:
          let typeNode = paramDefs[^2]
          for i in 0 ..< paramDefs.len - 2:
            let param = paramDefs[i]
            if param.strVal in ["gl_FragColor", "gl_Position"]:
              continue
            if typeNode.kind == nnkVarTy:
              if typeNode[0].repr == "seq":
                res.add "buffer?"
                res.add typeNode.repr
                continue
              elif typeNode[0].repr == "int":
                res.add "flat "
              if isVulkan():
                res.add "layout(location = "
                res.add $outLocation
                res.add ") "
                inc outLocation
              res.add "out "
              res.add typeRename(typeNode[0].strVal)
            else:
              if typeNode.kind == nnkBracketExpr:
                if isVulkan():
                  res.add "layout(location = "
                  res.add $inLocation
                  res.add ") "
                  inc inLocation
                res.add "in "
                res.add typeString(typeNode)
              else:
                if shaderTarget != glslES3 and param.strVal == "gl_FragCoord":
                  res.add "layout(origin_upper_left) "
                if typeNode.strVal == "int":
                  res.add "flat "
                if isVulkan():
                  res.add "layout(location = "
                  res.add $inLocation
                  res.add ") "
                  inc inLocation
                res.add "in "
                res.add typeRename(typeNode.strVal)
            res.add " "
            res.add param.strVal
            res.addSmart ';'
            res.add "\n"
    else:
      res.addGap()
      res.add "void main() {\n"
      let oldUseResult = useResult
      useResult = false
      n.toCodeStmts(res, level+1)
      useResult = oldUseResult
      if isVulkan() and entryStage == shaderVertex:
        res.add "  gl_Position.y = -gl_Position.y;\n"
      res.add "}\n"

proc hasResult(node: NimNode): bool =
  if node.kind == nnkSym and node.strVal == "result":
    return true
  for c in node.children:
    if c.hasResult():
      return true
  return false

proc procDef(topLevelNode: NimNode): string =
  ## Process whole function (that is not the main function).

  var procName = ""
  var paramsStr = ""
  var returnType = "void"

  assert topLevelNode.kind in {nnkFuncDef, nnkProcDef}
  for n in topLevelNode:
    case n.kind
    of nnkEmpty, nnkPragma:
      discard
    of nnkSym:
      procName = $n
    of nnkFormalParams:
      # Reading parameter list `(x, y, z: float)`
      if n[0].kind != nnkEmpty:
        returnType = typeRename(n[0].strVal)
      for paramDef in n[1 .. ^1]:
        # The paramDef is like `x, y, z: float`.
        if paramDef.kind != nnkEmpty:
          for param in paramDef[0 ..< ^2]:
            # Process each `x`, `y`, `z` in a loop.
            paramsStr.add "  "
            let paramName = param.repr()
            let paramType = param.getTypeInst()
            if paramType.kind == nnkVarTy:
              # Process `x: var float`
              if isGlsl() and paramType[0].strVal == "int":
                paramsStr.add "flat "
              if isMetal():
                paramsStr.add "thread "
                paramsStr.add typeRename(paramType[0].strVal)
                paramsStr.add "&"
              else:
                paramsStr.add "inout "
                paramsStr.add typeRename(paramType[0].strVal)
            elif paramType.kind == nnkBracketExpr:
              # Process varying[uniform].
              # TODO test?
              paramsStr.add paramType[0].strVal
              paramsStr.add " "
              paramsStr.add typeRename(paramType[1].strVal)
            else:
              # Just a simple `x: float` case.
              if isGlsl() and paramType.strVal == "int":
                paramsStr.add "flat "
              paramsStr.add typeRename(paramType.strVal)
            paramsStr.add " "
            paramsStr.add paramName
            paramsStr.add ",\n"
    else:
      if paramsStr.len > 0:
        paramsStr = paramsStr[0 .. ^3] & "\n"
      result.add returnType & " " & procName & "(\n" & paramsStr & ") {\n"
      useResult = n.hasResult()
      if useResult:
        result.addIndent(1)
        result.add returnType
        result.add " result;"
      n.toCodeStmts(result, 1)
      if useResult:
        if "return result" notin result[^20..^1]:
          result.addIndent(1)
          result.add "return result;\n"
      result.add "}"

proc gatherTypes(
  typeInst: NimNode,
  types: var Table[string, string]
) =
  ## Looks for types used and gathers their struct definitions.
  var typeInst = typeInst
  if typeInst.kind == nnkVarTy:
    typeInst = typeInst[0]
  if typeInst.kind == nnkBracketExpr:
    for i in 1 ..< typeInst.len:
      gatherTypes(typeInst[i], types)
    return

  if typeInst.kind == nnkSym:
    let name = typeInst.strVal
    if name in types: return
    if typeRename(name) != name: return
    if name in ["ColorRGBX"]:
      # Special case for ColorRGBX which is handled as vec4.
      return

    let impl = typeInst.getImpl()
    if impl.kind == nnkTypeDef and impl[2].kind == nnkObjectTy:
      var def = "struct " & name & " {\n"
      let obj = impl[2]
      let reclist = obj[2]
      for field in reclist:
        if field.kind == nnkIdentDefs:
          let fieldTypeNode = field[^2]
          let fieldType = fieldTypeNode.getTypeInst()
          gatherTypes(fieldType, types)
          for i in 0 ..< field.len - 2:
            var fieldName = field[i].repr
            if fieldName.endsWith("*"):
              fieldName = fieldName[0 .. ^2]
            def.add "  " & typeString(fieldType) & " " & fieldName & ";\n"
      def.add "};"
      types[name] = def

proc gatherFunction(
  topLevelNode: NimNode,
  functions: var Table[string, string],
  globals: var Table[string, string],
  types: var Table[string, string],
  hlslUniforms: var seq[dx12.UniformParam],
  hlslUniformNames: var Table[string, bool],
  hlslTextures: var Table[string, int],
  vulkanUniforms: var seq[vulkan.UniformParam],
  vulkanUniformNames: var Table[string, bool],
  vulkanTextures: var Table[string, int]
) =

  ## Looks for functions this function calls and brings them up
  for n in topLevelNode:
    if n.kind == nnkSym:
      # Looking for globals.
      let name = n.strVal
      if name notin glslGlobals and name notin glslFunctions and name notin globals:
        if n.owner().symKind == nskModule:
          let impl = n.getImpl()
          if impl.kind notin {
            nnkTypeDef,
            nnkIteratorDef,
            nnkProcDef,
            nnkFuncDef
            } and impl.kind != nnkNilLit:
            var defStr = ""
            let typeInst = n.getTypeInst
            gatherTypes(typeInst, types)
            var addGlobal = true
            if typeInst.kind == nnkBracketExpr:
              # might be a uniform
              if typeInst[0].repr in ["Uniform", "UniformWriteOnly", "Attribute"]:
                let (samplerType, arraySuffix) = splitArrayType(typeInst[1])
                if isVulkan():
                  if typeInst[0].repr == "Uniform" and
                      typeInst[1].repr in shaderSamplerTypes:
                    let textureBinding =
                      if name in vulkanTextures:
                        vulkanTextures[name]
                      else:
                        let nextBinding = vulkanTextures.len
                        vulkanTextures[name] = nextBinding
                        nextBinding
                    defStr.add vulkanSamplerDecl(name, samplerType, textureBinding)
                  elif typeInst[0].repr == "Uniform":
                    if name notin vulkanUniformNames:
                      vulkanUniformNames[name] = true
                      vulkanUniforms.add (
                        name: name & arraySuffix,
                        typ: samplerType
                      )
                    addGlobal = false
                  else:
                    defStr.add samplerType
                elif isGlsl():
                  defStr.add typeRename(typeInst[0].repr)
                  defStr.add " "
                  if shaderTarget == glslES3 and glsl3NeedsHighp(samplerType):
                    defStr.add "highp "
                  defStr.add samplerType
                elif isHlsl():
                  if typeInst[0].repr == "Uniform" and
                      typeInst[1].repr in shaderSamplerTypes:
                    let textureRegister =
                      if name in hlslTextures:
                        hlslTextures[name]
                      else:
                        let nextRegister = hlslTextures.len
                        hlslTextures[name] = nextRegister
                        nextRegister
                    defStr.add hlslTextureDecl(name, samplerType, textureRegister)
                    globals[name & "Sampler"] = hlslSamplerDecl(
                      name,
                      textureRegister,
                      typeInst[1].repr
                    )
                  elif typeInst[0].repr == "Uniform":
                    if name notin hlslUniformNames:
                      hlslUniformNames[name] = true
                      hlslUniforms.add (
                        name: name & arraySuffix,
                        typ: samplerType
                      )
                    addGlobal = false
                  else:
                    defStr.add samplerType
                else:
                  if typeInst[0].repr == "Uniform":
                    defStr.add "constant "
                    defStr.add samplerType
                  elif typeInst[0].repr == "UniformWriteOnly":
                    defStr.add samplerType
                  else:
                    defStr.add samplerType
              elif typeInst[0].repr == "array":
                let (baseType, arraySuffix) = splitArrayType(typeInst)
                defStr.add baseType
                defStr.add " "
                defStr.add name
                defStr.add arraySuffix
                addGlobal = false
              else:
                err "Invalid x[y].", n
            else:
              defStr.add typeRename(typeInst.repr)
            if addGlobal:
              if not (isHlsl() and typeInst.kind == nnkBracketExpr and
                  typeInst[0].repr == "Uniform" and
                  typeInst[1].repr in shaderSamplerTypes) and
                  not (isVulkan() and typeInst.kind == nnkBracketExpr and
                  typeInst[0].repr == "Uniform" and
                  typeInst[1].repr in shaderSamplerTypes):
                defStr.add " " & name
                if typeInst.kind == nnkBracketExpr and
                    typeInst[0].repr in ["Uniform", "UniformWriteOnly", "Attribute"]:
                  let (_, arraySuffix) = splitArrayType(typeInst[1])
                  defStr.add arraySuffix
              if impl[2].kind != nnkEmpty:
                defStr.add " = " & repr(impl[2])
              defStr.addSmart ';'
            if addGlobal and defStr notin ["uniform Uniform = T;",
                "attribute Attribute = T;"]:
              globals[name] = defStr

    if n.kind == nnkCall:
      # Looking for functions.
      if repr(n[0]) == "[]":
        continue
      let procName = repr n[0]
      if procName in ignoreFunctions:
        continue
      if procName notin glslFunctions and
        procName notin functions and
        not isVectorAccess(procName):
        ## If its not a builtin proc, we need to bring definition.
        let impl = n[0].getImpl()
        gatherFunction(
          impl,
          functions,
          globals,
          types,
          hlslUniforms,
          hlslUniformNames,
          hlslTextures,
          vulkanUniforms,
          vulkanUniformNames,
          vulkanTextures
        )
        functions[procName] = procDef(impl)

    if n.kind == nnkFormalParams:
      for i in 1 ..< n.len:
        let paramDef = n[i]
        let paramType = paramDef[^2].getTypeInst()
        gatherTypes(paramType, types)

    gatherFunction(
      n,
      functions,
      globals,
      types,
      hlslUniforms,
      hlslUniformNames,
      hlslTextures,
      vulkanUniforms,
      vulkanUniformNames,
      vulkanTextures
    )

proc toGLSLInner*(s: NimNode, version, extra: string): string =

  var code: string

  # Add shader header stuff.
  if isGlsl():
    if version.len > 0:
      code.add "#version " & version & "\n"
    code.add extra
  elif isMetal():
    code.add metalHeader
  elif isHlsl():
    code.add hlslHeader
  code.add "// from " & s.strVal & "\n"

  var n = getImpl(s)

  # Gather all globals and functions, and globals and functions they use.
  var functions: Table[string, string]
  var globals: Table[string, string]
  var types: Table[string, string]
  var hlslUniforms: seq[dx12.UniformParam]
  var hlslUniformNames: Table[string, bool]
  var hlslTextures: Table[string, int]
  var vulkanUniforms: seq[vulkan.UniformParam]
  var vulkanUniformNames: Table[string, bool]
  var vulkanTextures: Table[string, int]
  gatherFunction(
    n,
    functions,
    globals,
    types,
    hlslUniforms,
    hlslUniformNames,
    hlslTextures,
    vulkanUniforms,
    vulkanUniformNames,
    vulkanTextures
  )

  # Put types first.
  code.addGap()
  for k, v in types:
    code.add(v)
    code.add "\n"

  # Put globals next.
  code.addGap()
  if isHlsl() and hlslUniforms.len > 0:
    code.add emitHlslUniformBuffer(hlslUniforms)
    code.add "\n"
  if isVulkan() and vulkanUniforms.len > 0:
    code.add emitVulkanPushConstants(vulkanUniforms)
    code.add "\n"
  for k, v in globals:
    code.add(v)
    code.add "\n"

  # Put functions definition (just name and types part).
  code.addGap()
  for k, v in functions:
    var funCode = v.split(" {")[0]
    funCode = funCode
      .replace("\n", "")
      .replace("  ", " ")
      .replace(",  ", ", ")
      .replace("( ", "(")
    code.add funCode
    code.addSmart ';'
    code.add "\n"

  # Put functions (with bodies) next.
  code.addGap()
  for k, v in functions:
    code.add v
    code.add "\n"

  # Put the main function last.
  toCodeTopLevel(n, code)

  return code

proc toGLSLInner*(s: NimNode, target: GlslTarget): string =
  ## Converts proc to a GLSL string for the given target.
  shaderTarget = target
  shaderStage = shaderAuto
  case target
  of glsl4Desktop:
    toGLSLInner(s, glsl4DesktopVersion, glsl4DesktopExtra)
  of vulkanGlsl450:
    toGLSLInner(s, vulkanGlsl450Version, vulkanGlsl450Extra)
  of glsl3Desktop:
    toGLSLInner(s, glsl3DesktopVersion, glsl3DesktopExtra)
  of glsl3WebGL:
    toGLSLInner(s, glsl3WebGLVersion, glsl3WebGLExtra)
  of hlslDX12:
    toGLSLInner(s, "", "")
  of metalMSL:
    toGLSLInner(s, "", "")

proc toShaderInner*(
  s: NimNode,
  target: ShaderTarget,
  stage = shaderAuto
): string =
  ## Converts proc to shader source for the given target.
  shaderTarget = target
  shaderStage = stage
  case target
  of glsl4Desktop:
    toGLSLInner(s, glsl4DesktopVersion, glsl4DesktopExtra)
  of vulkanGlsl450:
    toGLSLInner(s, vulkanGlsl450Version, vulkanGlsl450Extra)
  of glsl3Desktop:
    toGLSLInner(s, glsl3DesktopVersion, glsl3DesktopExtra)
  of glsl3WebGL:
    toGLSLInner(s, glsl3WebGLVersion, glsl3WebGLExtra)
  of hlslDX12, metalMSL:
    toGLSLInner(s, "", "")

macro toGLSL*(
  s: typed,
  target: static[GlslTarget]
): string =
  ## Converts proc to a GLSL string for the given target.
  newLit(toGLSLInner(s, target))

macro toGLSL*(
  s: typed,
  version = "410",
  extra = "precision highp float;\n"
): string =
  ## Converts proc to a glsl string.
  ## For target-aware compilation, use the GlslTarget overload instead.
  shaderTarget = if "es" in version.strVal: glslES3 else: glslDesktop
  shaderStage = shaderAuto
  newLit(toGLSLInner(s, version.strVal, extra.strVal))

macro toShader*(
  s: typed,
  target: static[ShaderTarget],
  stage: static[ShaderStage] = shaderAuto
): string =
  ## Converts proc to shader source for the given target and stage.
  newLit(toShaderInner(s, target, stage))

macro toHLSL*(
  s: typed,
  stage: static[ShaderStage] = shaderAuto
): string =
  ## Converts proc to HLSL source for DirectX 12.
  newLit(toShaderInner(s, hlslDX12, stage))

macro toMSL*(
  s: typed,
  stage: static[ShaderStage] = shaderAuto
): string =
  ## Converts proc to Metal Shading Language source.
  newLit(toShaderInner(s, metalMSL, stage))

## GLSL helper functions

type
  Uniform*[T] = T
  UniformWriteOnly*[T] = T
  Attribute*[T] = T

  SamplerBuffer* = object
    data*: seq[float32]

  ImageBuffer* = object
    image*: Image

  UImageBuffer* = object
    image*: Image

  Sampler2d* = object
    image*: Image

  SamplerCube* = object
    faces*: array[6, Image]

  Sampler2dShadow* = object
    image*: Image

  USampler2d* = object
    image*: Image

  Sampler2dArray* = object
    images*: seq[Image]

var
  ## GLSL globals.
  gl_Position*: Vec4
  gl_VertexID*: int32
  gl_FrontFacing*: bool

proc mat3*(m: Mat4): Mat3 =
  result[0, 0] = m[0, 0]
  result[0, 1] = m[0, 1]
  result[0, 2] = m[0, 2]
  result[1, 0] = m[1, 0]
  result[1, 1] = m[1, 1]
  result[1, 2] = m[1, 2]
  result[2, 0] = m[2, 0]
  result[2, 1] = m[2, 1]
  result[2, 2] = m[2, 2]

proc mat4*(diagonal: float32): Mat4 =
  result[0, 0] = diagonal
  result[1, 1] = diagonal
  result[2, 2] = diagonal
  result[3, 3] = diagonal

proc `*`*(m: Mat4, s: float32): Mat4 =
  for i in 0 ..< 4:
    for j in 0 ..< 4:
      result[i, j] = m[i, j] * s

proc `*`*(s: float32, m: Mat4): Mat4 =
  m * s

proc `+`*(a, b: Mat4): Mat4 =
  for i in 0 ..< 4:
    for j in 0 ..< 4:
      result[i, j] = a[i, j] + b[i, j]

proc texelFetch*(buffer: Uniform[SamplerBuffer], index: SomeInteger): Vec4 =
  vec4(buffer.data[index.int], 0, 0, 0)

proc texelFetch*(buffer: Uniform[Sampler2D], pos: IVec2, level: int): Vec4 =
  let c = buffer.image[pos.x.int, pos.y.int]
  return vec4(c.r.float32/255, c.g.float32/255, c.b.float32/255, c.a.float32/255)

proc texelFetch*(buffer: Uniform[USampler2D], pos: IVec2, level: int): UVec4 =
  ## CPU stub for usampler2D; not used at runtime. Returns zeros.
  uvec4(0u32, 0u32, 0u32, 0u32)

proc imageLoad*(
  buffer: var UniformWriteOnly[UImageBuffer], index: int32
): UVec4 =
  result.x = buffer.image.data[index.int].r
  result.g = buffer.image.data[index.int].g
  result.b = buffer.image.data[index.int].b
  result.a = buffer.image.data[index.int].a

proc imageStore*(buffer: var UniformWriteOnly[UImageBuffer], index: int32,
    color: UVec4) =
  buffer.image.data[index.int].r = clamp(color.x, 0, 255).uint8
  buffer.image.data[index.int].g = clamp(color.y, 0, 255).uint8
  buffer.image.data[index.int].b = clamp(color.z, 0, 255).uint8
  buffer.image.data[index.int].a = clamp(color.w, 0, 255).uint8

proc imageStore*(buffer: var UniformWriteOnly[ImageBuffer], index: int32,
    color: Vec4) =
  buffer.image.data[index.int].r = clamp(color.x*255, 0, 255).uint8
  buffer.image.data[index.int].g = clamp(color.y*255, 0, 255).uint8
  buffer.image.data[index.int].b = clamp(color.z*255, 0, 255).uint8
  buffer.image.data[index.int].a = clamp(color.w*255, 0, 255).uint8

proc imageStore*(buffer: var Uniform[Sampler2D], pos: IVec2,
    color: Vec4) =
  buffer.image[pos.x.int, pos.y.int] = rgbx(
    clamp(color.x*255, 0, 255).uint8,
    clamp(color.y*255, 0, 255).uint8,
    clamp(color.z*255, 0, 255).uint8,
    clamp(color.w*255, 0, 255).uint8,
  )

proc vec4*(c: ColorRGBX): Vec4 =
  vec4(
    c.r.float32/255,
    c.g.float32/255,
    c.b.float32/255,
    c.a.float32/255
  )

proc dFdx*(a: float32): float32 =
  raise newException(Exception, "dFdx is not implemented")

proc dFdx*(a: Vec2): Vec2 =
  raise newException(Exception, "dFdx is not implemented")

proc dFdx*(a: Vec3): Vec3 =
  raise newException(Exception, "dFdx is not implemented")

proc dFdx*(a: Vec4): Vec4 =
  raise newException(Exception, "dFdx is not implemented")

proc dFdy*(a: float32): float32 =
  raise newException(Exception, "dFdy is not implemented")

proc dFdy*(a: Vec2): Vec2 =
  raise newException(Exception, "dFdy is not implemented")

proc dFdy*(a: Vec3): Vec3 =
  raise newException(Exception, "dFdy is not implemented")

proc dFdy*(a: Vec4): Vec4 =
  raise newException(Exception, "dFdy is not implemented")

proc fwidth*(a: float32): float32 =
  raise newException(Exception, "fwidth is not implemented")

proc fwidth*(a: Vec2): Vec2 =
  raise newException(Exception, "fwidth is not implemented")

proc fwidth*(a: Vec3): Vec3 =
  raise newException(Exception, "fwidth is not implemented")

proc fwidth*(a: Vec4): Vec4 =
  raise newException(Exception, "fwidth is not implemented")

proc fmod*(x, y: float32): float32 =
  x - y * floor(x / y)

proc fmod*(x: Vec2, y: float32): Vec2 =
  vec2(fmod(x.x, y), fmod(x.y, y))

proc fmod*(x: Vec3, y: float32): Vec3 =
  vec3(fmod(x.x, y), fmod(x.y, y), fmod(x.z, y))

proc fmod*(x: Vec4, y: float32): Vec4 =
  vec4(fmod(x.x, y), fmod(x.y, y), fmod(x.z, y), fmod(x.w, y))

proc fmod*(x, y: Vec2): Vec2 =
  vec2(fmod(x.x, y.x), fmod(x.y, y.y))

proc fmod*(x, y: Vec3): Vec3 =
  vec3(fmod(x.x, y.x), fmod(x.y, y.y), fmod(x.z, y.z))

proc fmod*(x, y: Vec4): Vec4 =
  vec4(fmod(x.x, y.x), fmod(x.y, y.y), fmod(x.z, y.z), fmod(x.w, y.w))

proc fract*(a: float32): float32 =
  a - floor(a)

proc fract*(a: Vec2): Vec2 =
  vec2(fract(a.x), fract(a.y))

proc fract*(a: Vec3): Vec3 =
  vec3(fract(a.x), fract(a.y), fract(a.z))

proc fract*(a: Vec4): Vec4 =
  vec4(fract(a.x), fract(a.y), fract(a.z), fract(a.w))

proc smoothstep*(a, b, x: float32): float32 =
  let t = clamp((x - a) / (b - a), 0.0, 1.0)
  t * t * (3.0 - 2.0 * t)

proc smoothstep*(a, b, x: Vec2): Vec2 =
  vec2(smoothstep(a.x, b.x, x.x), smoothstep(a.y, b.y, x.y))

proc smoothstep*(a, b, x: Vec3): Vec3 =
  vec3(smoothstep(a.x, b.x, x.x), smoothstep(a.y, b.y, x.y), smoothstep(a.z, b.z, x.z))

proc smoothstep*(a, b, x: Vec4): Vec4 =
  vec4(smoothstep(a.x, b.x, x.x), smoothstep(a.y, b.y, x.y), smoothstep(a.z, b.z, x.z), smoothstep(a.w, b.w, x.w))

proc texture*(buffer: Uniform[Sampler2D], pos: Vec2): Vec4 =
  let pos = pos - vec2(0.5 / buffer.image.width.float32, 0.5 /
      buffer.image.height.float32)
  buffer.image.getRgbaSmooth(
    ((pos.x mod 1.0) * buffer.image.width.float32),
    ((pos.y mod 1.0) * buffer.image.height.float32)
  ).vec4()

proc texture*(buffer: Uniform[SamplerCube], pos: Vec3): Vec4 =
  ## CPU stub for samplerCube; not used at runtime. Returns opaque black.
  vec4(0, 0, 0, 1)

proc texture*(buffer: Uniform[Sampler2dShadow], pos: Vec3): float32 =
  ## CPU stub for sampler2DShadow; not used at runtime. Returns fully lit.
  1.0

proc textureLod*(buffer: Uniform[SamplerCube], pos: Vec3, lod: float32): Vec4 =
  ## CPU stub for samplerCube textureLod; not used at runtime.
  texture(buffer, pos)

proc reflect*(incident, normal: Vec3): Vec3 =
  incident - 2.0'f32 * dot(normal, incident) * normal

proc textureSize*(buffer: Uniform[Sampler2D], level: int): Vec2 =
  vec2(buffer.image.width.float32, buffer.image.height.float32)

proc textureSize*(buffer: Uniform[SamplerCube], level: int): Vec2 =
  let image = buffer.faces[0]
  vec2(image.width.float32, image.height.float32)

proc textureSize*(buffer: Uniform[Sampler2dShadow], level: int): Vec2 =
  vec2(buffer.image.width.float32, buffer.image.height.float32)

proc textureGrad*(
  s: Uniform[Sampler2D],
  uv: Vec3,
  dUVdx: Vec2,
  dUVdy: Vec2
): Vec4 =
  texture(s, uv.xy)

proc textureGrad*(
  s: Uniform[Sampler2DArray],
  uvw: Vec3,
  dUVdx: Vec2,
  dUVdy: Vec2
): Vec4 =
  vec4(0, 0, 0, 0)

proc discardFragment*() =
  discard
