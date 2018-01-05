//
//  FileFormatManager.m
//  xiaoge_framework
//
//  Created by LijiaChai on 17/3/29.
//  Copyright © 2017年 biyao. All rights reserved.
//

#import "FileFormatManager.h"
#import "NZFileManager.h"
#import "DownloadManager.h"
#import "Utils.h"

#include "FileFormatUtil.h"

@interface FileFormatManager ()

@property (nonatomic, copy) NSString *public_key_path;

@end

@implementation FileFormatManager

+ (instancetype)shareManager {
    static FileFormatManager *sFileFormatManager = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        sFileFormatManager = [[self alloc] init];
    });
    return sFileFormatManager;
}

- (id)init {
    self = [super init];
    if (self) {
        NSString *publicString = [[NZFileManager shareManager]readStringFromUserWithKey:@"publicKey"];
       _public_key_path = @"";
        _publicKeyDict = (NSMutableDictionary *)[Utils dictionaryWithJsonString:publicString];
        if (!_publicKeyDict) {
            _publicKeyDict = [[NSMutableDictionary alloc]init];
        }
    }
    return self;
}

- (void)setPublicKeyPath:(NSString *)publicKeyPath {
    _public_key_path = publicKeyPath;
}

- (void)setVersion:(NSObject *)version downloadPath:(NSString *)downloadPath {
    if (![_publicKeyDict objectForKey:downloadPath]) {
        [_publicKeyDict setObject:version forKey:downloadPath];
        [[DownloadManager sharedManager]startDownload];
        [[NZFileManager shareManager]getFilePathWithKey:downloadPath urlString:downloadPath type:0 level:kImportantLevel storeLocation:kUser completionBlock:^(GetFileResultStatus status, NSString *filePath, NSString *downloadUrl, NSUInteger type) {
            [[DownloadManager sharedManager]stopDownload];
            //TODO:失败就不去操作文件目录,但如果下载文件失败，同样有风险,因为有些云文件会依赖此文件。
            if (status == kGetFileFail) {
                return;
            }
            //解出对应版本的公钥
            NSString *keyPath = [[[NZFileManager shareManager]getResourceRootPath] stringByAppendingString:filePath];
            std::ifstream fin([keyPath UTF8String],  std::ios::binary | std::ios::in);
            NSString *resultPath = [[[NZFileManager shareManager]getResourceRootPath]stringByAppendingString:@"result.pem"];
            std::ofstream fout([resultPath UTF8String], std::ios::binary | std::ios::out);
            FileFormatUtil *fileFormatUtil = new FileFormatUtil();
            NSString *public_key_name = _public_key_path;
            NSAssert(![public_key_name isEqualToString:@""], @"public_key_name must be not equal null string");
            NSString *ras_key_path = [[NSBundle mainBundle]pathForResource:public_key_name ofType:@"pem"];
            fileFormatUtil->DecodeAES(fin, fout, [ras_key_path UTF8String]);
            fin.close();
            fout.close();
            delete fileFormatUtil;
            [[NSFileManager defaultManager]removeItemAtPath:keyPath error:nil];
            [[NSFileManager defaultManager]moveItemAtPath:resultPath toPath:keyPath error:nil];
        }];
        NSString *publicKeyString = [Utils dictionaryToJson:_publicKeyDict];
        [[NZFileManager shareManager] writeStringToUserWithString:publicKeyString key:@"publicKey"];
    }
}

- (BOOL)decodeFileWithInputPath:(NSString *)inputPath {
    FileFormatUtil *fileFormatUtil = new FileFormatUtil();
    
    std::ifstream fin([inputPath UTF8String],  std::ios::binary | std::ios::in);
    NSString *resultPath = [[[NZFileManager shareManager]getResourceRootPath]stringByAppendingString:@"tempFile"];
    std::ofstream fout([resultPath UTF8String], std::ios::binary | std::ios::out);
    int resultCode = 0;
    for (NSUInteger i = _publicKeyDict.count; i > 0; i--) {
        NSNumber *object = [NSNumber numberWithUnsignedInteger:i];
        for (NSString *key in _publicKeyDict) {
            NSNumber *tempObject = [_publicKeyDict objectForKey:key];
            if ([object intValue] == [tempObject intValue]) {
                //解文件
                NSString *keyPath = [[NZFileManager shareManager]getUserPathWithKey:key];
                std::string publicKey = [[[[NZFileManager shareManager]getResourceRootPath]stringByAppendingString:keyPath] UTF8String];
                std::string msg = "cloudUnPack";
                resultCode = fileFormatUtil->UnPack(fin, fout, publicKey, msg);
                if (resultCode != 0) {
                    continue;
                } else {
                    break;
                }
            }
        }
        if (resultCode != 0) {
            continue;
        } else {
            break;
        }
    }
    delete fileFormatUtil;
    fin.close();
    fout.close();
    [[NSFileManager defaultManager]removeItemAtPath:inputPath error:nil];
    [[NSFileManager defaultManager]moveItemAtPath:resultPath toPath:inputPath error:nil];
    if (resultCode != 0) {
        return NO;
    } else {
        return YES;
    }
    return NO;
}

@end
