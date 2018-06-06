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

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "old_polish_cars_resnet50_95acc.h"

#include <memory>

@interface CameraExampleViewController
    : UIViewController<UIGestureRecognizerDelegate,
                       AVCaptureVideoDataOutputSampleBufferDelegate> {
  IBOutlet UIView *previewView;
  IBOutlet UISegmentedControl *camerasControl;
  AVCaptureVideoPreviewLayer *previewLayer;
  AVCaptureVideoDataOutput *videoDataOutput;
  dispatch_queue_t videoDataOutputQueue;
  AVCaptureStillImageOutput *stillImageOutput;
  UIView *flashView;
  UIImage *square;
  BOOL isUsingFrontFacingCamera;
  AVSpeechSynthesizer *synth;
  NSMutableDictionary *oldPredictionValues;
  NSMutableArray *labelLayers;
  AVCaptureSession *session;
}
@property(retain, nonatomic) CATextLayer *predictionTextLayer;

- (IBAction)takePicture:(id)sender;
- (IBAction)switchCameras:(id)sender;

@property (weak, nonatomic) IBOutlet UISwitch *smoothTransitionSwitch;
@property (weak, nonatomic) IBOutlet UILabel *inferenceTimeLabel;

@property (strong, nonatomic) old_polish_cars_resnet50_95acc *model;
@property (strong, nonatomic) NSArray<NSString *> *classNames;


- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image;
- (NSArray *)predictionFromImage:(UIImage *)myImage;
- (UIImage *)imageFromPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end
