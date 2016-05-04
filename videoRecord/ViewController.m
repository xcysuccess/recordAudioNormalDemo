//
//  OSMOCameraViewController.m
//  DJITrackingDemo
//
//  Created by tomxiang on 4/19/16.
//  Copyright © 2016 DJI. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "MediaUtils.h"
#import <Photos/Photos.h>
#import <AssetsLibrary/ALAssetsLibrary.h>

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>
{
    AVCaptureSession *_captureSession;
    AVCaptureDevice *_captureDeviceBack;
    AVCaptureDeviceInput *_captureDeviceInputFront;
    AVCaptureDeviceInput *_captureDeviceInputBack;
    
    AVCaptureVideoDataOutput *_videoOutput;
    
    AVAssetWriter *_assetWriter;
    AVAssetWriterInput *_videoWriterInput;
    AVAssetWriterInputPixelBufferAdaptor *_videoWriterInputPixelBufferAdaptor;
    
    VideoRecordState _videoRecordState;
    
    CMTime _videoLastTimestamp;
    CMTime _timeOffset;

    AVCaptureAudioDataOutput *_audioOutput;
    AVAssetWriterInput *_audioWriterInput;
}

@property (nonatomic,strong ) AVCaptureDevice          *videoDevice;
@property (weak, nonatomic) IBOutlet UIButton *startRecordBtn;
@property (weak, nonatomic) IBOutlet UIButton *stopReordBtn;
@property (weak, nonatomic) IBOutlet UIButton *pauseRecordBtn;
@property (nonatomic,assign ) CGSize                   recordingSize;
@property (nonatomic,copy   ) NSString                 *movieFilePath;

- (IBAction)startRecordAction:(id)sender;
- (IBAction)stopRecordAction:(id)sender;
- (IBAction)pauseRecordAction:(id)sender;
@end

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.view.backgroundColor = [UIColor redColor];
    
    [self initData];
    [self _setupCaptureSession];
    return;
}

-(void) initData{
    _videoLastTimestamp = kCMTimeInvalid;
    _timeOffset = kCMTimeInvalid;
}

-(void) _setupCaptureSession {
    NSError *error = nil;
    
    // Create the session
    _captureSession = [[AVCaptureSession alloc] init];
    
    [_captureSession beginConfiguration];
    // Configure the session to produce lower resolution video frames, if your
    // processing algorithm can cope. We'll specify medium quality for the
    // chosen device.
#if CONFIG_DO_ENABLE_4K_CAPTURE
    _captureSession.sessionPreset = AVCaptureSessionPreset3840x2160;
#else
    _captureSession.sessionPreset = AVCaptureSessionPresetHigh;
#endif
    AVCaptureVideoPreviewLayer *captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    captureVideoPreviewLayer.frame = self.view.bounds;
    captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:captureVideoPreviewLayer];
    
    /**
     *  Video
     */
    self.videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice
                                                                             error:nil];
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [_captureSession addInput:videoInput];
    [_captureSession addOutput:_videoOutput];
    _videoOutput.videoSettings =
    [NSDictionary dictionaryWithObject:
     [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    
    dispatch_queue_t videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [_videoOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
    //    [self _setupVideoWriter];
    /**
     *  Audio
     */
    dispatch_queue_t audioDataOutputQueue = dispatch_queue_create("AudioVideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    AVCaptureDevice * audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    [_captureSession addInput:audioInput];
    [_captureSession addOutput:_audioOutput];
    [_audioOutput setSampleBufferDelegate:self queue:audioDataOutputQueue];
    //    [self _setupAudioWriter];
    
    [_captureSession commitConfiguration];
    [_captureSession startRunning];

    [self.view bringSubviewToFront:_startRecordBtn];
    [self.view bringSubviewToFront:_stopReordBtn];
    [self.view bringSubviewToFront:_pauseRecordBtn];
}

- (BOOL)isLandscape{
    if([[UIApplication sharedApplication] statusBarOrientation] == UIInterfaceOrientationLandscapeRight || [[UIApplication sharedApplication] statusBarOrientation] == UIInterfaceOrientationLandscapeLeft){
        return YES;
    }
    else{
        return NO;
    }
}

-(void) _setupVideoWriter{
    
    CGSize size = self.recordingSize;
    
    // Setup the movie file path
    NSString* movieFileName = [NSString stringWithFormat:@"Rec_%.4lf.mov", [[NSDate date] timeIntervalSince1970]];
    self.movieFilePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:movieFileName];
    unlink([_movieFilePath UTF8String]);
    NSURL *outputURL = [NSURL fileURLWithPath:_movieFilePath];
    
    NSError *error = nil;
    _assetWriter = [[AVAssetWriter alloc] initWithURL:outputURL
                                             fileType:AVFileTypeQuickTimeMovie
                                                error:&error];
    NSParameterAssert(_assetWriter);
    
    if(error){
        NSLog(@"error = %@", [error localizedDescription]);
    }
    
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecH264,AVVideoCodecKey,
                                   AVVideoScalingModeResizeAspectFill,AVVideoScalingModeKey,
                                   [NSNumber numberWithInt:size.width],AVVideoWidthKey,
                                   [NSNumber numberWithInt:size.height],AVVideoHeightKey,nil];
    
    _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    _videoWriterInput.expectsMediaDataInRealTime = YES;
    NSParameterAssert(_videoWriterInput);
    if ([_assetWriter canAddInput:_videoWriterInput]){
        [_assetWriter addInput:_videoWriterInput];
    }else{
        assert(0);
    }
    
}
-(void) _setupAudioWriter{
    NSError *error = nil;
    
    AudioChannelLayout acl;
    bzero(&acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    NSDictionary*  audioOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [ NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                                          [ NSNumber numberWithInt: 2 ], AVNumberOfChannelsKey,
                                          [ NSNumber numberWithFloat: 44100.0 ], AVSampleRateKey,
                                          [ NSData dataWithBytes: &acl length: sizeof( AudioChannelLayout ) ], AVChannelLayoutKey,
                                          [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                                          nil];
    
    _audioWriterInput = [AVAssetWriterInput
                         assetWriterInputWithMediaType:AVMediaTypeAudio
                         outputSettings:audioOutputSettings];
    
    _audioWriterInput.expectsMediaDataInRealTime = true;
    NSParameterAssert(_audioWriterInput);
    if([_assetWriter canAddInput:_audioWriterInput]){
        [_assetWriter addInput:_audioWriterInput];
    }
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)startRecordAction:(id)sender {
    [self _setupVideoWriter];
    [self _setupAudioWriter];
    
    if (_videoRecordState == VideoRecordStateUnkonw) {
        _videoRecordState = VideoRecordStateRecording;
    }else {
        _videoRecordState = VideoRecordStateResumeRecord;
    }
}

- (IBAction)stopRecordAction:(id)sender {
    _videoRecordState = VideoRecordStateUnkonw;
    _timeOffset = kCMTimeInvalid;
    
    [_videoWriterInput markAsFinished];
    [_audioWriterInput markAsFinished];
    
    // Wait for the video
    AVAssetWriterStatus status = _assetWriter.status;
    while (status == AVAssetWriterStatusUnknown) {
        NSLog(@"Waiting...");
        [NSThread sleepForTimeInterval:0.5f];
        status = _assetWriter.status;
    }
    
    [_assetWriter finishWritingWithCompletionHandler:^{
        NSLog(@"finishWritingWithCompletionHandler");
    }];
    
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:_movieFilePath error:nil];
    unsigned long long fileSize = [fileAttributes fileSize];
    NSLog(@"文件空间的大小为： 保存的   %lluld",fileSize);
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    [library writeVideoAtPathToSavedPhotosAlbum:[NSURL fileURLWithPath:_movieFilePath]
                                completionBlock:^(NSURL *assetURL, NSError *error) {
                                    if (error) {
                                        NSLog(@"Save video fail:%@",error);
                                    } else {
                                        NSLog(@"Save video succeed.");
                                        
                                    }
                                }];
//    [self _setupAudioWriter];
//    [self _setupVideoWriter];
}

- (IBAction)pauseRecordAction:(id)sender {

    _videoRecordState = VideoRecordStateInteruped;
}

-(void) captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    // Record Video and Audio
    if(captureOutput == _audioOutput){
        [self _renderAudioRecordOutput:captureOutput fromSampleBuffer:sampleBuffer];
        return;
    }
    
    // Get the size of the buffer
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    self.recordingSize = CGSizeMake(width, height);

    @autoreleasepool {
        if(captureOutput == _videoOutput){
            [self _renderVideoRecordOutput:captureOutput fromSampleBuffer:sampleBuffer];
        }
    }
}

-(void) _renderAudioRecordOutput:(AVCaptureOutput *)captureOutput fromSampleBuffer:(CMSampleBufferRef) sampleBuffer{
    if (_videoRecordState == VideoRecordStateRecording && [_videoWriterInput isReadyForMoreMediaData] && _assetWriter.status != AVAssetWriterStatusUnknown) {

        // adjust the sample buffer if there is a time offset
        CMSampleBufferRef bufferToWrite = NULL;
        if (CMTIME_IS_VALID(_timeOffset)) {
            bufferToWrite = [MediaUtils createOffsetSampleBufferWithSampleBuffer:sampleBuffer withTimeOffset:_timeOffset];
            if (!bufferToWrite) {
                NSLog(@"error subtracting the timeoffset from the sampleBuffer");
            }
        } else {
            bufferToWrite = sampleBuffer;
            CFRetain(bufferToWrite);
        }
        if( ![_audioWriterInput appendSampleBuffer:bufferToWrite] ){
            
            NSLog(@"Unable to write to video input");
        }else {
            NSLog(@"already write vidio");
        }
        if (bufferToWrite) {
            CFRelease(bufferToWrite);
        }
    }
}

-(void) _renderVideoRecordOutput:(AVCaptureOutput *)captureOutput fromSampleBuffer:(CMSampleBufferRef) sampleBuffer{
    CMTime currentSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    if( _videoRecordState == VideoRecordStateRecording && _assetWriter.status != AVAssetWriterStatusWriting  ){
        [_assetWriter startWriting];
        [_assetWriter startSessionAtSourceTime:currentSampleTime];
    }
    
    //如果是恢复录制，将后面的时间点接上,比如1-3，6－10，从3直接接入到6即可，重新设置buffer信息
    if (_videoRecordState == VideoRecordStateResumeRecord) {
        if (CMTIME_IS_VALID(currentSampleTime) && CMTIME_IS_VALID(_videoLastTimestamp)) {
            CMTime offset = CMTimeSubtract(currentSampleTime, _videoLastTimestamp);
            if (CMTIME_IS_INVALID(_timeOffset)) {
                _timeOffset = offset;
            }else {
                _timeOffset = CMTimeAdd(_timeOffset, offset);
            }
        }
        _videoRecordState = VideoRecordStateRecording;
    }
    
    //多一个VideoRecordStateInteruped状态，是因为_videoLastTimestamp只需要记录一次即可
    if (_videoRecordState == VideoRecordStateInteruped) {
        _videoLastTimestamp = currentSampleTime;
        _videoRecordState = VideoRecordStatePausing;
    }
    
    if ( _assetWriter.status > AVAssetWriterStatusWriting ){
        NSLog(@"Warning: writer status is %ld", (long)_assetWriter.status);
        if( _assetWriter.status == AVAssetWriterStatusFailed){
            NSLog(@"Error: %@", _assetWriter.error);
        }
        return;
    }
    
    if (_videoRecordState == VideoRecordStateRecording && [_videoWriterInput isReadyForMoreMediaData]){
        // adjust the sample buffer if there is a time offset
        CMSampleBufferRef bufferToWrite = NULL;
        if (CMTIME_IS_VALID(_timeOffset)) {
            bufferToWrite = [MediaUtils createOffsetSampleBufferWithSampleBuffer:sampleBuffer withTimeOffset:_timeOffset];
            if (!bufferToWrite) {
                NSLog(@"error subtracting the timeoffset from the sampleBuffer");
            }
        } else {
            bufferToWrite = sampleBuffer;
            CFRetain(bufferToWrite);
        }
        if( ![_videoWriterInput appendSampleBuffer:bufferToWrite] ){
            
            NSLog(@"Unable to write to video input");
        }else {
            NSLog(@"already write vidio");
        }
        if (bufferToWrite) {
            CFRelease(bufferToWrite);
        }
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    NSLog(@"%s",__FUNCTION__);
}

@end
