//
//  CNVMe.c
//  CNVMe
//

#include "CNVMe.h"
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>

/// The 128-bit counters of the log page are read as their low 64 bits, which is far beyond any real value.
int MCReadNVMeSMART(MCNVMeSMART *out) {
    if (out == NULL) return 0;
    memset(out, 0, sizeof(*out));

    CFMutableDictionaryRef match = IOServiceMatching("IOService");
    if (match == NULL) return 0;
    CFMutableDictionaryRef properties = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                                                  &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(properties, CFSTR(kIOPropertyNVMeSMARTCapableKey), kCFBooleanTrue);
    CFDictionarySetValue(match, CFSTR(kIOPropertyMatchKey), properties);
    CFRelease(properties);

    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) != KERN_SUCCESS) return 0;

    int success = 0;
    io_service_t service;
    while (!success && (service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        if (IOCreatePlugInInterfaceForService(service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID,
                                              &plugin, &score) == kIOReturnSuccess && plugin != NULL) {
            IONVMeSMARTInterface **smart = NULL;
            HRESULT result = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
            if (result == S_OK && smart != NULL) {
                NVMeSMARTData data;
                memset(&data, 0, sizeof(data));
                if ((*smart)->SMARTReadData(smart, &data) == kIOReturnSuccess) {
                    out->criticalWarning = data.CRITICAL_WARNING;
                    out->temperatureKelvin = data.TEMPERATURE;
                    out->availableSpare = data.AVAILABLE_SPARE;
                    out->availableSpareThreshold = data.AVAILABLE_SPARE_THRESHOLD;
                    out->percentageUsed = data.PERCENTAGE_USED;
                    out->dataUnitsRead = data.DATA_UNITS_READ[0];
                    out->dataUnitsWritten = data.DATA_UNITS_WRITTEN[0];
                    out->powerCycles = data.POWER_CYCLES[0];
                    out->powerOnHours = data.POWER_ON_HOURS[0];
                    out->unsafeShutdowns = data.UNSAFE_SHUTDOWNS[0];
                    out->mediaErrors = data.MEDIA_ERRORS[0];
                    success = 1;
                }
                (*smart)->Release(smart);
            }
            IODestroyPlugInInterface(plugin);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return success;
}
