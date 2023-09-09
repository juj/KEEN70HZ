// BENCHVS.CPP: JukkaJ: Benchmark the vertical refresh rate and hblank
//                      length.

#include <dos.h>
#include "benchvs.h"

unsigned char VideoRefreshRate = 70;
unsigned char VideoRefreshRateIs70Hz = 1;
unsigned char MaxHblankLength = 15;

typedef void (interrupt far *INTERRUPT_PROC)(void);
static void SetTimerIntr(INTERRUPT_PROC handler, int interval)
{
  SREGS s;
  REGS r;
  disable();
  segread(&s);
  s.ds = FP_SEG(handler);
  r.x.ax = 0x2508;
  r.x.dx = FP_OFF(handler);
  int86x(0x21, &r, &r, &s); // Install our timer interrupt handler
  // Set new timer resolution for PIT #0 (DOS default timer is 18.2065hz)
  // Mode register: 00b: Select channel 0, 11b: Access lo+hi bytes,
  //                011b: Square wave, 0b: 16-bit binary mode
  outp(0x43, 0x36); // 0x36=00110110b
  outp(0x40, interval);
  outp(0x40, interval >> 8);
  enable();
}

static volatile long TimeMsecs = 0;
static void interrupt far TimerHandler() { ++TimeMsecs; outp(0x20, 0x20); }

extern "C" void SDL_SetTimerSpeed(void);

static void CalibrateMaxHblankLength()
{
  int i;
  MaxHblankLength = 0;
  // Benchmark: What is the maximum amount of port I/Os that can be
  // performed within a single hblank period?
  // Find what is the max length that a Hblank can take.
  for(i = 0; i < 1000; ++i)
  {
    int length = 0;
    unsigned char status, seen_status = 0;
    disable();
    while(inportb(0x3DA) & 9);
    while(!(inportb(0x3DA) & 9));
    do
    {
      status = inportb(0x3DA);
      seen_status |= status;
      ++length;
    } while((status & 9) == 1);
    enable();
    if (!(seen_status & 8) && length > MaxHblankLength)
      MaxHblankLength = length;
  }
  MaxHblankLength += 5; // For good measure, give a few more I/Os extra
}

extern "C" void BenchmarkVideoRefreshRate()
{
  INTERRUPT_PROC prevTimerProc;
  int i;
  long t;
  SREGS s;
  REGS r;
  // Install msec-granular timer
  disable();
  segread(&s);
  r.x.ax = 0x3508;
  int86x(0x21, &r, &r, &s); // Save original DOS timer interrupt vector
  prevTimerProc = (INTERRUPT_PROC)MK_FP(s.es, r.x.bx);
  SetTimerIntr(TimerHandler, 298); // 1193182/298 = 4000 times/second
  enable();
  // Measure duration of 10 vblanks
  while(inp(0x3DA)&8); while(!(inp(0x3DA)&8));
  t = TimeMsecs;
  for(i = 0; i < 10; ++i) { while(inp(0x3DA)&8); while(!(inp(0x3DA)&8)); }
  t = TimeMsecs + 1 - t;
  // Uninstall msec-granular timer
  SetTimerIntr(prevTimerProc, 0);
  SDL_SetTimerSpeed(); // Restore previous timer speed since we overwrote it above
  VideoRefreshRate = (40000l+(t>>1))/t;
  VideoRefreshRateIs70Hz = (VideoRefreshRate >= 67 && VideoRefreshRate <= 73);

  CalibrateMaxHblankLength();
}
