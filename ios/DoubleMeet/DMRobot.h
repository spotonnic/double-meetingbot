// Thin Objective-C wrapper around DRDouble (Double Basic Control SDK).
// Keeps the SDK's naming out of Swift and owns the dead-man timeout:
// if no drive/pole command arrives within 0.5 s the robot stops.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DMKickstand) {
	DMKickstandUnknown = 0,
	DMKickstandDeployed = 1,
	DMKickstandRetracted = 2,
	DMKickstandDeploying = 3,
	DMKickstandRetracting = 4
};

@protocol DMRobotDelegate <NSObject>
- (void)robotDidChange NS_SWIFT_NAME(robotDidChange());
@end

@interface DMRobot : NSObject

@property (nonatomic, weak, nullable) id<DMRobotDelegate> delegate;
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) float batteryPercent;
@property (nonatomic, readonly) BOOL batteryIsCharging;
@property (nonatomic, readonly) float poleHeightPercent;
@property (nonatomic, readonly) DMKickstand kickstand;
@property (nonatomic, readonly, nullable) NSString *firmwareVersion;
@property (nonatomic, readonly, nullable) NSString *serial;

- (void)start;
/// drive and turn are -1.0 ... 1.0. Must be repeated at least every 0.5 s while moving.
- (void)setDrive:(float)drive turn:(float)turn NS_SWIFT_NAME(setDrive(_:turn:));
/// 1 = up, -1 = down, 0 = stop. Must be repeated at least every 0.5 s while moving.
- (void)setPole:(NSInteger)direction NS_SWIFT_NAME(setPole(_:));
- (void)stop;
- (void)park;
- (void)unpark;

@end

NS_ASSUME_NONNULL_END
