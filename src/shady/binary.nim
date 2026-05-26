import std/[os, strutils]

type BinaryShaderStage* = enum
  binaryVertex
  binaryFragment
  binaryCompute

proc quoteShell(path: string): string =
  "\"" & path.replace("\"", "\\\"") & "\""

proc ensureParent(path: string) {.compileTime.} =
  let dir = parentDir(path)
  if dir.len > 0:
    createDir(dir)

proc spirvStage(stage: BinaryShaderStage): string =
  case stage
  of binaryVertex: "vert"
  of binaryFragment: "frag"
  of binaryCompute: "comp"

proc writeShaderSource*(
  source, sourcePath: string
): string {.compileTime.} =
  ensureParent(sourcePath)
  writeFile(sourcePath, source)
  source

proc compileSpirvShader*(
  source, sourcePath, outputPath: string,
  stage: BinaryShaderStage
): string {.compileTime.} =
  discard writeShaderSource(source, sourcePath)
  ensureParent(outputPath)
  let compiler =
    when defined(windows):
      getEnv("SHADY_SPIRV_COMPILER", "glslangValidator.exe")
    else:
      getEnv("SHADY_SPIRV_COMPILER", "glslangValidator")
  let command =
    quoteShell(compiler) & " -V -S " & spirvStage(stage) &
    " -o " & quoteShell(outputPath) & " " & quoteShell(sourcePath)
  discard staticExec(command)
  readFile(outputPath)

proc compileHlslShader*(
  source, sourcePath, outputPath, entryPoint, target: string
): string {.compileTime.} =
  discard writeShaderSource(source, sourcePath)
  ensureParent(outputPath)
  let compiler =
    when defined(windows):
      getEnv("SHADY_HLSL_COMPILER", "dxc.exe")
    else:
      getEnv("SHADY_HLSL_COMPILER", "dxc")
  let command =
    quoteShell(compiler) & " -T " & target & " -E " & entryPoint &
    " -Fo " & quoteShell(outputPath) & " " & quoteShell(sourcePath)
  discard staticExec(command)
  readFile(outputPath)
