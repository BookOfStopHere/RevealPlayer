//
//  KxMovieGLView.m
//  kxmovie
//
//  Created by Kolyvan on 22.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import "KxMovieGLView.h"
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import "KxMovieDecoder.h"
#import "KxLogger.h"
#import <GLKit/GLKit.h>
#import <AVFoundation/AVFoundation.h>
//////////////////////////////////////////////////////////

//https://neevek.net/posts/2017/11/26/opengl-rotating-mapped-texture-in-a-rectangular-viewport.html

#pragma mark - shaders

#define STRINGIZE(x) #x
#define STRINGIZE2(x) STRINGIZE(x)
#define SHADER_STRING(text) @ STRINGIZE2(text)
#undef cos
#undef sin
#undef sqrt
NSString *const vertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 attribute vec2 texcoord;
 uniform mat4 modelViewProjectionMatrix;
 uniform highp float xrotation;
 uniform highp float ratio;// with : height
 uniform highp float scale;// with : height
 
 varying vec2 v_texcoord;
 
 void main()
 {
    //
    highp float xaspect = 1.0;//ratio >= 1.0 ? 1.0 : ratio ;
    highp float yaspect = 1.0;//ratio >= 1.0 ? ratio  : 1.0 ;
    highp float xscale =  scale;
    highp mat4 aspect_mat = mat4(
        vec4(xaspect, 0.0, 0.0, 0.0),
        vec4(0.0,yaspect, 0.0, 0.0),
        vec4(0.0,0.0, 1.0, 0.0),
        vec4(0.0,0.0, 0.0, 1.0));

    highp mat4 model_mat = mat4(
        vec4(xscale*cos(xrotation),  -xscale*sin(xrotation),0.0,0.0),
        vec4(xscale*sin(xrotation), xscale*cos(xrotation),0.0,0.0),
        vec4(0.0, 0.0,1.,0.0),
        vec4(0.,0.,0.,  1.0));

//    gl_Position = modelViewProjectionMatrix * model_mat * aspect_mat * position;//矩阵的顺序也很重要
    
   gl_Position = modelViewProjectionMatrix * position;
    v_texcoord = texcoord.xy;
    
    
//    highp float Rote = xrotation;
//    highp float sinNum = sin(Rote);
//    highp float cosNum = cos(Rote);
//    highp vec2 center = vec2(0.5, 0.5);
//    highp float scale = 0.7;
//    highp vec3 temp = vec3(texcoord.xy - center,1.0) * mat3(vec3(scale* (ratio < 1. ? ratio : 1.0),0.,0.),vec3(0.,scale*(ratio >= 1. ? 1./ratio : 1.0),0.),vec3(0.,0.,1.));
    
    
    
//    highp vec3 temp = vec3(texcoord.xy - center,1.0) * mat3(vec3(MIN(1.,1./scale * ratio),0.,0.),vec3(0.,MIN(1./scale * ratio,1.0),0.),vec3(0.,0.,1.));
//
//    highp vec2 uv = temp.xy;
//    uv = uv * mat2(vec2(cosNum,-sinNum),vec2(sinNum,cosNum)) + center;
//    v_texcoord = uv;
    
//    highp float mid = 0.5;
//    v_texcoord = vec2(
//      cos(xrotation) * (v_texcoord.x - mid) + sin(xrotation) * (v_texcoord.y - mid) + mid,
//      cos(xrotation) * (v_texcoord.y - mid) - sin(xrotation) * (v_texcoord.x - mid) + mid
//    );

 }
);


NSString *const rgbFragmentShaderString = SHADER_STRING
(
 varying highp vec2 v_texcoord;
 uniform sampler2D s_texture;
 uniform highp float rotation;
 void main()
 {
    
    // 旋转变换
     gl_FragColor = texture2D(s_texture, v_texcoord);
 }
);

NSString *const yuvFragmentShaderString = SHADER_STRING
(
 varying highp vec2 v_texcoord;
 uniform sampler2D s_texture_y;
 uniform sampler2D s_texture_u;
 uniform sampler2D s_texture_v;
 uniform highp float rotation;

 void main()
 {
     highp float mid = 0.5;
     highp vec2 fuck = vec2(cos(rotation) * (v_texcoord.x - mid) + sin(rotation) * (v_texcoord.y - mid) + mid, cos(rotation) * (v_texcoord.y - mid) - sin(rotation) * (v_texcoord.x - mid) + mid);

     highp float y = texture2D(s_texture_y, v_texcoord).r;
     highp float u = texture2D(s_texture_u, v_texcoord).r - 0.5;
     highp float v = texture2D(s_texture_v, v_texcoord).r - 0.5;
     
     highp float r = y +             1.402 * v;
     highp float g = y - 0.344 * u - 0.714 * v;
     highp float b = y + 1.772 * u;
     
     gl_FragColor = vec4(r,g,b,1.0);
 }
);

static BOOL validateProgram(GLuint prog)
{
	GLint status;
	
    glValidateProgram(prog);
    
#ifdef DEBUG
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        LoggerVideo(1, @"Program validate log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == GL_FALSE) {
		LoggerVideo(0, @"Failed to validate program %d", prog);
        return NO;
    }
	
	return YES;
}

static GLuint compileShader(GLenum type, NSString *shaderString)
{
	GLint status;
	const GLchar *sources = (GLchar *)shaderString.UTF8String;
	
    GLuint shader = glCreateShader(type);
    if (shader == 0 || shader == GL_INVALID_ENUM) {
        LoggerVideo(0, @"Failed to create shader %d", type);
        return 0;
    }
    
    glShaderSource(shader, 1, &sources, NULL);
    glCompileShader(shader);
	
#ifdef DEBUG
	GLint logLength;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(shader, logLength, &logLength, log);
        LoggerVideo(1, @"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status == GL_FALSE) {
        glDeleteShader(shader);
		LoggerVideo(0, @"Failed to compile shader:\n");
        return 0;
    }
    
	return shader;
}

static void mat4f_LoadOrtho(float left, float right, float bottom, float top, float near, float far, float* mout)
{
	float r_l = right - left;
	float t_b = top - bottom;
	float f_n = far - near;
	float tx = - (right + left) / (right - left);
	float ty = - (top + bottom) / (top - bottom);
	float tz = - (far + near) / (far - near);
    float scale = 2.0;
	mout[0] = scale / r_l;
	mout[1] = 0.0f;
	mout[2] = 0.0f;
	mout[3] = 0.0f;
	
	mout[4] = 0.0f;
	mout[5] = scale / t_b;
	mout[6] = 0.0f;
	mout[7] = 0.0f;
	
	mout[8] = 0.0f;
	mout[9] = 0.0f;
	mout[10] = -scale / f_n;
	mout[11] = 0.0f;
	
	mout[12] = tx;
	mout[13] = ty;
	mout[14] = tz;
	mout[15] = 1.0f;
}

//////////////////////////////////////////////////////////

#pragma mark - frame renderers

@protocol KxMovieGLRenderer
- (BOOL) isValid;
- (NSString *) fragmentShader;
- (void) resolveUniforms: (GLuint) program;
- (void) setFrame: (KxVideoFrame *) frame;
- (BOOL) prepareRender;

@optional
@property (nonatomic, assign) float rotation;

@end

@interface KxMovieGLRenderer_RGB : NSObject<KxMovieGLRenderer> {
    
    GLint _uniformSampler;
    GLuint _texture;
}
@end

@implementation KxMovieGLRenderer_RGB

- (BOOL) isValid
{
    return (_texture != 0);
}

- (NSString *) fragmentShader
{
    return rgbFragmentShaderString;
}

- (void) resolveUniforms: (GLuint) program
{
    _uniformSampler = glGetUniformLocation(program, "s_texture");
}

- (void) setFrame: (KxVideoFrame *) frame
{
    KxVideoFrameRGB *rgbFrame = (KxVideoFrameRGB *)frame;
   
    assert(rgbFrame.rgb.length == rgbFrame.width * rgbFrame.height * 3);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    if (0 == _texture)
        glGenTextures(1, &_texture);
    
    glBindTexture(GL_TEXTURE_2D, _texture);
    
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGB,
                 frame.width,
                 frame.height,
                 0,
                 GL_RGB,
                 GL_UNSIGNED_BYTE,
                 rgbFrame.rgb.bytes);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

- (BOOL) prepareRender
{
    if (_texture == 0)
        return NO;
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _texture);
    glUniform1i(_uniformSampler, 0);
    
    return YES;
}

- (void) dealloc
{
    if (_texture) {
        glDeleteTextures(1, &_texture);
        _texture = 0;
    }
}

@end

@interface KxMovieGLRenderer_YUV : NSObject<KxMovieGLRenderer> {
    
    GLint _uniformSamplers[3];
    GLuint _textures[3];
    GLint _rotateUniform;
}
@property (nonatomic, assign) float rotation;
@end

@implementation KxMovieGLRenderer_YUV

- (BOOL) isValid
{
    return (_textures[0] != 0);
}

- (NSString *) fragmentShader
{
    return yuvFragmentShaderString;
}

- (void) resolveUniforms: (GLuint) program
{
    _uniformSamplers[0] = glGetUniformLocation(program, "s_texture_y");
    _uniformSamplers[1] = glGetUniformLocation(program, "s_texture_u");
    _uniformSamplers[2] = glGetUniformLocation(program, "s_texture_v");
    _rotateUniform = glGetUniformLocation(program, "rotation");
}

- (void) setFrame: (KxVideoFrame *) frame
{
    KxVideoFrameYUV *yuvFrame = (KxVideoFrameYUV *)frame;
    
    assert(yuvFrame.luma.length == yuvFrame.width * yuvFrame.height);
    assert(yuvFrame.chromaB.length == (yuvFrame.width * yuvFrame.height) / 4);
    assert(yuvFrame.chromaR.length == (yuvFrame.width * yuvFrame.height) / 4);

    const NSUInteger frameWidth = frame.width;
    const NSUInteger frameHeight = frame.height;    
    
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
//    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    if (0 == _textures[0])
        glGenTextures(3, _textures);

    const UInt8 *pixels[3] = { yuvFrame.luma.bytes, yuvFrame.chromaB.bytes, yuvFrame.chromaR.bytes };
    const NSUInteger widths[3]  = { frameWidth, frameWidth / 2, frameWidth / 2 };
    const NSUInteger heights[3] = { frameHeight, frameHeight / 2, frameHeight / 2 };
    
    for (int i = 0; i < 3; ++i) {
        
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_LUMINANCE,
                     widths[i],
                     heights[i],
                     0,
                     GL_LUMINANCE,
                     GL_UNSIGNED_BYTE,
                     pixels[i]);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }     
}

- (BOOL) prepareRender
{
    if (_textures[0] == 0)
        return NO;
    
    for (int i = 0; i < 3; ++i) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        glUniform1i(_uniformSamplers[i], i);
    }
    
    return YES;
}

- (void)setRotation:(float)rotation
{
    glUniform1f(_rotateUniform, rotation);
}

- (void) dealloc
{
    if (_textures[0])
        glDeleteTextures(3, _textures);
    if(_rotateUniform)
    glDeleteTextures(1,&_rotateUniform);
    
}

@end

//////////////////////////////////////////////////////////

#pragma mark - gl view

enum {
	ATTRIBUTE_VERTEX,
   	ATTRIBUTE_TEXCOORD,
};

@implementation KxMovieGLView {
    
    KxMovieDecoder  *_decoder;
    EAGLContext     *_context;
    GLuint          _framebuffer;
    GLuint          _renderbuffer;
    GLint           _backingWidth;
    GLint           _backingHeight;
    GLuint          _program;
    GLint           _uniformMatrix;
    GLint           _rotateUniform;
    GLint           _ratioUniform;
    GLint           _scaleUniform;
    GLfloat         _vertices[8];
    
    id<KxMovieGLRenderer> _renderer;
    CADisplayLink *_displayLink;
    double _rotation;
}

+ (Class) layerClass
{
	return [CAEAGLLayer class];
}

- (void)stop
{
    [self stopDeviceMotion];
    _displayLink.paused = YES;
    [_displayLink invalidate];
}

- (void)stopDeviceMotion
{
    [self.motionManager stopDeviceMotionUpdates];
    self.motionManager = nil;
}

- (void)startDeviceMotion {

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateDeviceMotion)];
    
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    _displayLink.paused = NO;
    // 2.1 Create a CMMotionManager instance and store it in the property "motionManager"
    self.motionManager = [[CMMotionManager alloc] init];
    // 2.1 Set the motion update interval to 1/60
    self.motionManager.deviceMotionUpdateInterval = 1.0 / 60.0;
    // 2.1 Start updating the motion using the reference frame CMAttitudeReferenceFrameXArbitraryCorrectedZVertical
//    [self.motionManager startDeviceMotionUpdates];
    [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical];
    _rotation = 0;
    return;
    
    
//    [self.motionManager startGyroUpdatesToQueue:[NSOperationQueue currentQueue] withHandler:^(CMGyroData *gyroData, NSError *error) {
//        NSLog([NSString stringWithFormat:@"旋转角度:X:%.3f,Y:%.3f,X:%.3f",gyroData.rotationRate.x,gyroData.rotationRate.y,gyroData.rotationRate.z]);
//        
//        glUniform1f(_rotateUniform, gyroData.rotationRate.z);
//     }];
}

-(void)updateDeviceMotion
{
    // 2.2 Get the deviceMotion from motionManager
    CMDeviceMotion *deviceMotion = self.motionManager.deviceMotion;
    
    // 2.2 Return if the returned CMDeviceMotion object is nil
    if(deviceMotion == nil)
    {
        return;
    }
    
    float vWdith = self.bounds.size.height;//_decoder.frameWidth;
    float vHeight = self.bounds.size.width ;//_decoder.frameHeight;
    
    double rotation = deviceMotion.attitude.yaw;
    
    if(rotation <= 0)
    {
        rotation = -rotation;
    }
    else
    {
        rotation = M_PI*2 - rotation;
    }
//   rotation = M_PI - atan2(deviceMotion.gravity.x, deviceMotion.gravity.y) ;
    float scale = MAX(_decoder.frameHeight/self.bounds.size.height,_decoder.frameWidth/self.bounds.size.width);

    double deltaQ = atan2(vHeight,vWdith);
    float nH = sin(deltaQ + rotation) * sqrt(vHeight * vHeight + vWdith * vWdith);
    float nW = nH * vWdith/vHeight;
    scale = nH/vHeight;
    
    //一开始是个角度
    //
    //1. 0-90
    //2. 90 -180
    //3. 180 - 270
    // 4. 270 - 360
    if(rotation >=0 && rotation <= M_PI_2)
    {
        nH = sin(deltaQ + rotation) * sqrt(vHeight * vHeight + vWdith * vWdith);
        nW = nH * vWdith/vHeight;
        scale = nH/vHeight;
    }
    else if(rotation >M_PI_2 && rotation <= M_PI)
    {
        nH = sin(-deltaQ + rotation) * sqrt(vHeight * vHeight + vWdith * vWdith);
        nW = nH * vWdith/vHeight;
        scale = nH/vHeight;
    }
    else if(rotation >M_PI && rotation <= M_PI*1.5)
    {
        nH = sin(deltaQ + rotation - M_PI) * sqrt(vHeight * vHeight + vWdith * vWdith);
        nW = nH * vWdith/vHeight;
        scale = nH/vHeight;
    }
    else if(rotation >M_PI*1.5 && rotation <= M_PI*2)
    {
        nH = sin(-deltaQ + rotation - M_PI) * sqrt(vHeight * vHeight + vWdith * vWdith);
        nW = nH * vWdith/vHeight;
        scale = nH/vHeight;
    }
    self.transform = CGAffineTransformConcat( CGAffineTransformMakeRotation(-rotation), CGAffineTransformMakeScale(scale,scale));
}

- (void)pause
{
    _displayLink.paused = YES;
}

- (void)play
{
    _displayLink.paused = NO;
}


- (id) initWithFrame:(CGRect)frame
             decoder: (KxMovieDecoder *) decoder
{
    self = [super initWithFrame:frame];
    if (self) {
        
        _decoder = decoder;
        
        if ([decoder setupVideoFrameFormat:KxVideoFrameFormatYUV]) {
            
            _renderer = [[KxMovieGLRenderer_YUV alloc] init];
            LoggerVideo(1, @"OK use YUV GL renderer");
            
        } else {
            
            _renderer = [[KxMovieGLRenderer_RGB alloc] init];
            LoggerVideo(1, @"OK use RGB GL renderer");
        }
                
        CAEAGLLayer *eaglLayer = (CAEAGLLayer*) self.layer;
        eaglLayer.opaque = YES;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                        nil];
        
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if (!_context ||
            ![EAGLContext setCurrentContext:_context]) {
            
            LoggerVideo(0, @"failed to setup EAGLContext");
            self = nil;
            return nil;
        }
        
        glGenFramebuffers(1, &_framebuffer);
        glGenRenderbuffers(1, &_renderbuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
        [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderbuffer);
        
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (status != GL_FRAMEBUFFER_COMPLETE) {
            
            LoggerVideo(0, @"failed to make complete framebuffer object %x", status);
            self = nil;
            return nil;
        }
        
        GLenum glError = glGetError();
        if (GL_NO_ERROR != glError) {
            
            LoggerVideo(0, @"failed to setup GL %x", glError);
            self = nil;
            return nil;
        }
                
        if (![self loadShaders]) {
            
            self = nil;
            return nil;
        }
        
        _vertices[0] = -1.0f;  // x0
        _vertices[1] = -1.0f;  // y0
        _vertices[2] =  1.0f;  // ..
        _vertices[3] = -1.0f;
        _vertices[4] = -1.0f;
        _vertices[5] =  1.0f;
        _vertices[6] =  1.0f;  // x3
        _vertices[7] =  1.0f;  // y3
        
        LoggerVideo(1, @"OK setup GL");
        [self startDeviceMotion];
    }
    
    return self;
}

- (void)dealloc
{
    _renderer = nil;

    if (_framebuffer) {
        glDeleteFramebuffers(1, &_framebuffer);
        _framebuffer = 0;
    }
    
    if (_renderbuffer) {
        glDeleteRenderbuffers(1, &_renderbuffer);
        _renderbuffer = 0;
    }
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
    
    if ([EAGLContext currentContext] == _context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    _context = nil;
}

- (void)layoutSubviews
{
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
	
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
	if (status != GL_FRAMEBUFFER_COMPLETE) {
		
        LoggerVideo(0, @"failed to make complete framebuffer object %x", status);
        
	} else {
        
        LoggerVideo(1, @"OK setup GL framebuffer %d:%d", _backingWidth, _backingHeight);
    }
    
    [self updateVertices];
    [self render: nil];
}

- (void)setContentMode:(UIViewContentMode)contentMode
{
    [super setContentMode:contentMode];
    [self updateVertices];
    if (_renderer.isValid)
        [self render:nil];
}

- (BOOL)loadShaders
{
    BOOL result = NO;
    GLuint vertShader = 0, fragShader = 0;
    
	_program = glCreateProgram();
	
    vertShader = compileShader(GL_VERTEX_SHADER, vertexShaderString);
	if (!vertShader)
        goto exit;
    
	fragShader = compileShader(GL_FRAGMENT_SHADER, _renderer.fragmentShader);
    if (!fragShader)
        goto exit;
    
	glAttachShader(_program, vertShader);
	glAttachShader(_program, fragShader);
	glBindAttribLocation(_program, ATTRIBUTE_VERTEX, "position");
    glBindAttribLocation(_program, ATTRIBUTE_TEXCOORD, "texcoord");
	
	glLinkProgram(_program);
    
    GLint status;
    glGetProgramiv(_program, GL_LINK_STATUS, &status);
    if (status == GL_FALSE) {
		LoggerVideo(0, @"Failed to link program %d", _program);
        goto exit;
    }
    
    result = validateProgram(_program);
        
    _uniformMatrix = glGetUniformLocation(_program, "modelViewProjectionMatrix");
    _rotateUniform = glGetUniformLocation(_program, "xrotation");
    _ratioUniform = glGetUniformLocation(_program, "ratio");
    _scaleUniform = glGetUniformLocation(_program, "scale");
    [_renderer resolveUniforms:_program];
	
exit:
    
    if (vertShader)
        glDeleteShader(vertShader);
    if (fragShader)
        glDeleteShader(fragShader);
    
    if (result) {
        
        LoggerVideo(1, @"OK setup GL programm");
        
    } else {
        
        glDeleteProgram(_program);
        _program = 0;
    }
    
    return result;
}


void rotateFuck(float *fuck, float xyrotation)
{
    float mid = 0;
    float x  = cos(xyrotation) * (fuck[0] - mid) + sin(xyrotation) * (fuck[1] - mid) + mid;
    float y  = cos(xyrotation) * (fuck[1] - mid) - sin(xyrotation) * (fuck[0] - mid) + mid;
    
    fuck[0] = x;
    fuck[1] = y;
}

- (void)updateVertices
{
    const BOOL fit      =  (self.contentMode == UIViewContentModeScaleAspectFit);
    const float width   = _decoder.frameWidth;
    const float height  = _decoder.frameHeight;
    const float dH      = (float)_backingHeight / height;
    const float dW      = (float)_backingWidth	  / width;
    const float dd      = fit ? MIN(dH, dW) : MAX(dH, dW);
    const float h       = (height * dd / (float)_backingHeight);
    const float w       = (width  * dd / (float)_backingWidth );

    _vertices[0] = - w;
    _vertices[1] = - h ;
    _vertices[2] =   w ;
    _vertices[3] = - h ;
    _vertices[4] = - w ;
    _vertices[5] =   h ;
    _vertices[6] =   w ;
    _vertices[7] =   h ;
    //宽高 填充由顶点 定义的 模具啊
}


void rotatePoint(float *points, float xrotation)
{

    CGPoint oriPoint = CGPointMake(points[0], points[1]);
    CGAffineTransform tranform =  CGAffineTransformMakeTranslation(-0.5, -0.5);
    CGPoint transPoint = CGPointApplyAffineTransform(oriPoint,tranform);
    
    transPoint = CGPointApplyAffineTransform(transPoint,CGAffineTransformMakeScale(0.5625*0.7, 0.7));
    transPoint = CGPointApplyAffineTransform(transPoint,CGAffineTransformMakeRotation(xrotation));
    
    transPoint = CGPointApplyAffineTransform(transPoint,CGAffineTransformMakeTranslation(0.5, 0.5));
    points[0] = transPoint.x;
    
    points[1] = transPoint.y;
  
}

typedef struct Quaternion
{
    double w, x, y, z;
}Quaternion;

Quaternion ToQuaternion(double yaw, double pitch, double roll) // yaw (Z), pitch (Y), roll (X)
{
    // Abbreviations for the various angular functions
    double cy = cos(yaw * 0.5);
    double sy = sin(yaw * 0.5);
    double cp = cos(pitch * 0.5);
    double sp = sin(pitch * 0.5);
    double cr = cos(roll * 0.5);
    double sr = sin(roll * 0.5);

    Quaternion q;
    q.w = cy * cp * cr + sy * sp * sr;
    q.x = cy * cp * sr - sy * sp * cr;
    q.y = sy * cp * sr + cy * sp * cr;
    q.z = sy * cp * cr - cy * sp * sr;

    return q;
}

typedef struct EulerAngles
{
    double roll, pitch, yaw;
}EulerAngles;

EulerAngles ToEulerAngles(Quaternion q)
{
    EulerAngles angles;

    // roll (x-axis rotation)
    double sinr_cosp = 2.0 * (q.w * q.x + q.y * q.z);
    double cosr_cosp = 1.0 - 2.0 * (q.x * q.x + q.y * q.y);
    angles.roll = atan2(sinr_cosp, cosr_cosp);

    // pitch (y-axis rotation)
    double sinp = +2.0 * (q.w * q.y - q.z * q.x);
    if (fabs(sinp) >= 1)
        angles.pitch = copysign(M_PI / 2, sinp); // use 90 degrees if out of range
    else
        angles.pitch = asin(sinp);

    // yaw (z-axis rotation)
    double siny_cosp = 2.0 * (q.w * q.z + q.x * q.y);
    double cosy_cosp = 1.0 - 2.0 * (q.y * q.y + q.z * q.z);
    angles.yaw = atan2(siny_cosp, cosy_cosp);

    return angles;
}

- (void)render: (KxVideoFrame *) frame
{
    // 纹理坐标 - 顶点坐标 一一对应
    // 更改显示的形状（平铺 拉伸 三角形等） 可以更改顶点坐标
    // 简单旋转 可以更改投影矩阵
    // 只显示纹理图一部分内容（放大 裁剪等）， 可以更改纹理坐标
    // 放缩 也可以 投影矩阵 模型->观察->投影
    static const GLfloat texCoords[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
    };
    
//   GLfloat newtexCoords[] = {
//        0.3f, 0.7,
//        0.7, 0.7,
//        0.3f, 0.3f,
//        0.7, 0.3f,
//    };

    
       GLfloat newtexCoords[] = {
            0.0f, 1.0f,
            1.0f, 1.0f,
            0.0f, 0.0f,
            1.0f, 0.0f,
        };
//   GLfloat newtexCoords[] = {
//
//       0.0f, 0.5f,//左上角
//       1.0f/2, 0.5f,//右上角
//       0.0f, 0.0f,//左下角
//       .5f, 0.0f,//右下角
//    };
    
    
    // 对于iphone8 保持最好的屏幕分辨率 1334x750 可以任意旋转的最小分辨率方图 1386x 1386
    
//    float alpha = 2160.0/3840.0;
//
//    float w_r = 750.* 1.5/2160.0;
//    float h_r = 1334.0 * 1.5/3840.0;
//
//    GLfloat newtexCoords[] = {
//         (1. - w_r)/2, (1. - h_r)/2 + h_r,
//        (1. - w_r)/2 + w_r, (1. - h_r)/2 + h_r,
//         (1. - w_r)/2, (1. - h_r)/2,
//         (1. - w_r)/2 + w_r, (1. - h_r)/2,
//     };

    // 这个得旋转
	
    [EAGLContext setCurrentContext:_context];
    
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glViewport(0, 0, _backingWidth, _backingHeight);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
	glUseProgram(_program);
        
    if (frame) {
        [_renderer setFrame:frame];        
    }
    
    
    if ([_renderer prepareRender]) {
        
        GLfloat modelviewProj[16];
        
        // 注意是高度比上宽度
        float aspect_ratio =   1.0;
//        _decoder.frameWidth/(_decoder.frameHeight + 0.0);
        if(aspect_ratio <= 1.) aspect_ratio = 1./aspect_ratio;
        
        mat4f_LoadOrtho(-1.0f, 1.0f, -aspect_ratio, aspect_ratio, -1.0f, 1.0f, modelviewProj);
        
        //这个也得更改
        // 投影矩阵
        
        GLKMatrix4 modelViewMatrix = GLKMatrix4MakeWithArray(modelviewProj);
        float ss =  sqrt(1 + pow(aspect_ratio, 2)) * aspect_ratio;
        glUniform1f(_scaleUniform, ss);
        glUniform1f(_ratioUniform, 1./aspect_ratio);
        
        glUniformMatrix4fv(_uniformMatrix, 1, GL_FALSE, modelViewMatrix.m);
        
        glVertexAttribPointer(ATTRIBUTE_VERTEX, 2, GL_FLOAT, 0, 0, _vertices);
        glEnableVertexAttribArray(ATTRIBUTE_VERTEX);
        glVertexAttribPointer(ATTRIBUTE_TEXCOORD, 2, GL_FLOAT, 0, 0, newtexCoords);
        glEnableVertexAttribArray(ATTRIBUTE_TEXCOORD);
        
    #if 0
        if (!validateProgram(_program))
        {
            LoggerVideo(0, @"Failed to validate program");
            return;
        }
    #endif
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);        
    }
    
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

@end
