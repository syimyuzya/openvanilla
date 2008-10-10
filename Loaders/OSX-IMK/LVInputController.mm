// Copyright (c) 2004-2008 The OpenVanilla Project (http://openvanilla.org)
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of OpenVanilla nor the names of its contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import "LVInputController.h"
#import "LVModuleManager.h"

@implementation LVInputController
- (id)initWithServer:(IMKServer*)server delegate:(id)delegate client:(id)inputClient
{
	if (self = [super initWithServer:server delegate:delegate client:inputClient]) {
		_contextSandwich = [[LVModuleManager sharedManager] createContextSandwich];
		_candidateText = new LVCandidate;
		_composingBuffer = new LVBuffer;
	}

	return self;
}
- (void)dealloc
{
	delete _contextSandwich;
	delete _candidateText;
	delete _composingBuffer;
    [super dealloc];
}

- (void)_updateComposingBuffer:(id)client cursorAtIndex:(NSUInteger)cursorIndex highlightRange:(NSRange)range
{
	#warning Calculate UTF-16
	NSString *composingBuffer = [NSString stringWithUTF8String:_composingBuffer->composingBuffer().c_str()];
	
	NSMutableAttributedString *attrString = [[[NSMutableAttributedString alloc] initWithString:composingBuffer attributes:[NSDictionary dictionary]] autorelease];    

    NSRange markerRange[3];
    NSInteger markerStyle[3];
    NSInteger markerCount = 0;

	if (range.location != NSNotFound) {
	    if (range.location) {
            markerRange[markerCount] = NSMakeRange(0, range.location);
            markerStyle[markerCount] = NSUnderlineStyleSingle;
            markerCount++;
	    }
	    
	    if (range.length) {
            markerRange[markerCount] = range;
            markerStyle[markerCount] = NSUnderlineStyleThick;
            markerCount++;
	    }
	    
        vector<string> codepoints = OVUTF8Helper::SplitStringByCodePoint(_composingBuffer->composingBuffer());
		
	    if (codepoints.size() > range.location + range.length) {
            markerRange[markerCount] = NSMakeRange(range.location + range.length, [composingBuffer length] - range.location + range.length);
            markerStyle[markerCount] = NSUnderlineStyleSingle;
            markerCount++;
	    }
	}
	else {
        markerRange[markerCount] = NSMakeRange(0, [composingBuffer length]);
        markerStyle[markerCount] = NSUnderlineStyleSingle;
        markerCount++;
	}
	
    for (NSInteger i = 0 ; i < markerCount ; i++) {
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
        NSDictionary *attrDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithInt:markerStyle[i]], NSUnderlineStyleAttributeName,
								  [NSNumber numberWithInt:i], NSMarkedClauseSegmentAttributeName, nil];
#else
        NSDictionary *attrDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithInt:markerStyle[i]], @"UnderlineStyleAttribute",
								  [NSNumber numberWithInt:i], @"MarkedClauseSegmentAttribute", nil];
#endif		
        [attrString setAttributes:attrDict range:markerRange[i]];  
    }

    // selectionRange means "cursor position"
	NSRange selectionRange = NSMakeRange(cursorIndex, 0);	
	[client setMarkedText:attrString selectionRange:selectionRange replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}
// To fix the curson position in some applications such as WOW
- (NSPoint)_fixCaretPosition:(NSPoint)caretPosition
{
	NSRect frame = [[NSScreen mainScreen] frame];
	BOOL hasFocus = NO;
	
	NSArray *screens = [NSScreen screens];
	NSEnumerator *enumerator = [screens objectEnumerator];
	NSScreen *screen;
	while (screen = [enumerator nextObject]) {
		NSRect screenFrame = [screen frame];
		
		if (!hasFocus && caretPosition.x >= NSMinX(screenFrame) && caretPosition.x <= NSMaxX(screenFrame)) {
			frame = screenFrame;
			hasFocus = YES;
			break;
		}
	}
	
	if (hasFocus) {		
		return caretPosition;
	}

	NSPoint point;		
	point.x = (int)(frame.size.width / 2.0);
	point.y = (int)(frame.size.height / 2.0);
	return point;
}
- (unsigned int)recognizedEvents:(id)sender
{
    return NSKeyDownMask | NSKeyUpMask | NSFlagsChangedMask | NSMouseEnteredMask | NSLeftMouseDownMask | NSLeftMouseDragged;
}
- (NSString *)currentKeyboardLayout
{
	return @"com.apple.keylayout.US";
}
- (void)activateServer:(id)sender
{
	_contextSandwich->start(_composingBuffer, _candidateText, [[LVModuleManager sharedManager] loaderService]);
}
- (void)deactivateServer:(id)sender
{
	_contextSandwich->end();
}
- (void)commitComposition:(id)sender 
{    
	NSString *committedText = [NSString stringWithUTF8String:_composingBuffer->committedString().c_str()];
    [sender insertText:committedText replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
	_composingBuffer->clearCommittedString();
}
- (BOOL)handleEvent:(NSEvent*)event client:(id)sender
{
    BOOL handled = NO;
    
    if ([event type] == NSFlagsChanged) {
        // handles caps lock and shift here
    }
    else if ([event type] == NSKeyDown) {
		NSString *chars = [event characters];
		unsigned int cocoaModifiers = [event modifierFlags];
		unsigned short virtualKeyCode = [event keyCode];		
		
		LVKeyCode keyCode;		
        if (cocoaModifiers & NSAlphaShiftKeyMask) keyCode.capsLock = true;
        // if (cocoaModifiers & NSShiftKeyMask) vanillaModifiers |= OVKeyMask::Shift;
        if (cocoaModifiers & NSControlKeyMask) keyCode.ctrl = true;
        if (cocoaModifiers & NSAlternateKeyMask) keyCode.opt = true;
        // if (cocoaModifiers & NSCommandKeyMask) vanillaModifiers |= OVKeyMask::Command;

		UInt32 numKeys[16] = {    
			0x52, 0x53, 0x54, 0x55, 0x56, 0x57, // 0,1,2,3,4,5
			0x58, 0x59, 0x5b, 0x5c, 0x41, 0x45, 0x4e, 0x43, 0x4b, 0x51 // 6,7,8,9,.,+,-,*,/,=
		};
		
		for (size_t i = 0; i < 16; i++) {
			if (virtualKeyCode == numKeys[i]) {
                // vanillaModifiers |= OVKeyMask::NumLock; // only if it's numpad key we put mask back
				break;
			}
		}
		
		UniChar unicharCode = 0;
		if ([chars length] > 0) {
			unicharCode = [chars characterAtIndex:0];
            
            // translates CTRL-[A-Z] to the correct PVKeyImpl
            if (unicharCode < 27 && (cocoaModifiers & NSControlKeyMask)) {
                unicharCode += ('a' - 1);
            }
            
			keyCode.keyCode = unicharCode;
			
            if (unicharCode < 128) {
				handled = _contextSandwich->keyEvent(&keyCode, _composingBuffer, _candidateText, [[LVModuleManager sharedManager] loaderService]);
            }
            else {
            }
        }
        else {
        }
    }
	
	if (_composingBuffer->shouldCommit()) {
		[self commitComposition:sender];
		_composingBuffer->clearCommittedString();
	}
	
	if (_composingBuffer->shouldUpdate()) {
		NSRange highlightRange = NSMakeRange(NSNotFound, NSNotFound);
		int hf = _composingBuffer->highlightFrom(), ht = _composingBuffer->highlightTo();
		if (hf >= 0 && ht >= 0 && (ht - hf) >= 0) {
			highlightRange = NSMakeRange(hf, ht - hf);
		}
		
		[self _updateComposingBuffer:sender cursorAtIndex:_composingBuffer->cursorIndex() highlightRange:highlightRange];
	}
	

    // update cursor position
    NSPoint caretPosition;
    NSRect lineHeightRect;
    CGFloat fontHeight;

	[sender attributesForCharacterIndex:0 lineHeightRectangle:&lineHeightRect];
	caretPosition = [self _fixCaretPosition:lineHeightRect.origin];			
	fontHeight = lineHeightRect.size.height;		
    
    return handled;
}

@end