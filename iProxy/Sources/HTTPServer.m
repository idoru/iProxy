//
//  HTTPServer.m
//  TextTransfer
//
//  Created by Matt Gallagher on 2009/07/13.
//  Copyright 2009 Matt Gallagher. All rights reserved.
//
//  Permission is given to use this source code file, free of charge, in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//

#import "HTTPServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <CFNetwork/CFNetwork.h>
#import "HTTPResponseHandler.h"
#import "SharedHeader.h"

NSString * const HTTPServerNotificationStateChanged = @"ServerNotificationStateChanged";

@implementation HTTPServer

+ (id)sharedHTTPServer
{
	static HTTPServer *shared = nil;
    
    if (!shared) {
    	shared = [[HTTPServer alloc] init];
    }
    return shared;
}

- (id)init
{
	self = [super init];
    if (self) {
		incomingRequests = [[NSMutableDictionary alloc] init];
        responseHandlers = [[NSMutableArray alloc] init];
    }
	return self;
}

- (void)dealloc
{
	[incomingRequests release];
    [super dealloc];
}

- (NSString *)serviceDomain
{
	return HTTP_SERVER_DOMAIN;
}

- (int)servicePort
{
	return HTTP_SERVER_PORT;
}

- (void)_stopReceivingForFileHandle:(NSFileHandle *)incomingFileHandle close:(BOOL)closeFileHandle
{
	if (closeFileHandle) {
		[incomingFileHandle closeFile];
	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleDataAvailableNotification object:incomingFileHandle];
	[incomingRequests removeObjectForKey:incomingFileHandle];
}

- (void)_closeSocket
{
	[super _closeSocket];
    for (NSFileHandle *incomingFileHandle in incomingRequests) {
        [self _stopReceivingForFileHandle:incomingFileHandle close:YES];
    }
}

- (void)didOpenConnection:(NSDictionary *)info
{
    if(info) {
    	CFHTTPMessageRef message;
        
        message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, TRUE);
		[incomingRequests setObject:(id)message forKey:[info objectForKey:@"handle"]];
        CFRelease(message);
		
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			selector:@selector(receiveIncomingDataNotification:)
			name:NSFileHandleDataAvailableNotification
			object:[info objectForKey:@"handle"]];
		
        [[info objectForKey:@"handle"] waitForDataInBackgroundAndNotify];
    }
}

//
// receiveIncomingDataNotification:
//
// Receive new data for an incoming connection.
//
// Once enough data is received to fully parse the HTTP headers,
// a HTTPResponseHandler will be spawned to generate a response.
//
// Parameters:
//    notification - data received notification
//
- (void)receiveIncomingDataNotification:(NSNotification *)notification
{
	NSFileHandle *incomingFileHandle = [notification object];
	NSData *data = [incomingFileHandle availableData];
	
	if ([data length] == 0) {
		[self _stopReceivingForFileHandle:incomingFileHandle close:YES];
		return;
	}

	CFHTTPMessageRef incomingRequest = (CFHTTPMessageRef)[incomingRequests objectForKey:incomingFileHandle];
	if (!incomingRequest) {
		[self _stopReceivingForFileHandle:incomingFileHandle close:YES];
		return;
	}
	
	if (!CFHTTPMessageAppendBytes(incomingRequest, [data bytes], [data length])) {
		[self _stopReceivingForFileHandle:incomingFileHandle close:YES];
		return;
	}

	if(CFHTTPMessageIsHeaderComplete(incomingRequest)) {
		HTTPResponseHandler *handler =
			[HTTPResponseHandler
				handlerForRequest:incomingRequest
				fileHandle:incomingFileHandle
				server:self];
		
		[responseHandlers addObject:handler];
		[self _stopReceivingForFileHandle:incomingFileHandle close:NO];

		[handler startResponse];	
		return;
	}

	[incomingFileHandle waitForDataInBackgroundAndNotify];
}

//
// closeHandler:
//
// Shuts down a response handler and removes it from the set of handlers.
//
// Parameters:
//    aHandler - the handler to shut down.
//
- (void)closeHandler:(HTTPResponseHandler *)aHandler
{
	[aHandler endResponse];
	[responseHandlers removeObject:aHandler];
}

@end
