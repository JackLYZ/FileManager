//
//  ScreenShotManager.m
//  nezha
//
//  Created by LijiaChai on 16/5/31.
//  Copyright © 2016年 biyao. All rights reserved.
//

#import "ScreenShotManager.h"
#import <UIKit/UIKit.h>
#import "Utils.h"

#import <SDWebImage/SDWebImageDecoder.h>
#import <SDWebImage/UIImage+MultiFormat.h>

#define Quality 0.1f

UIImage *NZScaledImageForKey(NSString *key, UIImage *image) {
    if (!image) {
        return nil;
    }
    
    if ([image.images count] > 0) {
        NSMutableArray *scaledImages = [NSMutableArray array];
        
        for (UIImage *tempImage in image.images) {
            [scaledImages addObject:NZScaledImageForKey(key, tempImage)];
        }
        
        return [UIImage animatedImageWithImages:scaledImages duration:image.duration];
    }
    else {
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
            CGFloat scale = 1;
            if (key.length >= 8) {
                NSRange range = [key rangeOfString:@"@2x."];
                if (range.location != NSNotFound) {
                    scale = 2.0;
                }
                
                range = [key rangeOfString:@"@3x."];
                if (range.location != NSNotFound) {
                    scale = 3.0;
                }
            }
            
            UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
            image = scaledImage;
        }
        return image;
    }
}

@interface NZAutoPurgeCache : NSCache
@end

@implementation NZAutoPurgeCache

- (id)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeAllObjects) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    
}

@end

@interface ScreenShotManager ()

@property (nonatomic, strong) NSCache *memCache;

@end

@implementation ScreenShotManager

+ (instancetype) shareManager {
    static ScreenShotManager *sScreenShotManager = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        sScreenShotManager = [[self alloc] init];
    });
    return sScreenShotManager;
}

- (id)init {
    self = [super init];
    if (self) {
        _memCache = [[NZAutoPurgeCache alloc] init];
        _memCache.name = @"com.nezha.screenShot";
    }
    return self;
}

NSUInteger NZCacheCostForImage(UIImage *image) {
    return image.size.height * image.size.width * image.scale * image.scale;
}

/**
 *  @author chailijia, 16-05-31 16:05:38
 *
 *  @brief 截屏工具
 *
 *  @param view 传入需要截屏的view
 *  @param key 文件的全路径
 */
- (void)ScreenShotWithView:(UIView *)view key:(NSString *)key {
    UIImage *sendImage = [Utils screenShotWithEAGLView:view];
    NSData *imageViewData = UIImageJPEGRepresentation(sendImage, Quality);

    NSString *savedImagePath = [self getFilePathWithKey:key];
    [imageViewData writeToFile:savedImagePath atomically:YES];//保存照片到沙盒目录
    
    if ([_memCache objectForKey:key]) {
        [_memCache removeObjectForKey:key];
    }
    
    NSInteger cost = NZCacheCostForImage(sendImage);
    if (sendImage) {
        [_memCache setObject:sendImage forKey:key cost:cost];
    }
}

- (BOOL)deleteFileWithKey:(NSString *)key {
    NSString *path = [self getFilePathWithKey:key];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isSuccess = NO;
    if ([fileManager fileExistsAtPath:path]) {
        isSuccess = [fileManager removeItemAtPath:path error:nil];
        if ([_memCache objectForKey:key]) {
            [_memCache removeObjectForKey:key];
        }
    }
    return isSuccess;
}

- (NSString *)getFilePathWithKey:(NSString *)key {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *pictureName= [NSString stringWithFormat:@"screenShot_%@.jpg",key];
    NSString *documentsDirectory = [paths firstObject];
    NSString *savedImagePath = [documentsDirectory stringByAppendingPathComponent:pictureName];
    return savedImagePath;
}

- (UIImage *)getImageWithKey:(NSString *)key {
    UIImage *image = [_memCache objectForKey:key];
    if (image) {
        return image;
    }
    
    //使用下面方法能降低图片的内存使用率
    NSString *imagePath = [self getFilePathWithKey:key];
    NSData *data = [NSData dataWithContentsOfFile:imagePath];
    image = [UIImage sd_imageWithData:data];
    image = NZScaledImageForKey(key, image);
    image = [UIImage decodedImageWithImage:image];
    NSInteger cost = NZCacheCostForImage(image);
    if (image) {
        [_memCache setObject:image forKey:key cost:cost];
    }
    return image;
}

- (void)copyImageWithOriginalKey:(NSString *)originalKey newKey:(NSString *)newKey {
    UIImage *image = [self getImageWithKey:originalKey];
    //TODO: 可以试验将质量降低。
    NSData *imageViewData = UIImageJPEGRepresentation(image, Quality);
    [imageViewData writeToFile:[self getFilePathWithKey:newKey] atomically:YES];
}

- (void)clearMemory {
    [_memCache removeAllObjects];
}

@end
