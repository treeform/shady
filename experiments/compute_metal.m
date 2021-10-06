#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

int main2(void) {
  @autoreleasepool {

    // Setup
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    id<MTLCommandQueue> commandQueue = [device newCommandQueue];

    //id<MTLLibrary> library = [device newDefaultLibrary];
    //id<MTLFunction> kernelFunction = [library newFunctionWithName:@"add"];

    MTLCompileOptions* compileOptions = [MTLCompileOptions new];
    compileOptions.languageVersion = MTLLanguageVersion1_1;
    NSError* compileError;
    id<MTLLibrary> lib = [device newLibraryWithSource:
        @"#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "kernel void add(\n"
        "    uint3 id [[ thread_position_in_grid ]],\n"
        "    const device float2 *in [[ buffer(0) ]],\n"
        "    device float *out [[ buffer(1) ]]\n"
        ") {\n"
        "       out[id.x] = in[id.x].x + in[id.x].y;"
        "}\n"
        options:compileOptions
        error:&compileError
    ];
    if (!lib)
    {
        NSLog(@"can't create library: %@", compileError);
        exit(EXIT_FAILURE);
    }
    id<MTLFunction> kernelFunction = [lib newFunctionWithName:@"add"];

    // pipeline
    NSError *error = NULL;
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    [encoder
        setComputePipelineState:[
            device
            newComputePipelineStateWithFunction:kernelFunction
            error:&error
        ]
    ];

    // Set Data

    // input buffer
    float input[] = {1,2};
    NSInteger dataSize = sizeof(input);
    id<MTLBuffer> inputBuffer = [
      device
      newBufferWithBytes:input
      length:dataSize
      options:0
    ];
    [encoder
      setBuffer:inputBuffer
      offset:0
      atIndex:0
    ];

    // output buffer
    id<MTLBuffer> outputBuffer = [
      device
      newBufferWithLength:sizeof(float)
      options:0
    ];
    [encoder
      setBuffer:outputBuffer
      offset:0
      atIndex:1
    ];

    // Run Kernel
    MTLSize numThreadgroups = {1,1,1};
    MTLSize numgroups = {1,1,1};
    [encoder dispatchThreadgroups:numThreadgroups threadsPerThreadgroup:numgroups];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    // Results
    float* output = (float*)[outputBuffer contents];
    printf("result = %f\n", output[0]);
  }
  return 0;
}
