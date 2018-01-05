//
//  FileFormatManager.h
//  xiaoge_framework
//
//  Created by LijiaChai on 17/3/29.
//  Copyright © 2017年 biyao. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FileFormatManager : NSObject {
    NSMutableDictionary *_publicKeyDict;
};

+ (instancetype)shareManager;
- (void)setVersion:(NSObject *)version downloadPath:(NSString *)downloadPath;
- (BOOL)decodeFileWithInputPath:(NSString *)inputPath;
- (void)setPublicKeyPath:(NSString *)publicKeyPath;

@end
