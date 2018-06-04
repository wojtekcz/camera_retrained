// Copyright 2015 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import "CameraExampleViewController.h"

#include <sys/time.h>

#include "tensorflow_utils.h"

// If you have your own model, modify this to the file name, and make sure
// you've added the file to your app resources too.
//static NSString* model_file_name = @"mmapped_graph";
//static NSString* model_file_type = @"pb";
// This controls whether we'll be loading a plain GraphDef proto, or a
// file created by the convert_graphdef_memmapped_format utility that wraps a
// GraphDef and parameter file that can be mapped into memory from file to
// reduce overall memory usage.
//const bool model_uses_memory_mapping = YES;
// If you have your own model, point this to the labels file.
//static NSString* labels_file_name = @"retrained_labels";
//static NSString* labels_file_type = @"txt";
// These dimensions need to match those the model was trained with.
//const int wanted_input_width = 299;
//const int wanted_input_height = 299;
//const int wanted_input_channels = 3;
//const float input_mean = 128.0f;
//const float input_std = 128.0f;
//const std::string input_layer_name = "Mul";
//const std::string output_layer_name = "final_result";

static const NSString *AVCaptureStillImageIsCapturingStillImageContext =
@"AVCaptureStillImageIsCapturingStillImageContext";

@interface CameraExampleViewController (InternalMethods)
- (void)setupAVCapture;
- (void)teardownAVCapture;
@end

@implementation CameraExampleViewController

- (void)setupAVCapture {
    NSError *error = nil;
    
    session = [AVCaptureSession new];
    if ([[UIDevice currentDevice] userInterfaceIdiom] ==
        UIUserInterfaceIdiomPhone)
        [session setSessionPreset:AVCaptureSessionPreset640x480];
    else
        [session setSessionPreset:AVCaptureSessionPresetPhoto];
    
    AVCaptureDevice *device =
    [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *deviceInput =
    [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    assert(error == nil);
    
    isUsingFrontFacingCamera = NO;
    if ([session canAddInput:deviceInput]) [session addInput:deviceInput];
    
    stillImageOutput = [AVCaptureStillImageOutput new];
    [stillImageOutput
     addObserver:self
     forKeyPath:@"capturingStillImage"
     options:NSKeyValueObservingOptionNew
     context:(void *)(AVCaptureStillImageIsCapturingStillImageContext)];
    if ([session canAddOutput:stillImageOutput])
        [session addOutput:stillImageOutput];
    
    videoDataOutput = [AVCaptureVideoDataOutput new];
    
    NSDictionary *rgbOutputSettings = [NSDictionary
                                       dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA]
                                       forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [videoDataOutput setVideoSettings:rgbOutputSettings];
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    videoDataOutputQueue =
    dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
    
    if ([session canAddOutput:videoDataOutput])
        [session addOutput:videoDataOutput];
    [[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
    
    previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    [previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    CALayer *rootLayer = [previewView layer];
    [rootLayer setMasksToBounds:YES];
    [previewLayer setFrame:[rootLayer bounds]];
    [rootLayer addSublayer:previewLayer];
    [session startRunning];
    
    if (error) {
        UIAlertView *alertView = [[UIAlertView alloc]
                                  initWithTitle:[NSString stringWithFormat:@"Failed with error %d",
                                                 (int)[error code]]
                                  message:[error localizedDescription]
                                  delegate:nil
                                  cancelButtonTitle:@"Dismiss"
                                  otherButtonTitles:nil];
        [alertView show];
        [self teardownAVCapture];
    }
}

- (void)teardownAVCapture {
    if (videoDataOutputQueue) videoDataOutputQueue = nil;
    [stillImageOutput removeObserver:self forKeyPath:@"isCapturingStillImage"];
    [previewLayer removeFromSuperlayer];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ((__bridge NSString *)context == AVCaptureStillImageIsCapturingStillImageContext) {
        BOOL isCapturingStillImage =
        [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
        
        if (isCapturingStillImage) {
            // do flash bulb like animation
            flashView = [[UIView alloc] initWithFrame:[previewView frame]];
            [flashView setBackgroundColor:[UIColor whiteColor]];
            [flashView setAlpha:0.f];
            [[[self view] window] addSubview:flashView];
            
            [UIView animateWithDuration:.4f
                             animations:^{
                                 [flashView setAlpha:1.f];
                             }];
        } else {
            [UIView animateWithDuration:.4f
                             animations:^{
                                 [flashView setAlpha:0.f];
                             }
                             completion:^(BOOL finished) {
                                 [flashView removeFromSuperview];
                                 flashView = nil;
                             }];
        }
    }
}

- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:
(UIDeviceOrientation)deviceOrientation {
    AVCaptureVideoOrientation result =
    (AVCaptureVideoOrientation)(deviceOrientation);
    if (deviceOrientation == UIDeviceOrientationLandscapeLeft)
        result = AVCaptureVideoOrientationLandscapeRight;
    else if (deviceOrientation == UIDeviceOrientationLandscapeRight)
        result = AVCaptureVideoOrientationLandscapeLeft;
    return result;
}

- (IBAction)takePicture:(id)sender {
    if ([session isRunning]) {
        [session stopRunning];
        [sender setTitle:@"Continue" forState:UIControlStateNormal];
        
        flashView = [[UIView alloc] initWithFrame:[previewView frame]];
        [flashView setBackgroundColor:[UIColor whiteColor]];
        [flashView setAlpha:0.f];
        [[[self view] window] addSubview:flashView];
        
        [UIView animateWithDuration:.2f
                         animations:^{
                             [flashView setAlpha:1.f];
                         }
                         completion:^(BOOL finished) {
                             [UIView animateWithDuration:.2f
                                              animations:^{
                                                  [flashView setAlpha:0.f];
                                              }
                                              completion:^(BOOL finished) {
                                                  [flashView removeFromSuperview];
                                                  flashView = nil;
                                              }];
                         }];
        
    } else {
        [session startRunning];
        [sender setTitle:@"Freeze Frame" forState:UIControlStateNormal];
    }
}

+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity
                          frameSize:(CGSize)frameSize
                       apertureSize:(CGSize)apertureSize {
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height =
            apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width =
            apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width =
            apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height =
            apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
    
    CGRect videoBox;
    videoBox.size = size;
    if (size.width < frameSize.width)
        videoBox.origin.x = (frameSize.width - size.width) / 2;
    else
        videoBox.origin.x = (size.width - frameSize.width) / 2;
    
    if (size.height < frameSize.height)
        videoBox.origin.y = (frameSize.height - size.height) / 2;
    else
        videoBox.origin.y = (size.height - frameSize.height) / 2;
    
    return videoBox;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self runCNNOnFrame:pixelBuffer];
}

- (void)runCNNOnFrame:(CVPixelBufferRef)pixelBuffer {
    assert(pixelBuffer != NULL);
    
    NSDate *startDate = [NSDate date];
    
    UIImage *img = [self imageFromPixelBuffer:pixelBuffer];
    NSArray *predictions = [self predictionFromImage:img];
//    NSLog(@"predictions = %@", predictions);
//    NSLog(@"classnames = %@", self.classNames);

    NSTimeInterval runTime = -[startDate timeIntervalSinceNow];

    NSMutableDictionary *newValues = [NSMutableDictionary dictionary];
    for (int index = 0; index < predictions.count; index += 1) {
        const float predictionValue = [(NSNumber *)[predictions objectAtIndex:index] floatValue];
        if (predictionValue > 0.05f) {
            NSString *labelObject = [self.classNames objectAtIndex:index];
            NSNumber *valueObject = [NSNumber numberWithFloat:predictionValue];
            [newValues setObject:valueObject forKey:labelObject];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self setPredictionValues:newValues smoothTransition:self.smoothTransitionSwitch.on];
        [self showRunTime:runTime];
    });
}

- (void)dealloc {
    [self teardownAVCapture];
}

// use front/back camera
- (IBAction)switchCameras:(id)sender {
    AVCaptureDevicePosition desiredPosition;
    if (isUsingFrontFacingCamera)
        desiredPosition = AVCaptureDevicePositionBack;
    else
        desiredPosition = AVCaptureDevicePositionFront;
    
    for (AVCaptureDevice *d in
         [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if ([d position] == desiredPosition) {
            [[previewLayer session] beginConfiguration];
            AVCaptureDeviceInput *input =
            [AVCaptureDeviceInput deviceInputWithDevice:d error:nil];
            for (AVCaptureInput *oldInput in [[previewLayer session] inputs]) {
                [[previewLayer session] removeInput:oldInput];
            }
            [[previewLayer session] addInput:input];
            [[previewLayer session] commitConfiguration];
            break;
        }
    }
    isUsingFrontFacingCamera = !isUsingFrontFacingCamera;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

// https://stackoverflow.com/questions/3838696/convert-uiimage-to-cvpixelbufferref
- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image
{
    NSDictionary *options = @{
                              (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
                              (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                              };
    
    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(image),
                                          CGImageGetHeight(image), kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    if (status!=kCVReturnSuccess) {
        NSLog(@"Operation failed");
    }
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(image),
                                                 CGImageGetHeight(image), 8, 4*CGImageGetWidth(image), rgbColorSpace,
                                                 kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    CGAffineTransform flipVertical = CGAffineTransformMake( 1, 0, 0, -1, 0, CGImageGetHeight(image) );
    CGContextConcatCTM(context, flipVertical);
    CGAffineTransform flipHorizontal = CGAffineTransformMake( -1.0, 0.0, 0.0, 1.0, CGImageGetWidth(image), 0.0 );
    CGContextConcatCTM(context, flipHorizontal);
    
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}

// https://stackoverflow.com/questions/8072208/how-to-turn-a-cvpixelbuffer-into-a-uiimage
- (UIImage *)imageFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [temporaryContext
                             createCGImage:ciImage
                             fromRect:CGRectMake(0, 0,
                                                 CVPixelBufferGetWidth(pixelBuffer),
                                                 CVPixelBufferGetHeight(pixelBuffer))];
    
    UIImage *uiImage = [UIImage imageWithCGImage:videoImage scale:1.0 orientation:UIImageOrientationLeft];
    CGImageRelease(videoImage);
    return uiImage;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    square = [UIImage imageNamed:@"squarePNG"];
    synth = [[AVSpeechSynthesizer alloc] init];
    labelLayers = [[NSMutableArray alloc] init];
    oldPredictionValues = [[NSMutableDictionary alloc] init];
    
    self.model = [[old_polish_cars_resnet50_95acc alloc] init];
    
    // TODO: test on simulator
//    UIImage *myImage = [UIImage imageNamed:@"Jelcz.043.89000116_ddd.jpg"];
//    NSArray *preds = [self predictionFromImage:myImage];
//    NSLog(@"%@", preds);
    
    // TODO: refactor
    //pull the content from the file into memory
    NSURL *path = [[NSBundle mainBundle] URLForResource:@"old_polish_cars_resnet50_95acc_classes.txt" withExtension:nil];
    NSData *data = [NSData dataWithContentsOfURL:path];
    //convert the bytes from the file into a string
    NSString *string = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
    
    //split the string around newline characters to create an array
    NSString* delimiter = @"\n";
    self.classNames = [string componentsSeparatedByString:delimiter];
    
    [self setupAVCapture];
    
    self.smoothTransitionSwitch.on = YES;
}

- (NSArray *)predictionFromImage:(UIImage *)myImage {
    CGSize size = CGSizeMake(224, 224);
    
    BOOL hasAlpha = false;
    CGFloat scale = 1.0;
    
    UIGraphicsBeginImageContextWithOptions(size, !hasAlpha, scale);
    [myImage drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CVPixelBufferRef pixelBuffer = [self pixelBufferFromCGImage:scaledImage.CGImage];
    
    NSError *err;
    old_polish_cars_resnet50_95accOutput *output;
    output = [self.model predictionFrom0:pixelBuffer error:&err];
    MLMultiArray *multiArray = output._442;
//    NSLog(@"multiArray = %@", multiArray);
    
    NSMutableArray *preds = [[NSMutableArray alloc] init];
    
    float sum = 0;

    for (int i=0; i<=9; i++) {
        float num = [multiArray objectAtIndexedSubscript:i].floatValue;
        num = exp(num);
        sum += num;
    }

    for (int i=0; i<=9; i++) {
        float num = [multiArray objectAtIndexedSubscript:i].floatValue;
        num = exp(num)/sum;
        [preds addObject:@(num)];
    }
    
    // TODO: free objects
    return preds.copy;
}

- (void)viewDidUnload {
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:
(UIInterfaceOrientation)interfaceOrientation {
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)setPredictionValues:(NSDictionary *)newValues
           smoothTransition:(BOOL)smoothTransition {

    float decayValue = 0.75f;
    float updateValue = 0.25f;
    float minimumThreshold = 0.01f;
    
    if (!smoothTransition) {
        decayValue = 0.0f;
        updateValue = 1.0f;
        minimumThreshold = 0.001f;
    }
    
    NSMutableDictionary *decayedPredictionValues =
    [[NSMutableDictionary alloc] init];
    for (NSString *label in oldPredictionValues) {
        NSNumber *oldPredictionValueObject =
        [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float decayedPredictionValue = (oldPredictionValue * decayValue);
        if (decayedPredictionValue > minimumThreshold) {
            NSNumber *decayedPredictionValueObject =
            [NSNumber numberWithFloat:decayedPredictionValue];
            [decayedPredictionValues setObject:decayedPredictionValueObject
                                        forKey:label];
        }
    }
    oldPredictionValues = decayedPredictionValues;
    
    for (NSString *label in newValues) {
        NSNumber *newPredictionValueObject = [newValues objectForKey:label];
        NSNumber *oldPredictionValueObject =
        [oldPredictionValues objectForKey:label];
        if (!oldPredictionValueObject) {
            oldPredictionValueObject = [NSNumber numberWithFloat:0.0f];
        }
        const float newPredictionValue = [newPredictionValueObject floatValue];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float updatedPredictionValue =
        (oldPredictionValue + (newPredictionValue * updateValue));
        NSNumber *updatedPredictionValueObject =
        [NSNumber numberWithFloat:updatedPredictionValue];
        [oldPredictionValues setObject:updatedPredictionValueObject forKey:label];
    }
    NSArray *candidateLabels = [NSMutableArray array];
    for (NSString *label in oldPredictionValues) {
        NSNumber *oldPredictionValueObject =
        [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        if (oldPredictionValue > 0.05f) {
            NSDictionary *entry = @{
                                    @"label" : label,
                                    @"value" : oldPredictionValueObject
                                    };
            candidateLabels = [candidateLabels arrayByAddingObject:entry];
        }
    }
    NSSortDescriptor *sort =
    [NSSortDescriptor sortDescriptorWithKey:@"value" ascending:NO];
    NSArray *sortedLabels = [candidateLabels
                             sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]];
    
    const float leftMargin = 10.0f;
    const float topMargin = 10.0f;
    
    const float valueWidth = 48.0f;
    const float valueHeight = 26.0f;
    
    const float labelWidth = 246.0f;
    const float labelHeight = 26.0f;
    
    const float labelMarginX = 5.0f;
    const float labelMarginY = 5.0f;
    
    [self removeAllLabelLayers];
    
    int labelCount = 0;
    for (NSDictionary *entry in sortedLabels) {
        NSString *label = [entry objectForKey:@"label"];
        NSNumber *valueObject = [entry objectForKey:@"value"];
        const float value = [valueObject floatValue];
        
        const float originY =
        (topMargin + ((labelHeight + labelMarginY) * labelCount));
        
        const int valuePercentage = (int)roundf(value * 100.0f);
        
        const float valueOriginX = leftMargin;
        NSString *valueText = [NSString stringWithFormat:@"%d%%", valuePercentage];
        
        [self addLabelLayerWithText:valueText
                            originX:valueOriginX
                            originY:originY
                              width:valueWidth
                             height:valueHeight
                          alignment:kCAAlignmentRight];
        
        const float labelOriginX = (leftMargin + valueWidth + labelMarginX);
        
        [self addLabelLayerWithText:[label capitalizedString]
                            originX:labelOriginX
                            originY:originY
                              width:labelWidth
                             height:labelHeight
                          alignment:kCAAlignmentLeft];
        
        if ((labelCount == 0) && (value > 0.5f)) {
            [self speak:[label capitalizedString]];
        }
        
        labelCount += 1;
        if (labelCount > 4) {
            break;
        }
    }
}

- (void)removeAllLabelLayers {
    for (CATextLayer *layer in labelLayers) {
        [layer removeFromSuperlayer];
    }
    [labelLayers removeAllObjects];
}

- (void)addLabelLayerWithText:(NSString *)text
                      originX:(float)originX
                      originY:(float)originY
                        width:(float)width
                       height:(float)height
                    alignment:(NSString *)alignment {
    NSString *const font = @"Menlo-Regular";
    const float fontSize = 20.0f;
    
    const float marginSizeX = 5.0f;
    const float marginSizeY = 2.0f;
    
    const CGRect backgroundBounds = CGRectMake(originX, originY, width, height);
    
    const CGRect textBounds =
    CGRectMake((originX + marginSizeX), (originY + marginSizeY),
               (width - (marginSizeX * 2)), (height - (marginSizeY * 2)));
    
    CATextLayer *background = [CATextLayer layer];
    [background setBackgroundColor:[UIColor blackColor].CGColor];
    [background setOpacity:0.5f];
    [background setFrame:backgroundBounds];
    background.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer:background];
    [labelLayers addObject:background];
    
    CATextLayer *layer = [CATextLayer layer];
    [layer setForegroundColor:[UIColor whiteColor].CGColor];
    [layer setFrame:textBounds];
    [layer setAlignmentMode:alignment];
    [layer setWrapped:YES];
    [layer setFont:(__bridge CFTypeRef)font];
    [layer setFontSize:fontSize];
    layer.contentsScale = [[UIScreen mainScreen] scale];
    [layer setString:text];
    
    [[self.view layer] addSublayer:layer];
    [labelLayers addObject:layer];
}

- (void)setPredictionText:(NSString *)text withDuration:(float)duration {
    if (duration > 0.0) {
        CABasicAnimation *colorAnimation =
        [CABasicAnimation animationWithKeyPath:@"foregroundColor"];
        colorAnimation.duration = duration;
        colorAnimation.fillMode = kCAFillModeForwards;
        colorAnimation.removedOnCompletion = NO;
        colorAnimation.fromValue = (id)[UIColor darkGrayColor].CGColor;
        colorAnimation.toValue = (id)[UIColor whiteColor].CGColor;
        colorAnimation.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [self.predictionTextLayer addAnimation:colorAnimation
                                        forKey:@"colorAnimation"];
    } else {
        self.predictionTextLayer.foregroundColor = [UIColor whiteColor].CGColor;
    }
    
    [self.predictionTextLayer removeFromSuperlayer];
    [[self.view layer] addSublayer:self.predictionTextLayer];
    [self.predictionTextLayer setString:text];
}

- (void)speak:(NSString *)words {
    if ([synth isSpeaking]) {
        return;
    }
    AVSpeechUtterance *utterance =
    [AVSpeechUtterance speechUtteranceWithString:words];
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"pl-PL"];
    utterance.rate = 0.75 * AVSpeechUtteranceDefaultSpeechRate;
    [synth speakUtterance:utterance];
}

- (void)showRunTime:(NSTimeInterval)runTime {
//    NSLog(@"runTime = %f", runTime);
    self.inferenceTimeLabel.text = [NSString stringWithFormat:@"Inference time: %.2f", runTime];
}


@end
