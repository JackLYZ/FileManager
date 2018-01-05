//
//  NZFileManager.m
//  nezha
//
//  Created by LijiaChai on 16/5/31.
//  Copyright © 2016年 biyao. All rights reserved.
//

#import "NZFileManager.h"
#import "Downloader.h"
#import "DownloadManager.h"
#import "Utils.h"

#import <SDWebImage/SDImageCache.h>
#import <CommonCrypto/CommonDigest.h>

static const NSInteger kDefaultCacheMaxCacheAge = 60 * 60 * 24 * 7; // 2 week save time

#define default_floder @"default"
#define cache_floder @"com.biyao.NZFileCache"
#define user_floder @"com.biyao.NZFileUser"

#ifndef NSFoundationVersionNumber_iOS_8_0
#define NSFoundationVersionNumber_With_Fixed_5871104061079552_bug 1140.11
#else
#define NSFoundationVersionNumber_With_Fixed_5871104061079552_bug NSFoundationVersionNumber_iOS_8_0
#endif

static dispatch_queue_t get_file_session_manager_creation_queue() {
    static dispatch_queue_t xg_get_file_session_manager_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        xg_get_file_session_manager_creation_queue = dispatch_queue_create("com.xg.get.file.session.manager.creation", DISPATCH_QUEUE_SERIAL);
    });
    
    return xg_get_file_session_manager_creation_queue;
}

static void get_file_session_manager_create_task_safely(dispatch_block_t block) {
    if (NSFoundationVersionNumber < NSFoundationVersionNumber_With_Fixed_5871104061079552_bug) {
        // Fix of bug
        // Open Radar:http://openradar.appspot.com/radar?id=5871104061079552 (status: Fixed in iOS8)
        // Issue about:https://github.com/AFNetworking/AFNetworking/issues/2093
        dispatch_sync(get_file_session_manager_creation_queue(), block);
    } else {
        block();
    }
}

static dispatch_group_t get_file_session_manager_completion_group() {
    static dispatch_group_t xg_get_file_session_manager_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        xg_get_file_session_manager_completion_group = dispatch_group_create();
    });
    
    return xg_get_file_session_manager_completion_group;
}

@interface NZFileManager ()
@property (nonatomic, strong) NSString *diskCachePath;
@property (nonatomic, strong) NSString *diskUserPath;

@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, strong) NSMutableArray *waitReturnUrls; //url和type可能会重复，所以不用字典存储
@property (nonatomic, strong) NSMutableArray *waitReturnTypes;
@end

@implementation NZFileManager {
    NSFileManager *_fileManager;
}

+ (instancetype)shareManager {
    static NZFileManager *sFileManager = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        sFileManager = [[self alloc] init];
    });
    return sFileManager;
}

- (id)init {
    return [self initWithNamespace:default_floder];
}

- (id)initWithNamespace:(NSString *)ns {
    NSString *path = [self makeDiskCachePath:ns];
    return [self initWithNamespace:ns diskCacheDirectory:path];
}

- (id)initWithNamespace:(NSString *)ns diskCacheDirectory:(NSString *)directory {
    if ((self = [super init])) {
        _ioQueue = dispatch_queue_create([cache_floder UTF8String], DISPATCH_QUEUE_SERIAL);

        _maxCacheAge = kDefaultCacheMaxCacheAge;
        _waitReturnUrls = [[NSMutableArray alloc]init];
        _waitReturnTypes = [[NSMutableArray alloc]init];

        if (directory != nil) {
            _diskCachePath = [directory stringByAppendingPathComponent:cache_floder];
            _diskUserPath = [directory stringByAppendingPathComponent:user_floder];
        } else {
            NSString *path = [self makeDiskCachePath:ns];
            _diskCachePath = path;
            _diskUserPath = path;
        }
        
        __weak typeof(self) weakSelf = self;
        dispatch_sync(_ioQueue, ^{
            __strong typeof(self) strongSelf = weakSelf;
            strongSelf->_fileManager = [NSFileManager new];
            if (![strongSelf->_fileManager fileExistsAtPath:strongSelf->_diskCachePath]) {
                [strongSelf->_fileManager createDirectoryAtPath:strongSelf->_diskCachePath withIntermediateDirectories:YES attributes:nil error:NULL];
            }
            if (![strongSelf->_fileManager fileExistsAtPath:strongSelf->_diskUserPath]) {
                [strongSelf->_fileManager createDirectoryAtPath:strongSelf->_diskUserPath withIntermediateDirectories:YES attributes:nil error:NULL];
            }
        });

#if TARGET_OS_IOS
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cleanDisk)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(backgroundCleanDisk)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
#endif
    }

    return self;
}

- (void)backgroundCleanDisk {
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if(!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
        return;
    }
    UIApplication *application = [UIApplication performSelector:@selector(sharedApplication)];
    __block UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];

    [self cleanDiskWithCompletionBlock:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
}

-(NSString *)makeDiskCachePath:(NSString*)fullNamespace{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [paths[0] stringByAppendingPathComponent:fullNamespace];
}

- (void)getFilePathWithKey:(NSString *)key
                 urlString:(NSString *)urlString
                            type:(NSUInteger)type
                           level:(DownloadLevel)level
             storeLocation:(StoreLocation)storeLocation
           completionBlock:(NZFileCompletionBlock)completionBlock {
    get_file_session_manager_create_task_safely(^ {
        [self private_getFilePathWithKey:key urlString:urlString type:type level:level
                           storeLocation:storeLocation completionBlock:completionBlock];
    });
}

- (void)private_getFilePathWithKey:(NSString *)key
                 urlString:(NSString *)urlString
                      type:(NSUInteger)type
                     level:(DownloadLevel)level
             storeLocation:(StoreLocation)storeLocation
           completionBlock:(NZFileCompletionBlock)completionBlock{
    __weak typeof(self)weakSelf = self;
    NSString *resourcePath = @"";
    NSString *savePath = @"";
    if (storeLocation == kUser) {
        resourcePath = [self getUserPathWithKey:key];
        savePath = [self defaultUserPathForKey:key];
    } else if (storeLocation == kCache) {
        resourcePath = [self getCachePathWithKey:key];
        savePath = [self defaultCachePathForKey:key];
    }
    if ([self diskFileExistsWithKey:key storeLocation:storeLocation]) {
        if (completionBlock) {
            //通知主线程刷新
            dispatch_group_async(get_file_session_manager_completion_group(),
                                 dispatch_get_main_queue(), ^{
                                     completionBlock(kGetFileSuccess, resourcePath, key, type);
                                 });
        }
    } else {
        //正在下载的url里面与要下载的相同，加入等待返回列表。
        if ([[DownloadManager sharedManager] isExsitWithUrl:key]) {
            [_waitReturnUrls addObject:key];
            [_waitReturnTypes addObject:[NSNumber numberWithUnsignedInteger:type]];
            return;
        }
        Downloader *downloader = [[Downloader alloc]initDownloadWithIdentifier:key requestPath:urlString savePath:savePath progressBlock:^ void(long long readedBytes, long long totalBytes) {
            //            NSLog(@"readedBytes %lld totalBytes %lld", readedBytes, totalBytes);
        } successBlock:^ void (id data) {
            if (completionBlock) {
                //遇到相同的url下载完成直接赋值返回
                dispatch_group_async(get_file_session_manager_completion_group(),
                                     dispatch_get_main_queue(), ^{
                                         for (int i = 0; i < _waitReturnUrls.count; i++) {
                                             if ([_waitReturnUrls[i] isEqualToString:key]) {
                                                 completionBlock(kGetFileSuccess, resourcePath, key, [_waitReturnTypes[i] integerValue]);
                                                 [_waitReturnUrls removeObjectAtIndex:i];
                                                 [_waitReturnTypes removeObjectAtIndex:i];
                                                 i--;
                                             }
                                         }
                                         completionBlock(kGetFileSuccess, resourcePath, key, type);
                                     });
            }
        }failureBlock:^ void(NSError *error) {
            if (error) {
                if (completionBlock) {
                    __strong typeof(self) strongSelf = weakSelf;
                    NSLog(@"get file error, error code is %ld",(long)error.code);
                    NSLog(@"error desc:%@", error.localizedDescription);
                    
                    //遇到相同的url下载完成直接赋值返回
                    dispatch_group_async(get_file_session_manager_completion_group(),
                                         dispatch_get_main_queue(), ^{
                                             for (int i = 0; i < _waitReturnUrls.count; i++) {
                                                 if ([_waitReturnUrls[i] isEqualToString:key]) {
                                                     completionBlock(kGetFileFail, @"", key, [_waitReturnTypes[i] integerValue]);
                                                     [_waitReturnUrls removeObjectAtIndex:i];
                                                     [_waitReturnTypes removeObjectAtIndex:i];
                                                     i--;
                                                 }
                                             }
                                             [strongSelf->_fileManager removeItemAtPath:savePath error:nil];
                                             completionBlock(kGetFileFail, @"", key, type);
                                         });
                }
            }
        }];
        
        [downloader setLevel:level];
        [[DownloadManager sharedManager]addDownloader:downloader];
    }
}

- (NSString *)readStringFromCacheWithKey:(NSString *)key {
    return [NSString stringWithContentsOfFile:[self defaultCachePathForKey:key] encoding:NSUTF8StringEncoding error:NULL];
}

- (void)writeToCacheWithString:(NSString *)string key:(NSString *)key {
    [string writeToFile:[self defaultCachePathForKey:key] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (NSString *)readStringFromUserWithKey:(NSString *)key {
    return [NSString stringWithContentsOfFile:[self defaultUserPathForKey:key] encoding:NSUTF8StringEncoding error:NULL];
}

- (void)writeStringToUserWithString:(NSString *)string key:(NSString *)key {
    [string writeToFile:[self defaultUserPathForKey:key] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)deleteCacheFileWithKey:(NSString *)key {
    if ([self diskFileExistsWithKey:key storeLocation:kCache]) {
        NSError *error = nil;
        [_fileManager removeItemAtURL:[NSURL fileURLWithPath:[self defaultCachePathForKey:key]] error:&error];
    }

}

- (void)deleteUserFileWithKey:(NSString *)key {
    if ([self diskUserFileExistsWithKey:key]) {
        NSError *error = nil;
        [_fileManager removeItemAtURL:[NSURL fileURLWithPath:[self defaultUserPathForKey:key]] error:&error];
    }
}

- (BOOL)diskUserFileExistsWithKey:(NSString *)key {
    BOOL exists = NO;
    // this is an exception to access the filemanager on another queue than ioQueue, but we are using the shared instance
    // from apple docs on NSFileManager: The methods of the shared NSFileManager object can be called from multiple threads safely.
    exists = [[NSFileManager defaultManager] fileExistsAtPath:[self defaultUserPathForKey:key]];
    
    if (!exists) {
        exists = [[NSFileManager defaultManager] fileExistsAtPath:[[self defaultUserPathForKey:key] stringByDeletingPathExtension]];
    }
    
    return exists;
}

- (NSString *)getCacheFullPathWithKey:(NSString *)key {
    return  [self defaultCachePathForKey:key];
}

- (NSString *)getCachePathWithKey:(NSString *)key {
    return [NSString stringWithFormat:@"%@/%@", cache_floder, [self cachedFileNameForKey:key]] ;
}

- (NSString *)getUserPathWithKey:(NSString *)key {
    return [NSString stringWithFormat:@"%@/%@", user_floder, [self cachedFileNameForKey:key]];
}

- (NSString *)getResourceRootPath {
    return [[self makeDiskCachePath:default_floder]stringByAppendingString:@"/"];
}

- (NSString *)getDiskCachePath {
    return self.diskCachePath;
}

#pragma mark Clean Expire Logic
- (void)cleanDisk {
    [self cleanDiskWithCompletionBlock:nil];
    [[SDImageCache sharedImageCache] cleanDisk];
}

- (void)cleanDiskWithCompletionBlock:(NZFileNoParamsBlock)completionBlock {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.ioQueue, ^{
        __strong typeof(self) strongSelf = weakSelf;
        NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];
        NSArray *resourceKeys = @[NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];

        //获取路径中文件的属性
        NSDirectoryEnumerator *fileEnumerator = [strongSelf->_fileManager enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:resourceKeys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];

        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-strongSelf.maxCacheAge];

        //删除过期文件
        NSMutableArray *urlsToDelete = [[NSMutableArray alloc] init];
        for (NSURL *fileURL in fileEnumerator) {
            NSDictionary *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:NULL];

            //跳过路径
            if ([resourceValues[NSURLIsDirectoryKey] boolValue]) {
                continue;
            }
            
            NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
            if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
                [urlsToDelete addObject:fileURL];
                continue;
            }
        }

        for (NSURL *fileURL in urlsToDelete) {
            [strongSelf->_fileManager removeItemAtURL:fileURL error:nil];
        }

        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock();
            });
        }
    });
}

- (void)deleteCacheFiles {
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:self.diskCachePath];
    for (NSString *fileName in enumerator) {
        [[NSFileManager defaultManager] removeItemAtPath:[self.diskCachePath stringByAppendingPathComponent:fileName] error:nil];
    }
}

#pragma mark NZFileManager (private)

- (NSString *)cachedFileNameForKey:(NSString *)key {
    const char *str = [key UTF8String];
    if (str == NULL) {
        str = "";
    }
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%@",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10],
                          r[11], r[12], r[13], r[14], r[15], [[key pathExtension] isEqualToString:@""] ? @"" : [NSString stringWithFormat:@".%@", [key pathExtension]]];
    return filename;
}

#pragma mark - URL extension
- (NSString *)cacheKeyForURL:(NSURL *)url {
    return [url absoluteString];
}

- (NSString *)defaultCachePathForKey:(NSString *)key {
    return [self cachePathForKey:key inPath:self.diskCachePath];
}

- (NSString *)defaultUserPathForKey:(NSString *)key {
    return [self cachePathForKey:key inPath:self.diskUserPath];
}

- (NSString *)cachePathForKey:(NSString *)key inPath:(NSString *)path {
    NSString *filename = [self cachedFileNameForKey:key];
    return [path stringByAppendingPathComponent:filename];
}

- (BOOL)diskFileExistsForURL:(NSURL *)url {
    NSString *key = [self cacheKeyForURL:url];
    return [self diskFileExistsWithKey:key storeLocation:kCache];
}

- (BOOL)diskFileExistsWithKey:(NSString *)key storeLocation:(StoreLocation)storeLocation {
    BOOL exists = NO;
    // this is an exception to access the filemanager on another queue than ioQueue, but we are using the shared instance
    // from apple docs on NSFileManager: The methods of the shared NSFileManager object can be called from multiple threads safely.
    NSString *path = @"";
    if (storeLocation == kUser) {
        path = [self defaultUserPathForKey:key];
    } else if (storeLocation == kCache) {
        path = [self defaultCachePathForKey:key];
    }
    exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    
    if (!exists) {
        exists = [[NSFileManager defaultManager] fileExistsAtPath:[path stringByDeletingPathExtension]];
    }
    
    return exists;
}

@end
