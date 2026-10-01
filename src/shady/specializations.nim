import std/strutils
import ./errors

proc replaceTextureReads*(
  source: string,
  textures: openArray[string]
): string =
  ## Folds unused floating-point GLSL texture reads to their neutral value.
  result = source
  for texture in textures:
    for function in ["texture", "textureLod"]:
      let prefix = function & "(" & texture & ","
      var start = result.find(prefix)
      while start >= 0:
        var
          finish = start + function.len
          depth = 0
        while finish < result.len:
          case result[finish]
          of '(':
            inc depth
          of ')':
            dec depth
            if depth == 0:
              inc finish
              break
          else:
            discard
          inc finish
        if depth != 0:
          raise newException(ShadyError,
            "Unbalanced generated texture read")
        result = result[0 ..< start] & "vec4(1.0)" & result[finish .. ^1]
        start = result.find(prefix, start + 9)

proc shareMetalSamplers*(source: string, bindings: openArray[int]): string =
  ## Shares equivalent sampler states while retaining independent textures.
  let start = source.find("fragment ")
  if start < 0:
    raise newException(ShadyError, "Expected a fragment entry")
  result = source[0 ..< start]
  var
    entry = source[start .. ^1]
    names: seq[string]
    lines = entry.splitLines()
  for line in lines:
    let words = line.strip().splitWhitespace()
    if words.len >= 3 and words[0] == "sampler" and "[[sampler(" in line:
      names.add(words[1])
  if bindings.len != names.len:
    raise newException(ShadyError, "Sampler binding count differs")
  var declarations: seq[string]
  for line in lines:
    let words = line.strip().splitWhitespace()
    if words.len >= 3 and words[0] == "sampler" and "[[sampler(" in line:
      continue
    declarations.add(line)
  entry = declarations.join("\n")
  let signatureEnd = entry.find("\n) {")
  if signatureEnd < 0:
    raise newException(ShadyError, "Missing fragment signature")
  var count = 0
  for binding in bindings:
    count = max(count, binding + 1)
  if count > 16:
    raise newException(ShadyError, "Metal supports 16 sampler states")
  var parameters = ""
  for i in 0 ..< count:
    parameters.add("  sampler sharedSampler" & $i & " [[sampler(" & $i & ")]]")
    if i < count - 1:
      parameters.add(",")
    parameters.add("\n")
  entry.insert("\n" & parameters, signatureEnd)
  for i, name in names:
    entry = entry.replace(name, "sharedSampler" & $bindings[i])
  result.add(entry)
