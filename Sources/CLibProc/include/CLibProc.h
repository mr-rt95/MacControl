//
//  CLibProc.h
//  CLibProc
//
//  Exposes libproc to Swift. The Darwin module map does not include <libproc.h>,
//  so this tiny C target re-exports it (process listing and per-process resource usage).
//

#ifndef CLIBPROC_H
#define CLIBPROC_H

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>

#endif /* CLIBPROC_H */
