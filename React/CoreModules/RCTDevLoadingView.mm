/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTDevLoadingView.h>

#import <QuartzCore/QuartzCore.h>

#import <FBReactNativeSpec/FBReactNativeSpec.h>
#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTDefines.h>
#import <React/RCTDevLoadingViewSetEnabled.h>
#import <React/RCTModalHostViewController.h>
#import <React/RCTUtils.h>

#import "CoreModulesPlugins.h"

using namespace facebook::react;

@interface RCTDevLoadingView () <NativeDevLoadingViewSpec>
@end

#if RCT_DEV | RCT_ENABLE_LOADING_VIEW

@implementation RCTDevLoadingView {
  UIWindow *_window;
  UILabel *_label;
  UILabel *_host;
  NSDate *_showDate;
  BOOL _hiding;
  dispatch_block_t _initialMessageBlock;
}

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

+ (void)setEnabled:(BOOL)enabled
{
  RCTDevLoadingViewSetEnabled(enabled);
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (void)setBridge:(RCTBridge *)bridge
{
  _bridge = bridge;

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(hide)
                                               name:RCTJavaScriptDidLoadNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(hide)
                                               name:RCTJavaScriptDidFailToLoadNotification
                                             object:nil];

  if (bridge.loading) {
    [self showWithURL:bridge.bundleURL];
  }
}

- (void)clearInitialMessageDelay
{
  if (self->_initialMessageBlock != nil) {
    dispatch_block_cancel(self->_initialMessageBlock);
    self->_initialMessageBlock = nil;
  }
}

- (void)showInitialMessageDelayed:(void (^)())initialMessage
{
  self->_initialMessageBlock = dispatch_block_create(static_cast<dispatch_block_flags_t>(0), initialMessage);

  // We delay the initial loading message to prevent flashing it
  // when loading progress starts quickly. To do that, we
  // schedule the message to be shown in a block, and cancel
  // the block later when the progress starts coming in.
  // If the progress beats this timer, this message is not shown.
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), self->_initialMessageBlock);
}

- (UIColor *)dimColor:(UIColor *)c
{
  // Given a color, return a slightly lighter or darker color for dim effect.
  CGFloat h, s, b, a;
  if ([c getHue:&h saturation:&s brightness:&b alpha:&a])
    return [UIColor colorWithHue:h saturation:s brightness:b < 0.5 ? b * 1.25 : b * 0.75 alpha:a];
  return nil;
}

- (NSString *)getTextForHost
{
  if (self->_bridge.bundleURL == nil || self->_bridge.bundleURL.fileURL) {
    return @"React Native";
  }

  return [NSString stringWithFormat:@"%@:%@", self->_bridge.bundleURL.host, self->_bridge.bundleURL.port];
}

- (void)showMessage:(NSString *)message color:(UIColor *)color backgroundColor:(UIColor *)backgroundColor
{
  if (!RCTDevLoadingViewGetEnabled() || self->_hiding) {
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    self->_showDate = [NSDate date];
    if (!self->_window && !RCTRunningInTestEnvironment()) {
      CGSize screenSize = [UIScreen mainScreen].bounds.size;

      if (@available(iOS 11.0, *)) {
        UIWindow *window = RCTSharedApplication().keyWindow;
        self->_window =
            [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenSize.width, window.safeAreaInsets.top + 52)];
        self->_label = [[UILabel alloc] initWithFrame:CGRectMake(0, window.safeAreaInsets.top, screenSize.width, 22)];
        self->_host =
            [[UILabel alloc] initWithFrame:CGRectMake(0, window.safeAreaInsets.top + 20, screenSize.width, 22)];
        self->_host.font = [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightRegular];
        self->_host.textAlignment = NSTextAlignmentCenter;

        [self->_window addSubview:self->_label];
        [self->_window addSubview:self->_host];

      } else {
        self->_window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenSize.width, 22)];
        self->_label = [[UILabel alloc] initWithFrame:self->_window.bounds];

        [self->_window addSubview:self->_label];
        // TODO: Add host to iOS < 11.0
      }

      self->_window.windowLevel = UIWindowLevelStatusBar + 1;
      // set a root VC so rotation is supported
      self->_window.rootViewController = [UIViewController new];

      self->_label.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular];
      self->_label.textAlignment = NSTextAlignmentCenter;
    }

    self->_label.text = message;
    self->_label.textColor = color;

    if (self->_host != nil) {
      self->_host.text = [self getTextForHost];
      self->_host.textColor = [self dimColor:color];
    }

    self->_window.backgroundColor = backgroundColor;
    self->_window.hidden = NO;

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && defined(__IPHONE_13_0) && \
    __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0
    if (@available(iOS 13.0, *)) {
      UIWindowScene *scene = (UIWindowScene *)RCTSharedApplication().connectedScenes.anyObject;
      self->_window.windowScene = scene;
    }
#endif
  });
}

RCT_EXPORT_METHOD(showMessage
                  : (NSString *)message withColor
                  : (NSNumber *__nonnull)color withBackgroundColor
                  : (NSNumber *__nonnull)backgroundColor)
{
  [self showMessage:message color:[RCTConvert UIColor:color] backgroundColor:[RCTConvert UIColor:backgroundColor]];
}

RCT_EXPORT_METHOD(hide)
{
  if (!RCTDevLoadingViewGetEnabled()) {
    return;
  }

  // Cancel the initial message block so it doesn't display later and get stuck.
  [self clearInitialMessageDelay];

  dispatch_async(dispatch_get_main_queue(), ^{
    self->_hiding = true;
    const NSTimeInterval MIN_PRESENTED_TIME = 0.5;
    NSTimeInterval presentedTime = [[NSDate date] timeIntervalSinceDate:self->_showDate];
    NSTimeInterval delay = MAX(0, MIN_PRESENTED_TIME - presentedTime);
    CGRect windowFrame = self->_window.frame;
    [UIView animateWithDuration:0.1
        delay:delay
        options:0
        animations:^{
          self->_window.frame = CGRectOffset(windowFrame, 0, -windowFrame.size.height);
        }
        completion:^(__unused BOOL finished) {
          self->_window.frame = windowFrame;
          self->_window.hidden = YES;
          self->_window = nil;
          self->_hiding = false;
        }];
  });
}

- (void)showWithURL:(NSURL *)URL
{
  UIColor *color;
  UIColor *backgroundColor;
  NSString *message;
  if (URL.fileURL) {
    // If dev mode is not enabled, we don't want to show this kind of notification.
#if !RCT_DEV
    return;
#endif
    color = [UIColor whiteColor];
    backgroundColor = [UIColor colorWithHue:105 saturation:0 brightness:.25 alpha:1];
    message = [NSString stringWithFormat:@"Connect to %@ to develop JavaScript.", RCT_PACKAGER_NAME];
    [self showMessage:message color:color backgroundColor:backgroundColor];
  } else {
    color = [UIColor whiteColor];
    backgroundColor = [UIColor colorWithHue:105 saturation:0 brightness:.25 alpha:1];
    message = [NSString stringWithFormat:@"Loading from %@\u2026", RCT_PACKAGER_NAME];

    [self showInitialMessageDelayed:^{
      [self showMessage:message color:color backgroundColor:backgroundColor];
    }];
  }
}

- (void)updateProgress:(RCTLoadingProgress *)progress
{
  if (!progress) {
    return;
  }

  // Cancel the initial message block so it's not flashed before progress.
  [self clearInitialMessageDelay];

  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_window == nil) {
      // If we didn't show the initial message, then there's no banner window.
      // We need to create it here so that the progress is actually displayed.
      UIColor *color = [UIColor whiteColor];
      UIColor *backgroundColor = [UIColor colorWithHue:105 saturation:0 brightness:.25 alpha:1];
      [self showMessage:[progress description] color:color backgroundColor:backgroundColor];
    } else {
      // This is an optimization. Since the progress can come in quickly,
      // we want to do the minimum amount of work to update the UI,
      // which is to only update the label text.
      self->_label.text = [progress description];
    }
  });
}

- (std::shared_ptr<TurboModule>)getTurboModule:(const ObjCTurboModule::InitParams &)params
{
  return std::make_shared<NativeDevLoadingViewSpecJSI>(params);
}

@end

#else

@implementation RCTDevLoadingView

+ (NSString *)moduleName
{
  return nil;
}
+ (void)setEnabled:(BOOL)enabled
{
}
- (void)showMessage:(NSString *)message color:(UIColor *)color backgroundColor:(UIColor *)backgroundColor
{
}
- (void)showMessage:(NSString *)message withColor:(NSNumber *)color withBackgroundColor:(NSNumber *)backgroundColor
{
}
- (void)showWithURL:(NSURL *)URL
{
}
- (void)updateProgress:(RCTLoadingProgress *)progress
{
}
- (void)hide
{
}
- (std::shared_ptr<TurboModule>)getTurboModule:(const ObjCTurboModule::InitParams &)params
{
  return std::make_shared<NativeDevLoadingViewSpecJSI>(params);
}

@end

#endif

Class RCTDevLoadingViewCls(void)
{
  return RCTDevLoadingView.class;
}
