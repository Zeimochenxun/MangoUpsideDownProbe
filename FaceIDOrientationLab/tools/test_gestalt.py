#!/usr/bin/env python3
"""Compile the exact MobileGestalt wrappers with simple host CoreFoundation mocks."""
import pathlib
import subprocess
import tempfile

source = (pathlib.Path(__file__).resolve().parents[1] / 'RuntimeLab.m').read_text()
keys = source[source.index('static const CFStringRef kMGKeys[]'):source.index('#endif', source.index('static const CFStringRef kMGKeys[]'))]
wrappers = source[source.index('static void ObserveMG'):source.index('#endif', source.index('static void ObserveMG'))]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include <string.h>
typedef const char *CFStringRef;
typedef void *CFDictionaryRef;
typedef void *CFTypeRef;
#define CFSTR(x) x
static unsigned CFGetTypeID(CFStringRef s) { return s ? 1 : 0; }
static unsigned CFStringGetTypeID(void) { return 1; }
static bool CFEqual(CFStringRef a, CFStringRef b) { return strcmp(a,b)==0; }
static _Atomic(bool) gEnabled;
static unsigned seen[9], lastKey;
static uintptr_t lastCaller;
static void Observe(unsigned method, uint64_t value, uintptr_t caller) { seen[method]++; lastKey=(unsigned)value; lastCaller=caller; }
static CFTypeRef (*gCopyAnswer)(CFStringRef, CFDictionaryRef);
static bool (*gBoolAnswer)(CFStringRef);
'''
tests = r'''
static unsigned copyCalls, boolCalls;
static CFDictionaryRef lastOptions;
static CFTypeRef OriginalCopy(CFStringRef key, CFDictionaryRef options) {
  assert(key); copyCalls++; lastOptions=options; return (CFTypeRef)(uintptr_t)0x6789;
}
static bool OriginalBool(CFStringRef key) { assert(key); boolCalls++; return true; }
int main(void) {
  gCopyAnswer=OriginalCopy; gBoolAnswer=OriginalBool;
  atomic_store(&gEnabled,true);
  assert(CopyAnswer("DeviceClass",(CFDictionaryRef)0x33)==(CFTypeRef)(uintptr_t)0x6789);
  assert(copyCalls==1 && lastOptions==(CFDictionaryRef)0x33 && seen[7]==1 && lastKey==0 && lastCaller!=0);
  assert(BoolAnswer("eP/CPXY0Q1CoIqAWn/J97g") && boolCalls==1 && seen[8]==1 && lastKey==7);
  assert(strcmp(kMGNames[lastKey],"eP/CPXY0Q1CoIqAWn/J97g")==0);
  assert(BoolAnswer("NotAllowed") && boolCalls==2 && seen[8]==1);
  atomic_store(&gEnabled,false);
  assert(CopyAnswer("DeviceClass",NULL)==(CFTypeRef)(uintptr_t)0x6789 && copyCalls==2 && seen[7]==1);
  return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='faceid-gestalt-test-') as temporary:
    path = pathlib.Path(temporary) / 'gestalt.c'
    path.write_text(prefix + keys + wrappers + tests)
    binary = pathlib.Path(temporary) / 'gestalt-test'
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('PASS: MobileGestalt original return and arguments preserved; only allow-listed queries observed; disabled state forwards')
