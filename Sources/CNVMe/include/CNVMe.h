//
//  CNVMe.h
//  CNVMe
//
//  Reads NVMe SMART data through IOKit's IONVMeSMARTInterface plug-in (the API smartmontools uses).
//  A C shim is needed because the plug-in is a COM-style C interface.
//

#ifndef CNVME_H
#define CNVME_H

#include <stdint.h>

/// Selected fields of the NVMe SMART / Health log page.
typedef struct {
    uint8_t  criticalWarning;       ///< bit field; 0 means no warning
    uint16_t temperatureKelvin;
    uint8_t  availableSpare;        ///< percent
    uint8_t  availableSpareThreshold;
    uint8_t  percentageUsed;        ///< vendor estimate of life used; may exceed 100
    uint64_t dataUnitsRead;         ///< 1 unit = 1000 × 512 bytes
    uint64_t dataUnitsWritten;
    uint64_t powerCycles;
    uint64_t powerOnHours;
    uint64_t unsafeShutdowns;
    uint64_t mediaErrors;
} MCNVMeSMART;

/// Reads the first SMART-capable NVMe drive. Returns 1 on success, 0 if none is available.
int MCReadNVMeSMART(MCNVMeSMART *out);

#endif /* CNVME_H */
