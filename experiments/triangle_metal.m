#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>

static void error_callback(int error, const char* description) {
    fputs(description, stderr);
}

CAMetalLayer* layer;
id<MTLCommandQueue> cq;
MTLRenderPipelineDescriptor* rpd;
id<MTLRenderPipelineState> rps;

int metalSetup(NSWindow* nswin, const char* utf8Shader) {
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	if (!device)
		exit(EXIT_FAILURE);

    layer = [CAMetalLayer layer];
    layer.device = device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    nswin.contentView.layer = layer;
    nswin.contentView.wantsLayer = YES;
    MTLCompileOptions* compileOptions = [MTLCompileOptions new];
    compileOptions.languageVersion = MTLLanguageVersion1_1;
    NSError* compileError;

    NSString* shader = [NSString stringWithUTF8String:utf8Shader];

    id<MTLLibrary> lib = [
        device
        newLibraryWithSource:shader
       options:compileOptions error:&compileError
    ];
    if (!lib)
    {
        NSLog(@"can't create library: %@", compileError);
        exit(EXIT_FAILURE);
    }
    id<MTLFunction> vs = [lib newFunctionWithName:@"vertexShader"];
    assert(vs);
    id<MTLFunction> fs = [lib newFunctionWithName:@"fragmentShader"];
    assert(fs);
    cq = [device newCommandQueue];
    assert(cq);
    rpd = [MTLRenderPipelineDescriptor new];
    rpd.vertexFunction = vs;
    rpd.fragmentFunction = fs;
    rpd.colorAttachments[0].pixelFormat = layer.pixelFormat;
    rps = [device newRenderPipelineStateWithDescriptor:rpd error:NULL];
    assert(rps);
}

int metalDraw(int width, int height) {
    float ratio = width / (float) height;
    layer.drawableSize = CGSizeMake(width, height);
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    assert(drawable);
    id<MTLCommandBuffer> cb = [cq commandBuffer];
    MTLRenderPassDescriptor* rpd = [MTLRenderPassDescriptor new];
    MTLRenderPassColorAttachmentDescriptor* cd = rpd.colorAttachments[0];
    cd.texture = drawable.texture;
    cd.loadAction = MTLLoadActionClear;
    cd.clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0);
    cd.storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> rce = [cb renderCommandEncoderWithDescriptor:rpd];
    [rce setRenderPipelineState:rps];
    [rce setVertexBytes:(vector_float4[]){
        { -1, -3, 0, 1 },
        { -1, 1, 0, 1 },
        { 3, 1, 0, 1 },
    } length:3 * sizeof(vector_float4) atIndex:0];
    [rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [rce endEncoding];
    [cb presentDrawable:drawable];
    [cb commit];
    return 0;
}
