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
    int batteryCycleCount;
    char batteryHealth[32]; // null-terminated string for health status, e.g. "Good"
    bool batteryPresent;
    char chipModel[64]; // null-terminated string for the chip/CPU model, e.g. "Apple M1 Pro"
} HardwareSnapshot;

@interface SystemSensorReader : NSObject
- (instancetype)init;
- (HardwareSnapshot)fetchCurrentMetrics;
@end

