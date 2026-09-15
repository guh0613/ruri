#!/usr/bin/env python3
"""Measure Release monitor overhead using disposable synthetic games.

Build ruri-monitor and ruri-cli in the same Release directory first.
Usage: python3 scripts/monitor-benchmark.py [--helper path] [--debug] [--checkpoint]
100% CPU means one core. File sizes and sampled process I/O are not SSD wear.
The CLI initializes an empty current-format DB; Python supplies a launch row
just as the GUI would. Their setup work is excluded from monitor accounting.
"""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import signal
import sqlite3
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
    parser.add_argument("--checkpoint", action="store_true", help="One 75-second idle fixture with a real minute checkpoint")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This benchmark requires macOS.")
    helper = args.helper.resolve(strict=True)
    cli = helper.with_name("ruri-cli").resolve(strict=True)
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
                    rss=usage.rss / 2**20, footprint=usage.footprint / 2**20,
                    idle_wakeups=usage.idle_wake, disk_written=usage.diskwritten)

    cases = [("idle_75_seconds", 0, 0)] if args.checkpoint else [("idle", 0, 0), ("1000_lines_per_second", 1000, 0), ("burst_100000_lines", 0, 100000)]
    for name, rate, burst in cases:
        with tempfile.TemporaryDirectory(prefix="ruri-monitor-benchmark-") as temporary:
            root = Path(temporary).resolve()
            iid, sid = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
            game = root / "instances" / iid / "minecraft"
            directory = root / "instances" / iid / "diagnostics" / sid
            game.mkdir(parents=True)
            subprocess.run([str(cli), "sessions"], check=True, stdout=subprocess.DEVNULL,
                           env={"RURI_DATA_DIR": str(root), "PATH": "/bin:/usr/bin"}, timeout=20)
            file = root / "records" / "records.sqlite"
            database = sqlite3.connect(file, timeout=2)
            process = subprocess.Popen([str(helper), "run"], stdin=subprocess.PIPE,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            last_record = None
            endpoint = None

            def load_record():
                nonlocal last_record, endpoint
                row = database.execute("SELECT payload,timing,revision,observed,endpoint FROM sessions WHERE id=?", (sid,)).fetchone()
                if row:
                    record = json.loads(row[0])
                    record["timing"] = json.loads(row[1]) if row[1] else None
                    record["revision"], record["updatedAt"], record["controlEndpoint"] = row[2:]
                    last_record = record
                    endpoint = row[4] or endpoint
                return last_record

            try:
                owner = identity(process.pid)
                assert owner is not None
                now = time.time() - 978307200
                record = dict(schema=1, id=sid, instanceID=iid, instanceName="Synthetic monitor benchmark",
                              gameVersion="fixture", loader="vanilla", memoryMB=1024,
                              operatingSystem="macOS", hostArchitecture="aarch64", accountMode="offline",
                              ownerPID=os.getpid(), createdAt=now, updatedAt=now, state="preparing", stage="starting",
                              monitorIdentity=owner, events=[], evidence=[], revision=1, finalSnapshot=False, debugLogging=args.debug)
                database.execute("""INSERT INTO sessions(id,instance_id,name,game_version,created,started,updated,seconds,played,attention,finished,revision,payload,observed)
                                    VALUES(?,?,?,?,?,?,?,0,0,0,0,1,?,?)""",
                                 (sid, iid, record["instanceName"], "fixture", now+978307200, now+978307200, now+978307200,
                                  json.dumps(record).encode(), now))
                database.commit()
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
 time.sleep({68 if args.checkpoint else 1})
pathlib.Path('logs').mkdir(exist_ok=True)
pathlib.Path('logs/latest.log').write_text('synthetic latest log\\n'*100)
'''
                plan = dict(executable=Path(sys.executable).resolve().as_uri(), arguments=["-c", code],
                            directory=game.as_uri() + "/", environment={"PATH": "/bin:/usr/bin", "PYTHONDONTWRITEBYTECODE": "1"},
                            debugLogging=args.debug)
                default_id = "00000000-0000-0000-0000-000000000000"
                storage = dict(root=root.as_uri()+"/", directories=[], newInstanceDirectoryID=default_id,
                               instanceDirectories=[iid, default_id], instanceRunDirectories=[iid, "isolated"])
                request = dict(version=1, instanceID=iid, sessionID=sid, monitor=owner, plan=plan, storage=storage,
                               secrets=["synthetic-access-secret", "synthetic-refresh-secret"], language="zh-Hans", region="CN")
                process.stdin.write(json.dumps(request).encode())
                process.stdin.close()
                start = time.monotonic()
                samples, baseline, checkpoint_measured = [], None, False
                while process.poll() is None and time.monotonic() - start < (100 if args.checkpoint else 40):
                    value = sample(process.pid)
                    if value:
                        t = time.monotonic() - start
                        samples.append((t, value))
                        current = load_record()
                        if args.checkpoint and t >= 10 and baseline is None:
                            baseline = (t, value)
                        if args.checkpoint and t >= 72 and not checkpoint_measured:
                            assert current["state"] == "running" and (current.get("timing") or {}).get("awakeSeconds", 0) >= 50, current
                            t0, u0 = baseline
                            print(json.dumps(dict(case="checkpoint_interval", elapsed=round(t-t0, 3),
                                sampled_disk_written_bytes=value["disk_written"]-u0["disk_written"],
                                monitor_cpu_seconds=round(value["cpu"]-u0["cpu"], 6),
                                cpu_percent=round((value["cpu"]-u0["cpu"])/(t-t0)*100, 5))), flush=True)
                            checkpoint_measured = True
                    time.sleep(.05)
                if process.poll() is None:
                    raise RuntimeError("Monitor timed out")
                final = load_record()
                if process.returncode != 0 or final["state"] != "succeeded":
                    raise RuntimeError(dict(returncode=process.returncode, record=final))
                assert not directory.joinpath("session.json").exists()
                if not args.debug:
                    assert not directory.exists(), "Ordinary success created duplicate diagnostic files"
                if args.checkpoint:
                    assert checkpoint_measured
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
                                      monitor_cpu_seconds=round(samples[-1][1]["cpu"], 3),
                                      console_log_bytes=sum(p.stat().st_size for p in directory.glob("console*.log")),
                                      history_bytes=sum(p.stat().st_size for p in file.parent.glob("*") if p.is_file()),
                                      sampled_idle_wakeups=samples[-1][1]["idle_wakeups"],
                                      sampled_disk_written_bytes=samples[-1][1]["disk_written"],
                                      report_copy_bytes=sum(p.stat().st_size for p in (directory / "reports").glob("*") if p.is_file()))), flush=True)
            finally:
                try:
                    current = load_record() or {}
                    child = current.get("gameIdentity")
                    if child and identity(child["pid"]) == child:
                        os.kill(child["pid"], signal.SIGKILL)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    database.close()
                    if endpoint and endpoint.startswith("/tmp/ruri-monitor-") and Path(endpoint).name == "control.sock":
                        Path(endpoint).unlink(missing_ok=True)
                        try:
                            Path(endpoint).parent.rmdir()
                        except OSError:
                            pass


if __name__ == "__main__":
    main()
