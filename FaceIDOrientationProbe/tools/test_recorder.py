#!/usr/bin/env python3
"""Compile the actual C recorder and forwarding bodies on host; no Apple ABI claim."""
import pathlib
import subprocess
import tempfile
import os

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "RuntimeProbe.m").read_text()
declarations = source[source.index("typedef struct { unsigned method"):source.index("static uint64_t Now")]
bodies = source[source.index("static void Observe"):source.index("static void Log")]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include <pthread.h>
#include <string.h>
typedef void *id;
typedef void *SEL;
typedef void (*IMP)(void);
static IMP gOriginal[4];
static _Atomic(bool) gEnabled;
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static unsigned gPhase;
static uint64_t tick = 1000000000ULL;
static uint64_t Now(void) { return tick; }
'''
tests = r'''
static unsigned called[4];
static uint64_t lastSet, lastAnalytics;
static id lastEvent, lastIdentities;
static uint64_t D(id self, SEL sel) { assert(self == (id)1 && sel == (SEL)2); called[0]++; return UINT64_MAX; }
static void S(id self, SEL sel, uint64_t v) { assert(self == (id)1 && sel == (SEL)2); called[1]++; lastSet = v; }
static uint64_t G(id self, SEL sel) { assert(self == (id)1 && sel == (SEL)2); called[2]++; return 42; }
static void A(id self, SEL sel, id ev, uint64_t v, id ids) { assert(self == (id)1 && sel == (SEL)2); called[3]++; lastEvent = ev; lastAnalytics = v; lastIdentities = ids; }
int main(void) {
  gOriginal[0]=(IMP)D; gOriginal[1]=(IMP)S; gOriginal[2]=(IMP)G; gOriginal[3]=(IMP)A;
  for (unsigned enabled=0; enabled<2; enabled++) {
    atomic_store(&gEnabled, enabled);
    assert(DeviceOrientation((id)1,(SEL)2)==UINT64_MAX);
    SetOrientation((id)1,(SEL)2,UINT64_MAX);
    assert(Orientation((id)1,(SEL)2)==42);
    Analytics((id)1,(SEL)2,(id)3,UINT64_MAX,(id)4);
    for(unsigned i=0;i<4;i++) assert(called[i]==enabled+1);
    assert(lastSet==UINT64_MAX && lastAnalytics==UINT64_MAX && lastEvent==(id)3 && lastIdentities==(id)4);
  }
  assert(gUsed==4);
  for(unsigned i=0;i<100;i++) Observe(0,i);
  assert(gUsed==7 && gCounts[0]==101 && gLimited[0]==97);
  pthread_mutex_lock(&gLock); Observe(0,5); pthread_mutex_unlock(&gLock);
  assert(atomic_load(&gBusyDrops)==1);
  gPhase=2; tick+=1000000000ULL; Observe(0,2);
  assert(gEvents[gUsed-1].phase==2 && gEvents[gUsed-1].value==2);
  for(unsigned sec=0;sec<100;sec++) {tick+=1000000000ULL; for(unsigned i=0;i<4;i++) Observe(i,sec);}
  assert(gUsed==64);
  atomic_store(&gEnabled,false); Observe(0,9); assert(gUsed==64);
  return 0;
}
'''
with tempfile.TemporaryDirectory(prefix="faceid-recorder-test-") as temporary:
    test = pathlib.Path(temporary) / "recorder.c"
    test.write_text(prefix + declarations + bodies + tests)
    binary = pathlib.Path(temporary) / "recorder-test"
    subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Werror", "-pthread", str(test), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print("PASS: original called once, args/returns preserved including UINT64_MAX; enable/disable, rate cap, queue cap, lock contention, phase label")
