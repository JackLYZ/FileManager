//
//  Downloader.h
//  biyhao
//
//  Created by LijiaChai on 16/5/19.
//  Copyright © 2016年 LijiaChai. All rights reserved.
//

#import "Downloader.h"
#include "DownloadManager.h"
#import "FileFormatManager.h"
#import "Utils.h"
#import <AFNetworking/AFNetworking.h>

#define REQUEST_TIMEOUT 10.0

static dispatch_queue_t download_finish_data_processing_queue() {
    static dispatch_queue_t xg_download_finish_data_processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        xg_download_finish_data_processing_queue = dispatch_queue_create("com.xiaoge.download.session.data.processing", DISPATCH_QUEUE_SERIAL);
    });
    
    return xg_download_finish_data_processing_queue;
}

@interface Downloader ()

@property (nonatomic, copy) NSString *requestPath;
@property (nonatomic, copy) NSString *savePath;
@property (nonatomic, readwrite) DownloaderState state;

@property (nonatomic, copy) DownloadProgress downloadProgressBlock;
@property (nonatomic, copy) DownloadSuccess downloadSuccessBlock;
@property (nonatomic, copy) DownloadFailure downloadFailureBlock;

@property (nonatomic, strong) NSURLSessionDownloadTask *downloadTask;

@end

@implementation Downloader

+ (AFURLSessionManager *)getManager {
    static AFURLSessionManager *sAFURLSessionManager = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        sAFURLSessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    });
    return sAFURLSessionManager;
}

- (id)initDownloadWithIdentifier:(NSString *)identifier
                     requestPath:(NSString *)requestPath
                        savePath:(NSString *)savePath
                   progressBlock:(DownloadProgress)progress
                    successBlock:(DownloadSuccess)success
                    failureBlock:(DownloadFailure)failure {
    self = [super init];
    if (self) {
        _identifier = identifier;
        _requestPath = requestPath;
        _savePath = savePath;
        
        _state = DownloaderStateIdle;
        
        _downloadProgressBlock = progress;
        _downloadSuccessBlock = success;
        _downloadFailureBlock = failure;
        _retryTimes = 0;
    }
    return self;
}

- (void)startDownload {
    _state = DownloaderStateProcessing;
    
    AFURLSessionManager *manager = [Downloader getManager];
    NSURL *URL = [NSURL URLWithString:_requestPath];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:REQUEST_TIMEOUT];
    
    __weak typeof(self) weakSelf = self;
    _downloadTask = [manager downloadTaskWithRequest:request progress:^ void (NSProgress *progress) {
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf.downloadProgressBlock) {
            strongSelf.downloadProgressBlock(progress.completedUnitCount, progress.totalUnitCount);
        }
    }destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf.savePath) {
            NSString * cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
            NSString *path = [cacheDir stringByAppendingPathComponent:
                              response.suggestedFilename];
            return [NSURL fileURLWithPath:path];
        } else {
            NSURL *saveURL = [[NSURL alloc]initFileURLWithPath:strongSelf.savePath];
            return saveURL;
        }
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!error) {
            dispatch_async(download_finish_data_processing_queue(), ^ {
            strongSelf.state = DownloaderStateSuccess;
                if (![strongSelf.requestPath isEqualToString:strongSelf.identifier]) {
                    BOOL isSuccess = [[FileFormatManager shareManager]decodeFileWithInputPath:strongSelf.savePath];
                    if (!isSuccess) {
                        //TODO:测试查问题用
                        [Utils showAlertWithErrorMessage:[NSString stringWithFormat:@"解密文件失败!服务器地址:%@ 云平台地址:%@ 本地存储位置:%@", strongSelf.identifier, strongSelf.requestPath, strongSelf.savePath]];
                    }
                }
                if (strongSelf.downloadSuccessBlock) {
                    strongSelf.downloadSuccessBlock(strongSelf.savePath);
                }
                [[DownloadManager sharedManager]setupIdleTimer];
                [[DownloadManager sharedManager]removeDownloaderByIdentifier:strongSelf.identifier];
            });
        } else {
            strongSelf.state = DownloaderStateFailure;
            if (strongSelf.retryTimes == 3) {
                if (![strongSelf.requestPath isEqualToString:strongSelf.identifier]) {
                    strongSelf.retryTimes = 0;
                    strongSelf.requestPath = strongSelf.identifier;
                    [self cancelDownload];
                    [self startDownload];
                    strongSelf.retryTimes++;
                } else {
                    if (strongSelf.downloadFailureBlock) {
                        strongSelf.downloadFailureBlock(error);
                    }
                    [[DownloadManager sharedManager]setupIdleTimer];
                    [[DownloadManager sharedManager]removeDownloaderByIdentifier:strongSelf.identifier];
                }
            } else {
                [self cancelDownload];
                [self startDownload];
                strongSelf.retryTimes++;
            }
        }
    }];
    
    [_downloadTask resume];
    [[DownloadManager sharedManager]setupIdleTimer];
}

- (void)cancelDownload {
	if (_state != DownloaderStateSuccess) {
        [_downloadTask cancel];
		[self stopAndDelete:YES];
	}
}

- (void)stopAndDelete:(BOOL)delete {
	if (delete) {
		NSError *error;
		[[NSFileManager defaultManager] removeItemAtPath:self.savePath error:&error];
	}
	_state = DownloaderStateIdle;
}

@end
