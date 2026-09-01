//
//  HardwareMonitorBridge.m
//  UnderTheHood
//
//  Created by Jeff on 8/25/26.
//

#import "HardwareMonitorBridge.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>
#import <mach/mach_host.h>
#import <IOKit/ps/IOPowerSources.h>
#include <sys/sysctl.h>

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
        //kern_return_t openResult = KERN_FAILURE;
        if (service) {
            IOServiceOpen(service, mach_task_self_, kSMCUserClientOpen, &smcConnection);
            IOObjectRelease(service);
        }
       // NSLog(@"IOServiceOpen returned %d, smcConnection = %u", openResult, smcConnection);
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
        // --- Fan Speed Aggregation ---
        const char *fanKeys[] = {"F0Ac", "F1Ac", "F2Ac", "F3Ac"};
        double totalFanRPM = 0;
        int fanCount = 0;
        for (int i = 0; i < 4; i++) {
            SMCParamStruct fanValue = {0};
            if (SMCReadKey(smcConnection, fanKeys[i], &fanValue) == KERN_SUCCESS) {
                double rpm = SMCFanRPMValue(fanValue);
                NSLog(@"Fan key %s: %.1f RPM", fanKeys[i], rpm);
                if (rpm > 0) {
                    totalFanRPM += rpm;
                    fanCount++;
                }
            } else {
                NSLog(@"Fan key %s: unavailable", fanKeys[i]);
            }
        }
        if (fanCount > 0) {
            snapshot.fanSpeedRPM = totalFanRPM;
            snapshot.fanSpeedAvailable = true;
        } else {
            snapshot.fanSpeedRPM = 0;
            snapshot.fanSpeedAvailable = false;
        }
        // --- End Fan Speed Aggregation ---
    }
    
    // --- CPU Usage Calculation ---
    static uint64_t lastTotalTicks = 0, lastIdleTicks = 0;
    uint64_t totalTicks = 0, idleTicks = 0;
    
    natural_t cpuCount;
    processor_info_array_t cpuInfo;
    mach_msg_type_number_t numCpuInfo;
    kern_return_t kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfo, &numCpuInfo);
    
    if (kr == KERN_SUCCESS) {
        for (natural_t i = 0; i < cpuCount; i++) {
            integer_t *cpu = (integer_t *)(cpuInfo + (CPU_STATE_MAX * i));
            idleTicks += cpu[CPU_STATE_IDLE];
            totalTicks += cpu[CPU_STATE_IDLE] + cpu[CPU_STATE_USER] + cpu[CPU_STATE_SYSTEM] + cpu[CPU_STATE_NICE];
        }
        static BOOL first = YES;
        if (first) {
            first = NO;
            lastTotalTicks = totalTicks;
            lastIdleTicks = idleTicks;
            snapshot.cpuUsage = 0;
        } else {
            uint64_t totalDelta = totalTicks - lastTotalTicks;
            uint64_t idleDelta = idleTicks - lastIdleTicks;
            if (totalDelta > 0) {
                snapshot.cpuUsage = 100.0 * (double)(totalDelta - idleDelta) / (double)totalDelta;
            } else {
                snapshot.cpuUsage = 0;
            }
            lastTotalTicks = totalTicks;
            lastIdleTicks = idleTicks;
        }
        vm_deallocate(mach_task_self(), (vm_address_t)cpuInfo, numCpuInfo * sizeof(integer_t));
    } else {
        snapshot.cpuUsage = 0;
    }
    // --- End CPU Usage Calculation ---
    
    // --- Battery Info Retrieval ---
    snapshot.batteryPresent = false;
    io_service_t batteryService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (batteryService) {
        CFDictionaryRef batteryPropertiesRef = NULL;
        if (IORegistryEntryCreateCFProperties(batteryService, (CFMutableDictionaryRef *)&batteryPropertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS && batteryPropertiesRef) {
            NSDictionary *batteryProperties = CFBridgingRelease(batteryPropertiesRef);
            NSNumber *cycleCountNum = batteryProperties[@"CycleCount"];
            NSString *batteryHealthStr = batteryProperties[@"BatteryHealth"];
            
            if (cycleCountNum != nil && [cycleCountNum isKindOfClass:[NSNumber class]]) {
                snapshot.batteryCycleCount = [cycleCountNum intValue];
            }
            if (batteryHealthStr != nil && [batteryHealthStr isKindOfClass:[NSString class]]) {
                strncpy(snapshot.batteryHealth, [batteryHealthStr UTF8String], 31);
                snapshot.batteryHealth[31] = '\0';
            } else {
                snapshot.batteryHealth[0] = '\0';
            }
            snapshot.batteryPresent = true;
        }
        IOObjectRelease(batteryService);
    }
    
    // --- End Battery Info Retrieval ---
    
    char brandString[64] = "";
    size_t size = sizeof(brandString);
    if (sysctlbyname("machdep.cpu.brand_string", &brandString, &size, NULL, 0) == 0) {
        strncpy(snapshot.chipModel, brandString, 63);
        snapshot.chipModel[63] = '\0';
    } else {
        snapshot.chipModel[0] = '\0';
    }
    
    return snapshot;
}

- (void)dealloc {
    if (hidClient) CFRelease(hidClient);
    if (smcConnection) IOServiceClose(smcConnection);
}

@end

