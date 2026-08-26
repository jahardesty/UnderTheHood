//
//  HardwareMonitorBridge.h
//  UnderTheHood
//
//  Created by Jeff on 8/25/26.
//

#import <Foundation/Foundation.h>

typedef struct {
    double cpuTempMax;
    double gpuTempMax;
    double fanSpeedRPM;
    double cpuUsage;
    double gpuUsage;
    bool fanSpeedAvailable;
} HardwareSnapshot;

@interface SystemSensorReader : NSObject
- (instancetype)init;
- (HardwareSnapshot)fetchCurrentMetrics;
@end
