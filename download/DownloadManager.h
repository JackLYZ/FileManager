//
//  DownloadManager.h
//  biyhao
//
//  Created by LijiaChai on 16/5/19.
//  Copyright © 2016年 LijiaChai. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Downloader.h"

typedef void(^DownloadProgressBlock)();
typedef void(^NotifyUpdateDownloadLevel)();

@interface DownloadParam : NSObject

@property (nonatomic, copy) NSString *downloadUrl;
@property (nonatomic, assign) NSUInteger downloadLevel;

@end

@interface DownloadManager : NSObject

@property (nonatomic, copy) DownloadProgressBlock downloadProgressBlock;
@property (nonatomic, copy) NotifyUpdateDownloadLevel notifyUpdateDownloadLevelBlock;

+ (instancetype)sharedManager;

- (NSUInteger)countForDownloading;

- (void)addDownloader:(Downloader *)downloader;
- (void)removeDownloaderByIdentifier:(NSString *)identifier;
- (void)removeAllDownloader;
- (void)setupIdleTimer;
- (BOOL)isExsitWithUrl:(NSString *)url;
- (void)startDownload;
- (void)stopDownload;
- (void)updateDownloadLevelWithResourceArray:(NSMutableArray<DownloadParam *> *)resourceArray;

@end
