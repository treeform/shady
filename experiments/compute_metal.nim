{.
  passC: "-D_GLFW_COCOA",
  passL: "-framework Cocoa -framework Metal",
  compile: "compute_metal.m",
.}
#import staticglfw

let shader = """#include <metal_stdlib>
using namespace metal;

kernel void add(
    const device float2 *in [[ buffer(0) ]],
    device float  *out [[ buffer(1) ]],
    uint id [[ thread_position_in_grid ]]
) {
    out[id] = in[id].x + in[id].y;
}
"""

proc main2(): cint {.importc.}

echo "here"
discard main2()
echo "bye"
