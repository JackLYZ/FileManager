//
//  DownloadManager.h
//  biyhao
//
//  Created by LijiaChai on 16/5/19.
//  Copyright © 2016年 LijiaChai. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^DownloadSuccess)(id data);
typedef void(^DownloadFailure)(NSError* error);
typedef void(^DownloadProgress)(long long readedBytes, long long totalBytes);

typedef NS_ENUM(NSInteger, DownloaderState)
{
	DownloaderStateIdle,
	DownloaderStateProcessing,
	DownloaderStateSuccess,
	DownloaderStateFailure
};

@interface Downloader : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) NSUInteger retryTimes;
@property (nonatomic, assign) NSUInteger level; //level 0 普通级别 1重要优先级别

- (id)initDownloadWithIdentifier:(NSString *)identifier
                              requestPath:(NSString *)requestPath
                                 savePath:(NSString *)savePath
                            progressBlock:(DownloadProgress)progress
                             successBlock:(DownloadSuccess)success
                             failureBlock:(DownloadFailure)failure;

- (void)startDownload;

- (void)cancelDownload;

@end
