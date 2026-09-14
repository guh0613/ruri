#!/usr/bin/env python3
"""Measure a Release monitor in disposable sessions without launching Minecraft.

Usage: python3 scripts/monitor-benchmark.py [--helper path] [--debug]
CPU uses Mach timebase conversion; 100% denotes one CPU core. File sizes are
logical bytes, not SSD writes. Every fixture and its processes are cleaned up.
"""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time
import uuid


class Timebase(C.Structure):
    _fields_ = [("numer", C.c_uint32), ("denom", C.c_uint32)]


FIELDS = "user system idle_wake interrupt_wake pageins wired rss footprint start exit child_user child_system child_idle child_interrupt child_pageins child_elapsed diskread diskwritten".split()


class Usage(C.Structure):
    _fields_ = [("uuid", C.c_ubyte * 16)] + [(name, C.c_uint64) for name in FIELDS]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", type=Path, default=Path(".build/validation/release/ruri-monitor"))
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This benchmark requires macOS.")
    helper = args.helper.resolve(strict=True)
    lib = C.CDLL("/usr/lib/libproc.dylib")
    tb = Timebase()
    C.CDLL("/usr/lib/libSystem.B.dylib").mach_timebase_info(C.byref(tb))
    seconds_per_tick = tb.numer / tb.denom / 1e9

    def identity(pid):
        buffer = C.create_string_buffer(136)
        if lib.proc_pidinfo(pid, 3, 0, buffer, 136) != 136:
            return None
        seconds, micros = struct.unpack_from("QQ", buffer.raw, 120)
        return dict(pid=pid, startSeconds=seconds, startMicroseconds=micros)

    def sample(pid):
        usage = Usage()
        if lib.proc_pid_rusage(pid, 2, C.byref(usage)):
            return None
        return dict(cpu=(usage.user + usage.system) * seconds_per_tick,
                    rss=usage.rss / 2**20, footprint=usage.footprint / 2**20)

    for name, rate, burst in [("idle", 0, 0), ("1000_lines_per_second", 1000, 0), ("burst_100000_lines", 0, 100000)]:
        with tempfile.TemporaryDirectory(prefix="ruri-monitor-benchmark-") as temporary:
            root = Path(temporary).resolve()
            iid, sid = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
            game = root / "instances" / iid / "minecraft"
            directory = root / "instances" / iid / "sessions" / sid
            game.mkdir(parents=True)
            directory.mkdir(parents=True)
            log = directory / "launcher.log"
            log.touch()
            session = directory / "session.json"
            process = subprocess.Popen([str(helper), "run"], stdin=subprocess.PIPE,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                owner = identity(process.pid)
                assert owner is not None
                now = time.time() - 978307200  # Foundation's reference date.
                record = dict(schema=1, id=sid, instanceID=iid, instanceName="Synthetic monitor benchmark",
                              gameVersion="fixture", loader="vanilla", memoryMB=1024,
                              operatingSystem="macOS", hostArchitecture="aarch64", accountMode="offline",
                              ownerPID=os.getpid(), createdAt=now, updatedAt=now, state="preparing",
                              stage="starting", monitorIdentity=owner, events=[], evidence=[])
                session.write_text(json.dumps(record))
                code = f'''import os,time,pathlib
line=b"[Render thread/INFO] synthetic log "+b"x"*165+b"\\n"
time.sleep(1)
if {burst}:
 for i in range({burst}//100): os.write(1,line*100)
 time.sleep(8)
else:
 start=time.monotonic()
 for i in range(60):
  if {rate}: os.write(1,line*({rate}//10))
  time.sleep(max(0,start+(i+1)*0.1-time.monotonic()))
 time.sleep(1)
pathlib.Path('logs').mkdir(exist_ok=True)
pathlib.Path('logs/latest.log').write_text('synthetic latest log\\n'*100)
'''
                plan = dict(executable=Path(sys.executable).resolve().as_uri(), arguments=["-c", code],
                            directory=game.as_uri() + "/", environment={"PATH": "/bin:/usr/bin", "PYTHONDONTWRITEBYTECODE": "1"},
                            debugLogging=args.debug)
                request = dict(version=1, root=root.as_uri() + "/", instanceID=iid, sessionID=sid,
                               monitor=owner, plan=plan, secrets=["synthetic-access-secret", "synthetic-refresh-secret"],
                               language="zh-Hans", region="CN")
                process.stdin.write(json.dumps(request).encode())
                process.stdin.close()
                start = time.monotonic()
                samples = []
                while process.poll() is None and time.monotonic() - start < 40:
                    value = sample(process.pid)
                    if value:
                        samples.append((time.monotonic() - start, value))
                    time.sleep(.05)
                if process.poll() is None:
                    raise RuntimeError("Monitor timed out")
                final = json.loads(session.read_text())
                if process.returncode != 0 or final["state"] != "succeeded":
                    raise RuntimeError(final.get("failure", "Fixture did not succeed"))
                steady = [(t, u) for t, u in samples if 1.5 < t < 6.5]
                first, last = steady[0], steady[-1]
                peak = max((u["cpu"] - v["cpu"]) / (t - s) * 100
                           for i, (t, u) in enumerate(samples)
                           for s, v in samples[max(0, i-20):max(0, i-19)] if t-s >= .8)
                print(json.dumps(dict(case=name, debug=args.debug,
                                      steady_cpu_percent=round((last[1]["cpu"]-first[1]["cpu"])/(last[0]-first[0])*100, 3),
                                      peak_one_second_cpu_percent=round(peak, 2),
                                      peak_rss_mib=round(max(u["rss"] for _, u in samples), 2),
                                      peak_footprint_mib=round(max(u["footprint"] for _, u in samples), 2),
                                      last_rss_mib=round(samples[-1][1]["rss"], 2),
                                      monitor_cpu_seconds=round(samples[-1][1]["cpu"], 3),
                                      launcher_log_bytes=log.stat().st_size,
                                      report_copy_bytes=sum(p.stat().st_size for p in (directory / "reports").glob("*") if p.is_file()))), flush=True)
            finally:
                if process.poll() is None:
                    # Only terminate the fixture child whose kernel identity we recorded.
                    try:
                        child = json.loads(session.read_text()).get("gameIdentity")
                        if child and identity(child["pid"]) == child:
                            os.kill(child["pid"], signal.SIGKILL)
                    finally:
                        process.kill()
                        process.wait()


if __name__ == "__main__":
    main()
