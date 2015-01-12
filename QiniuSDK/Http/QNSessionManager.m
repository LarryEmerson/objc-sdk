//
//  QNHttpManager.m
//  QiniuSDK
//
//  Created by bailong on 14/10/1.
//  Copyright (c) 2014年 Qiniu. All rights reserved.
//

#import <AFNetworking/AFNetworking.h>

#import "QNConfig.h"
#import "QNSessionManager.h"
#import "QNUserAgent.h"
#import "QNResponseInfo.h"
#import "QNDns.h"

#if (defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000) || (defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 1090)

@interface QNSessionManager ()
@property (nonatomic) AFHTTPSessionManager *httpManager;
@end

static NSString *userAgent = nil;

@implementation QNSessionManager

+ (void)initialize {
	userAgent = QNUserAgent();
}

- (instancetype)initWithProxy:(NSDictionary *)proxyDict {
	if (self = [super init]) {
		NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
		if (proxyDict != nil) {
			configuration.connectionProxyDictionary = proxyDict;
		}
		_httpManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:configuration];
		_httpManager.responseSerializer = [AFHTTPResponseSerializer serializer];
	}

	return self;
}

+ (QNResponseInfo *)buildResponseInfo:(NSHTTPURLResponse *)response
                            withError:(NSError *)error
                         withDuration:(double)duration
                         withResponse:(NSData *)body
                             withHost:(NSString *)host {
	QNResponseInfo *info;

	if (response) {
		NSDictionary *headers = [response allHeaderFields];
		NSString *reqId = headers[@"X-Reqid"];
		NSString *xlog = headers[@"X-Log"];
		int status =  (int)[response statusCode];
		info = [[QNResponseInfo alloc] init:status withReqId:reqId withXLog:xlog withHost:host withDuration:duration withBody:body];
	}
	else {
		info = [QNResponseInfo responseInfoWithNetError:error host:host duration:duration];
	}
	return info;
}

- (void)  sendRequest:(NSMutableURLRequest *)request
    withCompleteBlock:(QNCompleteBlock)completeBlock
    withProgressBlock:(QNInternalProgressBlock)progressBlock {
	__block NSDate *startTime = [NSDate date];
	NSProgress *progress = nil;
	__block NSString *host = request.URL.host;

	NSURLSessionUploadTask *uploadTask = [_httpManager uploadTaskWithStreamedRequest:request progress:&progress completionHandler: ^(NSURLResponse *response, id responseObject, NSError *error) {
	    NSData *data = responseObject;
	    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
	    double duration = [[NSDate date] timeIntervalSinceDate:startTime];
	    QNResponseInfo *info;
	    NSDictionary *resp = nil;
	    if (error == nil) {
	        info = [QNSessionManager buildResponseInfo:httpResponse withError:nil withDuration:duration withResponse:data withHost:host];
	        if (info.isOK) {
	            NSError *tmp;
	            resp = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:&tmp];
			}
		}
	    else {
	        info = [QNSessionManager buildResponseInfo:httpResponse withError:error withDuration:duration withResponse:data withHost:host];
		}
	    [progress removeObserver:self forKeyPath:@"fractionCompleted" context:(__bridge void *)(progressBlock)];
	    completeBlock(info, resp);
	}];
	[progress addObserver:self forKeyPath:@"fractionCompleted" options:NSKeyValueObservingOptionNew context:(__bridge void *)(progressBlock)];

	[request setTimeoutInterval:kQNTimeoutInterval];

	[request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
	[request setValue:nil forHTTPHeaderField:@"Accept-Language"];
	[uploadTask resume];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ([keyPath isEqualToString:@"fractionCompleted"]) {
		NSProgress *progress = (NSProgress *)object;
		QNInternalProgressBlock progressBlock = (__bridge QNInternalProgressBlock)context;
		if (progress != nil && progressBlock != nil) {
			progressBlock(progress.completedUnitCount, progress.totalUnitCount);
		}
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)multipartPost:(NSString *)url
             withData:(NSData *)data
           withParams:(NSDictionary *)params
         withFileName:(NSString *)key
         withMimeType:(NSString *)mime
    withCompleteBlock:(QNCompleteBlock)completeBlock
    withProgressBlock:(QNInternalProgressBlock)progressBlock
      withCancelBlock:(QNCancelBlock)cancelBlock {
	NSMutableURLRequest *request = [_httpManager.requestSerializer
	                                multipartFormRequestWithMethod:@"POST"
	                                                     URLString:url
	                                                    parameters:params
	                                     constructingBodyWithBlock: ^(id < AFMultipartFormData > formData) {
	    [formData appendPartWithFileData:data name:@"file" fileName:key mimeType:mime];
	}

	                                                         error:nil];
	[self sendRequest:request
	    withCompleteBlock:completeBlock
	    withProgressBlock:progressBlock];
}

- (void)         post:(NSString *)url
             withData:(NSData *)data
           withParams:(NSDictionary *)params
          withHeaders:(NSDictionary *)headers
    withCompleteBlock:(QNCompleteBlock)completeBlock
    withProgressBlock:(QNInternalProgressBlock)progressBlock
      withCancelBlock:(QNCancelBlock)cancelBlock {
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[[NSURL alloc] initWithString:url]];
	if (headers) {
		[request setAllHTTPHeaderFields:headers];
	}

	[request setHTTPMethod:@"POST"];

	if (params) {
		[request setValuesForKeysWithDictionary:params];
	}
	[request setHTTPBody:data];
	[self sendRequest:request
	    withCompleteBlock:completeBlock
	    withProgressBlock:progressBlock];
}

@end

#endif
