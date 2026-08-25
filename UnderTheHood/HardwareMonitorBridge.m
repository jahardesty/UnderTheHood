//
//  HardwareMonitorBridge.m
//  UnderTheHood
//
//  Created by Jeff on 8/25/26.
//

#import "HardwareMonitorBridge.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

typedef struct {
    char major;
    char minor;
    char build;
    char reserved;
    UInt16 release;
} SMCVersion;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} SMCPowerLimitData;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    UInt8 dataAttributes;
} SMCKeyInfo;

typedef struct {
    UInt32 key;
    SMCVersion version;
    SMCPowerLimitData powerLimitData;
    SMCKeyInfo keyInfo;
    UInt16 padding;
    UInt8 result;
    UInt8 status;
    UInt8 data8;
    UInt32 data32;
    UInt8 bytes[32];
} SMCParamStruct;

FOUNDATION_EXPORT IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
FOUNDATION_EXPORT void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
FOUNDATION_EXPORT CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
FOUNDATION_EXPORT IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t matching, int64_t options);
FOUNDATION_EXPORT double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kIOHIDEventTypeTemperature 15
#define kIOHIDEventFieldTemperatureLevel (kIOHIDEventTypeTemperature << 16)
#define kSMCUserClientOpen 0
#define kSMCHandleYPCEvent 2
#define kSMCReadKeyInfo 9
#define kSMCReadBytes 5

static UInt32 FourCharCodeFromCString(const char *string) {
    return ((UInt32)string[0] << 24) | ((UInt32)string[1] << 16) | ((UInt32)string[2] << 8) | (UInt32)string[3];
}

static BOOL SensorNameHasPrefix(NSString *name, NSString *prefix) {
    return [name rangeOfString:prefix options:NSCaseInsensitiveSearch | NSAnchoredSearch].location != NSNotFound;
}

static BOOL SensorNameContains(NSString *name, NSString *substring) {
    return [name rangeOfString:substring options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL IsCPUTemperatureSensor(NSString *name) {
    return SensorNameHasPrefix(name, @"pACC MTR Temp Sensor") ||
           SensorNameHasPrefix(name, @"eACC MTR Temp Sensor") ||
           SensorNameContains(name, @"CPU") ||
           SensorNameHasPrefix(name, @"PMU tdie") ||
           SensorNameHasPrefix(name, @"TSCD") ||
           SensorNameHasPrefix(name, @"Ts2z") ||
           SensorNameHasPrefix(name, @"Tp") ||
           SensorNameHasPrefix(name, @"Te0");
}

static BOOL IsGPUTemperatureSensor(NSString *name) {
    return SensorNameHasPrefix(name, @"GPU MTR Temp Sensor") ||
           SensorNameHasPrefix(name, @"PMU tdev") ||
           SensorNameContains(name, @"GPU") ||
           SensorNameHasPrefix(name, @"Tg");
}

static kern_return_t SMCReadKey(io_connect_t connection, const char *key, SMCParamStruct *output) {
    SMCParamStruct input = {0};
    size_t inputSize = sizeof(SMCParamStruct);
    size_t outputSize = sizeof(SMCParamStruct);

    input.key = FourCharCodeFromCString(key);
    input.data8 = kSMCReadKeyInfo;

    kern_return_t result = IOConnectCallStructMethod(connection, kSMCHandleYPCEvent, &input, inputSize, output, &outputSize);
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (output->result != 0) {
        return kIOReturnError;
    }

    SMCKeyInfo keyInfo = output->keyInfo;
    input.keyInfo.dataSize = keyInfo.dataSize;
    input.keyInfo.dataType = keyInfo.dataType;
    input.data8 = kSMCReadBytes;
    outputSize = sizeof(SMCParamStruct);

    result = IOConnectCallStructMethod(connection, kSMCHandleYPCEvent, &input, inputSize, output, &outputSize);
    output->keyInfo = keyInfo;
    if (result == KERN_SUCCESS && output->result != 0) {
        return kIOReturnError;
    }
    return result;
}

static double SMCFanRPMValue(SMCParamStruct value) {
    if (value.keyInfo.dataSize == 4) {
        float rpm = 0;
        memcpy(&rpm, value.bytes, sizeof(float));
        return rpm;
    }

    return ((double)(((UInt16)value.bytes[0] << 8) | value.bytes[1])) / 4.0;
}

@implementation SystemSensorReader {
    IOHIDEventSystemClientRef hidClient;
    io_connect_t smcConnection;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        hidClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        NSDictionary *matching = @{ @"PrimaryUsagePage": @(0xff00), @"PrimaryUsage": @(0x5) };
        IOHIDEventSystemClientSetMatching(hidClient, (__bridge CFDictionaryRef)matching);
        
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
        if (!service) {
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
        }
        if (service) {
            IOServiceOpen(service, mach_task_self_, kSMCUserClientOpen, &smcConnection);
            IOObjectRelease(service);
        }
    }
    return self;
}

- (HardwareSnapshot)fetchCurrentMetrics {
    HardwareSnapshot snapshot = {0};
    
    // Query IOHID event system for Apple Silicon PMU sensor channels
    CFArrayRef services = IOHIDEventSystemClientCopyServices(hidClient);
    if (services) {
        CFIndex count = CFArrayGetCount(services);
        for (CFIndex i = 0; i < count; i++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
            CFTypeRef productProperty = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
            NSString *productName = nil;
            if (productProperty) {
                if (CFGetTypeID(productProperty) == CFStringGetTypeID()) {
                    productName = CFBridgingRelease(productProperty);
                } else {
                    CFRelease(productProperty);
                }
            }
            
            if (productName) {
                IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
                if (event) {
                    double temp = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel);
                    if (IsCPUTemperatureSensor(productName) && temp > snapshot.cpuTempMax) {
                        snapshot.cpuTempMax = temp;
                    } else if (IsGPUTemperatureSensor(productName) && temp > snapshot.gpuTempMax) {
                        snapshot.gpuTempMax = temp;
                    }
                    CFRelease(event);
                }
            }
        }
        CFRelease(services);
    }

    if (smcConnection) {
        SMCParamStruct fanValue = {0};
        if (SMCReadKey(smcConnection, "F0Ac", &fanValue) == KERN_SUCCESS) {
            snapshot.fanSpeedRPM = SMCFanRPMValue(fanValue);
            snapshot.fanSpeedAvailable = true;
        }
    }
    
    return snapshot;
}

- (void)dealloc {
    if (hidClient) CFRelease(hidClient);
    if (smcConnection) IOServiceClose(smcConnection);
}

@end
