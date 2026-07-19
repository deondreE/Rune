#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Cocoa/Cocoa.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include "renderer.hpp"
#include <vector>
#include <map>

struct NativeVertex {
    IVec2 pos;
    IVec2 uv;
    float color[4];
};

struct GlyphData {
    IVec2 size;
    IVec2 bearing;
    u32 advance;
    IVec2 uv_min;
    IVec2 uv_max;
};

class MetalRenderer : public IRenderer {
public:
	MetalRenderer() : device(nil), commandQueue(nil), metalLayer(nil) {}

	bool initialize(WindowHandle handle, RenderConfig config) override {
       
		NSWindow* nswin = (__bridge NSWindow*)handle.native_handle;
        if (!nswin) return false;

		device = MTLCreateSystemDefaultDevice();
		commandQueue = [device newCommandQueue];		

		metalLayer = [CAMetalLayer layer];
		metalLayer.device = device;
		metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		metalLayer.framebufferOnly = YES;
		nswin.contentView.layer = metalLayer;
		nswin.contentView.wantsLayer = YES;
		
		NSError* error = nil;
		const char* shaderCStr = R"METAL(
        #include <metal_stdlib>
        using namespace metal;
        struct VertexIn {
            float2 position [[attribute(0)]];
            float2 uv       [[attribute(1)]];
            float4 color    [[attribute(2)]];
        };
        struct VertexOut {
            float4 position [[position]];
            float2 uv;
            float4 color;
        };
        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant float2& viewport_size [[buffer(1)]]) {
            VertexOut out;
            float2 clip_space = (in.position / viewport_size) * 2.0 - 1.0;
            out.position = float4(clip_space.x, -clip_space.y, 0.0, 1.0);
            out.uv = in.uv;
            out.color = in.color;
            return out;
        }
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                       texture2d<float> font_texture [[texture(0)]]) {
            constexpr sampler s(mag_filter::linear, min_filter::linear);
            float mask = font_texture.sample(s, in.uv).r;
            return float4(in.color.rgb, in.color.a * mask);
        }
        )METAL";
		NSString* shaderSrc = [NSString stringWithUTF8String:shaderCStr];
		id<MTLLibrary> library = [device newLibraryWithSource:shaderSrc options:nil error:&error];
		if (!library) {
			NSLog(@"Failed to compile Metal shaders: %@", error);
			return false;
		}

		id<MTLFunction> vFunc = [library newFunctionWithName:@"vertex_main"];
        id<MTLFunction> fFunc = [library newFunctionWithName:@"fragment_main"];

        MTLRenderPipelineDescriptor* pd = [[MTLRenderPipelineDescriptor alloc] init];
        pd.vertexFunction = vFunc;
        pd.fragmentFunction = fFunc;
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pd.colorAttachments[0].blendingEnabled = YES;
        pd.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pd.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        MTLVertexDescriptor* vd = [[MTLVertexDescriptor alloc] init];
        vd.attributes[0].format = MTLVertexFormatFloat2;               // position
        vd.attributes[0].offset = offsetof(NativeVertex, pos);
        vd.attributes[0].bufferIndex = 0;

        vd.attributes[1].format = MTLVertexFormatFloat2;               // uv
        vd.attributes[1].offset = offsetof(NativeVertex, uv);
        vd.attributes[1].bufferIndex = 0;

        vd.attributes[2].format = MTLVertexFormatFloat4;               // color
        vd.attributes[2].offset = offsetof(NativeVertex, color);
        vd.attributes[2].bufferIndex = 0;

        vd.layouts[0].stride = sizeof(NativeVertex);
        vd.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

        pd.vertexDescriptor = vd;

        pipelineState = [device newRenderPipelineStateWithDescriptor:pd error:&error];
        if (!pipelineState) {
            NSLog(@"Pipeline creation failed: %@", error);
            return false;
        }

 		setup_font("/System/Library/Fonts/Helvetica.ttc", 24);

        vertexBuffer = [device newBufferWithLength:1024 * 1024 * sizeof(NativeVertex) 
                                           options:MTLResourceStorageModeShared];

        NSLog(@"Initializing pipeline!");
		return true;
	}

	void setup_font(const char* fontPath, int size) {
        FT_Library ft;
        if (FT_Init_FreeType(&ft)) { fprintf(stderr, "FreeType init failed\n"); return; }

        FT_Face face;
        if (FT_New_Face(ft, fontPath, 0, &face)) {
            fprintf(stderr, "Failed to load font: %s\n", fontPath);
            FT_Done_FreeType(ft);
            return;
        }
        FT_Set_Pixel_Sizes(face, 0, size);

        // Store line height from the face's scaled metrics (26.6 fixed-point -> pixels).
        // This is the correct inter-line distance, not just the tallest glyph bitmap.
        font_line_height = (float)(face->size->metrics.height >> 6);

        u32 atlasW = 1024, atlasH = 1024;
        u8* pixels = (u8*)calloc(atlasW * atlasH, 1);

        // Reserve texel (0,0) as solid white for draw_rect's mask sample.
        pixels[0] = 255;

        // Start glyph packing at x=1 so no glyph bitmap can overwrite the reserved pixel.
        u32 curX = 1, curY = 0, rowH = 0;

        for (unsigned char c = 32; c < 128; c++) {
            if (FT_Load_Char(face, c, FT_LOAD_RENDER)) continue; // skip glyphs that fail to load

            if (curX + face->glyph->bitmap.width >= atlasW) {
                curX = 0; curY += rowH + 1; rowH = 0;
            }

            u32 pitch = (u32)abs(face->glyph->bitmap.pitch);
            for (u32 r = 0; r < face->glyph->bitmap.rows; r++) {
                memcpy(&pixels[(curY + r) * atlasW + curX],
                       &face->glyph->bitmap.buffer[r * pitch],
                       face->glyph->bitmap.width);
            }

            GlyphData& gd = glyphMap[c];
            gd.size = {(float)face->glyph->bitmap.width, (float)face->glyph->bitmap.rows};
            gd.bearing = {(float)face->glyph->bitmap_left, (float)face->glyph->bitmap_top};
            gd.advance = (u32)face->glyph->advance.x;
            gd.uv_min = {(float)curX / atlasW, (float)curY / atlasH};   // was atlasW for both
            gd.uv_max = {(float)(curX + gd.size.x) / atlasW, (float)(curY + gd.size.y) / atlasH};

            curX += face->glyph->bitmap.width + 1;
            rowH = std::max(rowH, (u32)face->glyph->bitmap.rows);
        }

        // Space advance for tab-stop math (space may have no bitmap but does have advance).
        if (glyphMap.count(' '))
            font_space_advance = (float)(glyphMap[' '].advance >> 6);

        MTLTextureDescriptor* td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:atlasW height:atlasH mipmapped:NO];
        fontTexture = [device newTextureWithDescriptor:td];
        [fontTexture replaceRegion:MTLRegionMake2D(0,0,atlasW,atlasH) mipmapLevel:0 withBytes:pixels bytesPerRow:atlasW];

        free(pixels);
        FT_Done_Face(face);
        FT_Done_FreeType(ft);
    }

	void begin_frame() override {
		drawable = [metalLayer nextDrawable];
		renderPass = [MTLRenderPassDescriptor renderPassDescriptor];
		renderPass.colorAttachments[0].texture = drawable.texture;
		renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;
		renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;
		renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0.12, 0.12, 0.12, 1.0);
	}	

    void end_frame() override {
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];

        if (!batch.empty())
        {
            size_t maxVerts = 1024 * 1024;
            if (batch.size() > maxVerts) {
                fprintf(stderr, "Vertex batch overflow: %zu > %zu, truncating\n", batch.size(), maxVerts);
                batch.resize(maxVerts);
            }

            memcpy([vertexBuffer contents], batch.data(), batch.size() * sizeof(NativeVertex));

            IVec2 viewport = {(float)metalLayer.drawableSize.width, (float)metalLayer.drawableSize.height};

            [encoder setRenderPipelineState:pipelineState];
            [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
            [encoder setVertexBytes:&viewport length:sizeof(IVec2) atIndex:1];
            [encoder setFragmentTexture:fontTexture atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:batch.size()];
        }

        [encoder endEncoding];
        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];

        batch.clear(); 
    }

    void draw_rect(IVec2 pos, IVec2 size, IColor4 color) override {
        float x0 = pos.x;
        float y0 = pos.y;
        float x1 = pos.x + size.x;
        float y1 = pos.y + size.y;

        float r = color.r / 255.0f;
        float g = color.g / 255.0f;
        float b = color.b / 255.0f;
        float a = color.a / 255.0f;

        // For draw_rect, we use a UV coordinate that points 
        // to a white pixel in our texture atlas (usually char 32 'space')
        // or we can use (0,0) if we ensure the first pixel of the atlas is white.
        IVec2 uv = {0, 0}; 

        // Triangle 1
        batch.push_back({{x0, y1}, uv, {r, g, b, a}});
        batch.push_back({{x0, y0}, uv, {r, g, b, a}});
        batch.push_back({{x1, y0}, uv, {r, g, b, a}});

        // Triangle 2
        batch.push_back({{x0, y1}, uv, {r, g, b, a}});
        batch.push_back({{x1, y0}, uv, {r, g, b, a}});
        batch.push_back({{x1, y1}, uv, {r, g, b, a}});
    }

    void draw_text(const std::string& text, IVec2 pos, float32 size, IColor4 color) override {
        float x = pos.x;
        float y = pos.y;
        float r = color.r/255.f, g = color.g/255.f, b = color.b/255.f, a = color.a/255.f;

        // Width of a single tab stop in pixels.
        float tab_stop_px = font_space_advance * (float)tab_width;

        for (char c : text)
        {
            if (c == '\n') {
                x = pos.x;
                y += font_line_height;
                continue;
            }

            if (c == '\t') {
                // Snap x forward to the next tab stop, measured from the draw origin.
                float offset = x - pos.x;
                float next   = (std::floor(offset / tab_stop_px) + 1.0f) * tab_stop_px;
                x = pos.x + next;
                continue;
            }

            if (!glyphMap.count(c)) continue;
            GlyphData& gd = glyphMap[c];
            float x0 = x + gd.bearing.x;
            float y0 = y - gd.bearing.y;
            float x1 = x0 + gd.size.x;
            float y1 = y0 + gd.size.y;

            // Simple Quad (2 Triangles)
            batch.push_back({{x0, y1}, {gd.uv_min.x, gd.uv_max.y}, {r,g,b,a}});
            batch.push_back({{x0, y0}, {gd.uv_min.x, gd.uv_min.y}, {r,g,b,a}});
            batch.push_back({{x1, y0}, {gd.uv_max.x, gd.uv_min.y}, {r,g,b,a}});

            batch.push_back({{x0, y1}, {gd.uv_min.x, gd.uv_max.y}, {r,g,b,a}});
            batch.push_back({{x1, y0}, {gd.uv_max.x, gd.uv_min.y}, {r,g,b,a}});
            batch.push_back({{x1, y1}, {gd.uv_max.x, gd.uv_max.y}, {r,g,b,a}});

            x += (float)(gd.advance >> 6);
        }
    }

    float line_height()  const override { return font_line_height; }
    float space_width()  const override { return font_space_advance; }
    void  set_tab_width(int spaces) override { tab_width = spaces; }

    void on_resize(u32 width, u32 height) override {
        metalLayer.drawableSize = CGSizeMake(width, height);
    }

    void shutdown() override {
    	device = nil;
    	commandQueue = nil;
    }

    float32 get_text_width(const std::string& text, float32 size) override {
        float width = 0;
        for (char c : text) {
            if (glyphMap.count(c)) {
                // (advance >> 6) converts FreeType 26.6 fixed point to pixels
                width += (glyphMap[c].advance >> 6);
            }
        }
        // Scale width based on requested size vs atlas size (if atlas was 32px)
        return width * (size / 32.0f); 
    }
private:
	id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
    CAMetalLayer* metalLayer;
    id<MTLRenderPipelineState> pipelineState;
    id<MTLTexture> fontTexture;
    id<MTLBuffer> vertexBuffer;
    id<CAMetalDrawable> drawable;
    MTLRenderPassDescriptor* renderPass;
    
    std::map<char, GlyphData> glyphMap;
    std::vector<NativeVertex> batch;

    float font_line_height  = 0.0f;
    float font_space_advance = 0.0f;
    int   tab_width         = 4;
};

IRenderer* create_renderer(RenderBackend backend) {
    if (backend == RenderBackend::Metal) return new MetalRenderer();
    return nullptr;
}