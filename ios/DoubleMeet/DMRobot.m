#import "DMRobot.h"
#import <DoubleControlSDK/DoubleControlSDK.h>
#import <QuartzCore/QuartzCore.h>

static const CFTimeInterval kCommandTimeout = 0.5;
static const CFTimeInterval kRetractCooldown = 2.0;
static const float kMoveThreshold = 0.05f;

static float DMClamp(float v) {
	if (isnan(v)) return 0.0f;
	return fmaxf(-1.0f, fminf(1.0f, v));
}

@interface DMRobot () <DRDoubleDelegate>
@end

@implementation DMRobot {
	float _drive;
	float _turn;
	NSInteger _poleDirection;
	CFTimeInterval _lastDriveAt;
	CFTimeInterval _lastPoleAt;
	CFTimeInterval _lastRetractAt;
}

- (void)start {
	[DRDouble sharedDouble].delegate = self;
	[[DRDouble sharedDouble] requestStatusUpdate];
}

#pragma mark - Status

- (float)batteryPercent { return [DRDouble sharedDouble].batteryPercent; }
- (BOOL)batteryIsCharging { return [DRDouble sharedDouble].batteryIsCharging; }
- (float)poleHeightPercent { return [DRDouble sharedDouble].poleHeightPercent; }
- (DMKickstand)kickstand { return (DMKickstand)[DRDouble sharedDouble].kickstandState; }
- (nullable NSString *)firmwareVersion { return [DRDouble sharedDouble].firmwareVersion; }
- (nullable NSString *)serial { return [DRDouble sharedDouble].serial; }

#pragma mark - Commands

- (void)setDrive:(float)drive turn:(float)turn {
	_drive = DMClamp(drive);
	_turn = DMClamp(turn);
	_lastDriveAt = CACurrentMediaTime();

	BOOL moving = fabsf(_drive) > kMoveThreshold || fabsf(_turn) > kMoveThreshold;
	if (moving && self.kickstand == DMKickstandDeployed && _lastDriveAt - _lastRetractAt > kRetractCooldown) {
		_lastRetractAt = _lastDriveAt;
		[[DRDouble sharedDouble] retractKickstands];
	}
}

- (void)setPole:(NSInteger)direction {
	_lastPoleAt = CACurrentMediaTime();
	direction = direction > 0 ? 1 : (direction < 0 ? -1 : 0);
	if (direction == _poleDirection) return;
	_poleDirection = direction;
	if (direction > 0) {
		[[DRDouble sharedDouble] poleUp];
	} else if (direction < 0) {
		[[DRDouble sharedDouble] poleDown];
	} else {
		[[DRDouble sharedDouble] poleStop];
	}
}

- (void)stop {
	_drive = 0.0f;
	_turn = 0.0f;
	if (_poleDirection != 0) [self setPole:0];
}

- (void)park {
	[self stop];
	[[DRDouble sharedDouble] deployKickstands];
}

- (void)unpark {
	_lastRetractAt = CACurrentMediaTime();
	[[DRDouble sharedDouble] retractKickstands];
}

#pragma mark - DRDoubleDelegate

- (void)doubleDidConnect:(DRDouble *)theDouble {
	_connected = YES;
	[theDouble requestStatusUpdate];
	[self notify];
}

- (void)doubleDidDisconnect:(DRDouble *)theDouble {
	_connected = NO;
	_drive = 0.0f;
	_turn = 0.0f;
	_poleDirection = 0;
	[self notify];
}

- (void)doubleStatusDidUpdate:(DRDouble *)theDouble {
	_connected = YES;
	[self notify];
}

// Polled by the SDK continuously while the base is connected.
- (void)doubleDriveShouldUpdate:(DRDouble *)theDouble {
	CFTimeInterval now = CACurrentMediaTime();
	if (now - _lastDriveAt > kCommandTimeout) {
		_drive = 0.0f;
		_turn = 0.0f;
	}
	if (_poleDirection != 0 && now - _lastPoleAt > kCommandTimeout) {
		[self setPole:0];
	}
	[theDouble variableDrive:_drive turn:_turn];
}

- (void)notify {
	id<DMRobotDelegate> delegate = self.delegate;
	if (!delegate) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		[delegate robotDidChange];
	});
}

@end
