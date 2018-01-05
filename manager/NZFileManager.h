//
//  NZFileManager.h
//  nezha
//
//  Created by LijiaChai on 16/5/31.
//  Copyright © 2016年 biyao. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    kGetFileSuccess,
    kGetFileFail
}GetFileResultStatus;

typedef enum {
    kUsualLevel,
    kImportantLevel
}DownloadLevel;

typedef enum {
    kUser,
    kCache
}StoreLocation;

typedef void(^NZFileNoParamsBlock)();
typedef void(^NZFileCompletionBlock)(GetFileResultStatus status, NSString *filePath, NSString *downloadUrl, NSUInteger type);

@interface NZFileManager : NSObject

+ (instancetype)shareManager;

@property (nonatomic, assign) NSInteger maxCacheAge;

- (void)getFilePathWithKey:(NSString *)key
                 urlString:(NSString *)urlString
                            type:(NSUInteger)type
                           level:(DownloadLevel)level
             storeLocation:(StoreLocation)storeLocation
                 completionBlock:(NZFileCompletionBlock)completionBlock;

- (NSString *)readStringFromCacheWithKey:(NSString *)key;
- (void)writeToCacheWithString:(NSString *)string key:(NSString *)key;
- (void)deleteCacheFileWithKey:(NSString *)key;

- (NSString *)readStringFromUserWithKey:(NSString *)key;
- (void)writeStringToUserWithString:(NSString *)string key:(NSString *)key;
- (void)deleteUserFileWithKey:(NSString *)key;
- (NSString *)getUserPathWithKey:(NSString *)key;

- (BOOL)diskFileExistsWithKey:(NSString *)key storeLocation:(StoreLocation)storeLocation;
- (NSString *)getCacheFullPathWithKey:(NSString *)key;
- (NSString *)getCachePathWithKey:(NSString *)key;
- (NSString *)getResourceRootPath;
- (NSString *)getDiskCachePath;
- (NSString *)cachedFileNameForKey:(NSString *)key;

- (void)cleanDisk;
- (void)cleanDiskWithCompletionBlock:(NZFileNoParamsBlock)completionBlock;
- (void)deleteCacheFiles;

@end
