//
//  DownloadManager.m
//  biyhao
//
//  Created by LijiaChai on 16/5/19.
//  Copyright © 2016年 LijiaChai. All rights reserved.
//

#import "DownloadManager.h"
#import "Utils.h"

#define MAX_CONCURRENT 10

typedef enum {
    kUsualLevel,
    kImportantLevel
}DownloadLevel;

@implementation DownloadParam

@end

@interface DownloadManager ()

@property (nonatomic, strong) NSMutableArray<Downloader *> *operationQueue;
@property (nonatomic, strong) NSMutableDictionary *downloadQueue;
@property (nonatomic, strong) NSThread *downloadThread;
@property (nonatomic, strong) NSLock *lock;

@end

@implementation DownloadManager

+ (instancetype) sharedManager {
    static DownloadManager *sDownloadManager = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        sDownloadManager = [[self alloc] init];
    });
    return sDownloadManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _operationQueue = [[NSMutableArray alloc]init];
        _downloadQueue = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc]init];
    }
    return self;
}

- (void)startDownload {
    _downloadThread =  [[NSThread alloc] initWithTarget:self selector:@selector(downloadThreadFunc) object:nil];
    [_downloadThread start];
}

- (void)stopDownload {
    [_downloadThread cancel];
    _downloadThread = nil;
}

- (NSUInteger)countForDownloading {
    return _operationQueue.count;
}

- (void)setNotifyUpdateDownloadLevelBlock:(NotifyUpdateDownloadLevel)notifyUpdateDownloadLevelBlock {
    _notifyUpdateDownloadLevelBlock = notifyUpdateDownloadLevelBlock;
}

- (void)addDownloader:(Downloader *)downloader {
    //download level 0 普通级别 1重要优先级别
    if (downloader.level == kUsualLevel) {
        [_operationQueue addObject:downloader];
    } else if (downloader.level == kImportantLevel) {
        [downloader startDownload];
        [_downloadQueue setObject:downloader forKey:downloader.identifier];
    }
}

- (void)downloadThreadFunc {
    while (![[NSThread currentThread] isCancelled]) {
        NSString *identifier = @"";
        Downloader *downloader = nil;
        
        [_lock lock];

        if (_operationQueue.count > 0) {
            downloader = _operationQueue.lastObject;
            identifier = downloader.identifier;
        }
        
        if (_downloadQueue.count < MAX_CONCURRENT && ![identifier isEqualToString:@""]) {
            [_operationQueue removeObject:downloader];
            [downloader startDownload];
            [_downloadQueue setObject:downloader forKey:identifier];
            
            if (_operationQueue.count > MAX_CONCURRENT) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (_notifyUpdateDownloadLevelBlock) {
                        _notifyUpdateDownloadLevelBlock();
                    }
                });
            }
        }
        [_lock unlock];

        [NSThread sleepForTimeInterval:0.1];
    }
}

- (void)removeDownloaderByIdentifier:(NSString *)identifier {
    if (identifier && identifier.length > 0) {
        NSString *operationKey = identifier;
        Downloader *downloader  = _downloadQueue[operationKey];
        [downloader cancelDownload];
        [_downloadQueue removeObjectForKey:operationKey];
        [self setupIdleTimer];
        if (_downloadProgressBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                _downloadProgressBlock();
            });
        }
    }
}

- (void)removeAllDownloader {
    [_lock lock];

    [_downloadQueue enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        Downloader *downloader = obj;
        [downloader cancelDownload];
    }];
    
    [_operationQueue removeAllObjects];
    [_downloadQueue removeAllObjects];
    
    [_lock unlock];
    [self setupIdleTimer];
}

- (void)setupIdleTimer {
    [Utils setIdleTimerDisabled:(_operationQueue.count != 0 && _downloadQueue.count != 0)];
}

- (BOOL)isExsitWithUrl:(NSString *)url {
    __block BOOL isExsit = NO;

    [_lock lock];

    [_operationQueue enumerateObjectsUsingBlock:^(Downloader * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj.identifier isEqualToString:url]) {
            isExsit = YES;
            *stop = YES;
        }
    }];

    if (!isExsit) {
        [_downloadQueue enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([url isEqualToString:key]) {
                isExsit = YES;
                *stop = YES;
            }
        }];
    }
    
    [_lock unlock];
    return isExsit;
}

- (void)updateDownloadLevelWithResourceArray:(NSMutableArray<DownloadParam *> *)resourceArray {
    //resourceArray按照downloadLevel从大到小排序
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSUInteger count = resourceArray.count;
        
        [strongSelf.lock lock];
        
        for (Downloader *downloader in strongSelf.operationQueue) {
            downloader.level = 0;
        }
        
        for (int i = 0; i < count; i++) {
            DownloadParam *param = [resourceArray objectAtIndex:i];
            for (Downloader *downloader in strongSelf.operationQueue) {
                if ([downloader.identifier isEqualToString:param.downloadUrl]) {
                    downloader.level = param.downloadLevel;
                }
            }
        }
        
        for(int i = 0; i < strongSelf.operationQueue.count; i++) {
            for(int j = 0; i + j < strongSelf.operationQueue.count - 1; j++) {
                if(_operationQueue[j].level > strongSelf.operationQueue[j + 1].level) {
                    Downloader *tempDownloader = strongSelf.operationQueue[j];
                    strongSelf.operationQueue[j] = strongSelf.operationQueue[j + 1];
                    strongSelf.operationQueue[j + 1] = tempDownloader;
                }
            }
        }
        
        [strongSelf.lock unlock];
    });
}

@end
