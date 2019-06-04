//
//  ViewController.m
//  ZhqVideoCapture
//
//  Created by 周焕强 on 2019/6/3.
//  Copyright © 2019 zhq. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "libyuv.h"
#import "aw_alloc.h"
@interface ViewController ()<AVCaptureAudioDataOutputSampleBufferDelegate,AVCaptureVideoDataOutputSampleBufferDelegate>


/********************公共*************/
//会话
@property (nonatomic, strong) AVCaptureSession *captureSession;

/********************音频相关**********/
//音频设备
@property (nonatomic, strong) AVCaptureDeviceInput *audioInputDevice;
//输出数据接收
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;

/********************视频相关**********/
//前后摄像头
@property (nonatomic, strong) AVCaptureDeviceInput *frontCamera;
@property (nonatomic, strong) AVCaptureDeviceInput *backCamera;
//输出数据接收
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
//预览层
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;

@property (nonatomic, strong) UIView *preView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self initInputDevice];
    [self initOutputDevice];
    [self createAVCaptureSession];
}

// 初始化输入设备
- (void)initInputDevice{
    //获得输入设备
    AVCaptureDevice *backCaptureDevice=[self getCameraDeviceWithPosition:AVCaptureDevicePositionBack];//取得后置摄像头
    AVCaptureDevice *frontCaptureDevice=[self getCameraDeviceWithPosition:AVCaptureDevicePositionFront];//取得前置摄像头
    
    //根据输入设备初始化设备输入对象，用于获得输入数据
    _backCamera = [[AVCaptureDeviceInput alloc]initWithDevice:backCaptureDevice error:nil];
    _frontCamera = [[AVCaptureDeviceInput alloc]initWithDevice:frontCaptureDevice error:nil];
    
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    self.audioInputDevice = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
}

// 初始化输出设备
- (void)initOutputDevice{
    //创建数据获取线程
    dispatch_queue_t captureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    //视频数据输出
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    //设置代理，需要当前类实现protocol：AVCaptureVideoDataOutputSampleBufferDelegate
    [self.videoDataOutput setSampleBufferDelegate:self queue:captureQueue];
    //抛弃过期帧，保证实时性
    [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    //设置输出格式为 yuv420
    [self.videoDataOutput setVideoSettings:@{
                                             (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
                                             }];
    
    //音频数据输出
    self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    //设置代理，需要当前类实现protocol：AVCaptureAudioDataOutputSampleBufferDelegate
    [self.audioDataOutput setSampleBufferDelegate:self queue:captureQueue];
}

// 创建AVCaptureSession
- (void)createAVCaptureSession{
    
    self.captureSession = [[AVCaptureSession alloc] init];
    
    // 改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.captureSession beginConfiguration];
    // 设置分辨率
    [self setVideoPreset];

    //将设备输入添加到会话中
    if ([self.captureSession canAddInput:self.backCamera]) {
        [self.captureSession addInput:self.backCamera];
    }
    
    if ([self.captureSession canAddInput:self.audioInputDevice]) {
        [self.captureSession addInput:self.audioInputDevice];
    }
    
    //将设备输出添加到会话中
    if ([self.captureSession canAddOutput:self.videoDataOutput]) {
        [self.captureSession addOutput:self.videoDataOutput];
    }
    
    if ([self.captureSession canAddOutput:self.audioDataOutput]) {
        [self.captureSession addOutput:self.audioDataOutput];
    }
    
    [self createPreviewLayer];
    
    //提交配置变更
    [self.captureSession commitConfiguration];
    
    [self startRunning];
    
}

- (void)createPreviewLayer{
    
    [self.view addSubview:self.preView];
    
    //创建视频预览层，用于实时展示摄像头状态
    _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc]initWithSession:self.captureSession];
    
    _captureVideoPreviewLayer.frame = self.view.bounds;
    _captureVideoPreviewLayer.videoGravity=AVLayerVideoGravityResizeAspectFill;//填充模式
    //将视频预览层添加到界面中
    [self.view.layer addSublayer:_captureVideoPreviewLayer];
}


#pragma mark - Control start/stop capture or change camera
- (void)startRunning{
    if (!self.captureSession.isRunning) {
        [self.captureSession startRunning];
    }
}
- (void)stop{
    if (self.captureSession.isRunning) {
        [self.captureSession stopRunning];
    }
    
}

/**设置分辨率**/
- (void)setVideoPreset{
    if ([self.captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080])  {
        self.captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
    }else if ([self.captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    }else{
        self.captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    }
    
}

/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
-(AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition )position{
    NSArray *cameras= [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *camera in cameras) {
        if ([camera position]==position) {
            return camera;
        }
    }
    return nil;
}

#pragma mark-输出代理
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    CVPixelBufferRef initialPixelBuffer= CMSampleBufferGetImageBuffer(sampleBuffer);
    if (initialPixelBuffer == NULL) {
        return;
    }
    // 获取最终的音视频数据
    CVPixelBufferRef newPixelBuffer = [self convertVideoSmapleBufferToBGRAData:sampleBuffer];
    
    // 将CVPixelBufferRef转换成CMSampleBufferRef
    [self pixelBufferToSampleBuffer:newPixelBuffer];
    NSLog(@"initialPixelBuffer%@,newPixelBuffer%@", initialPixelBuffer, newPixelBuffer);

    // 使用完newPixelBuffer记得释放，否则内存会会溢出
    CFRelease(newPixelBuffer);
}


//转化
-(CVPixelBufferRef)convertVideoSmapleBufferToBGRAData:(CMSampleBufferRef)videoSample{
    
    //CVPixelBufferRef是CVImageBufferRef的别名，两者操作几乎一致。
    //获取CMSampleBuffer的图像地址
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(videoSample);
  //VideoToolbox解码后的图像数据并不能直接给CPU访问，需先用CVPixelBufferLockBaseAddress()锁定地址才能从主存访问，否则调用CVPixelBufferGetBaseAddressOfPlane等函数则返回NULL或无效值。值得注意的是，CVPixelBufferLockBaseAddress自身的调用并不消耗多少性能，一般情况，锁定之后，往CVPixelBuffer拷贝内存才是相对耗时的操作，比如计算内存偏移。
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    //图像宽度（像素）
    size_t pixelWidth = CVPixelBufferGetWidth(pixelBuffer);
    //图像高度（像素）
    size_t pixelHeight = CVPixelBufferGetHeight(pixelBuffer);
    //获取CVImageBufferRef中的y数据
    uint8_t *y_frame = (unsigned char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    //获取CMVImageBufferRef中的uv数据
    uint8_t *uv_frame =(unsigned char *) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    
    
    // 创建一个空的32BGRA格式的CVPixelBufferRef
    NSDictionary *pixelAttributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVPixelBufferRef pixelBuffer1 = NULL;
    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                          pixelWidth,pixelHeight,kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)pixelAttributes,&pixelBuffer1);
    if (result != kCVReturnSuccess) {
        NSLog(@"Unable to create cvpixelbuffer %d", result);
        return NULL;
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    result = CVPixelBufferLockBaseAddress(pixelBuffer1, 0);
    if (result != kCVReturnSuccess) {
        CFRelease(pixelBuffer1);
        NSLog(@"Failed to lock base address: %d", result);
        return NULL;
    }
    
    // 得到新创建的CVPixelBufferRef中 rgb数据的首地址
    uint8_t *rgb_data = (uint8*)CVPixelBufferGetBaseAddress(pixelBuffer1);
    
    // 使用libyuv为rgb_data写入数据，将NV12转换为BGRA
    int ret = NV12ToARGB(y_frame, pixelWidth, uv_frame, pixelWidth, rgb_data, pixelWidth * 4, pixelWidth, pixelHeight);
    if (ret) {
        NSLog(@"Error converting NV12 VideoFrame to BGRA: %d", result);
        CFRelease(pixelBuffer1);
        return NULL;
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer1, 0);
    
    return pixelBuffer1;
}

// 将CVPixelBufferRef转换成CMSampleBufferRef

-(CMSampleBufferRef)pixelBufferToSampleBuffer:(CVPixelBufferRef)pixelBuffer
{
    
    CMSampleBufferRef sampleBuffer;
    CMTime frameTime = CMTimeMakeWithSeconds([[NSDate date] timeIntervalSince1970], 1000000000);
    CMSampleTimingInfo timing = {frameTime, frameTime, kCMTimeInvalid};
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
    
    OSStatus status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, videoInfo, &timing, &sampleBuffer);
    if (status != noErr) {
        NSLog(@"Failed to create sample buffer with error %zd.", status);
    }
    CVPixelBufferRelease(pixelBuffer);
    if(videoInfo)
        CFRelease(videoInfo);
    
    return sampleBuffer;
}



@end
