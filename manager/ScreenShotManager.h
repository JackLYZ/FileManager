//
//  ScreenShotManager.h
//  nezha
//
//  Created by LijiaChai on 16/5/31.
//  Copyright © 2016年 biyao. All rights reserved.
//

#import <Foundation/Foundation.h>

@class UIView, UIImage;

@interface ScreenShotManager : NSObject

+ (instancetype) shareManager;
- (void)ScreenShotWithView:(UIView *)view key:(NSString *)key;
- (BOOL)deleteFileWithKey:(NSString *)key;
- (UIImage *)getImageWithKey:(NSString *)key;
- (void)copyImageWithOriginalKey:(NSString *)originalKey newKey:(NSString *)newKey;
- (void)clearMemory;
@end
