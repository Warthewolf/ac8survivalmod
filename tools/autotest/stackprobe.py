"""stackprobe.py: where a running AceCombat8.exe's threads are, without a debugger: each thread's RIP and the module return
addresses found scanning its stack (from RSP up), as module+offset. A rough call chain, enough to tell a window, GPU
driver, Steam or loader wait apart. `python -I tools/autotest/stackprobe.py [pid] [--all]` (default: the game, its first
thread). Read only: each thread is suspended for the read and resumed at once."""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

k32 = ctypes.windll.kernel32
psapi = ctypes.windll.psapi
PROCESS_ALL = 0x0010 | 0x0400 | 0x0008     # VM_READ | QUERY_INFORMATION | VM_OPERATION
THREAD_ALL = 0x0002 | 0x0008 | 0x0010 | 0x0040   # SUSPEND_RESUME | GET_CONTEXT | QUERY_INFORMATION | QUERY_LIMITED
TH32CS_SNAPTHREAD = 0x4


class THREADENTRY32(ctypes.Structure):
    _fields_ = [('dwSize', wt.DWORD), ('cntUsage', wt.DWORD), ('th32ThreadID', wt.DWORD), ('th32OwnerProcessID', wt.DWORD),
                ('tpBasePri', ctypes.c_long), ('tpDeltaPri', ctypes.c_long), ('dwFlags', wt.DWORD)]


class MODULEINFO(ctypes.Structure):
    _fields_ = [('lpBaseOfDll', ctypes.c_void_p), ('SizeOfImage', wt.DWORD), ('EntryPoint', ctypes.c_void_p)]


class M128A(ctypes.Structure):
    _fields_ = [('Low', ctypes.c_ulonglong), ('High', ctypes.c_longlong)]


class CONTEXT(ctypes.Structure):
    _pack_ = 16
    _fields_ = ([('P%dHome' % i, ctypes.c_ulonglong) for i in range(1, 7)] +
                [('ContextFlags', wt.DWORD), ('MxCsr', wt.DWORD)] +
                [(n, wt.WORD) for n in ('SegCs', 'SegDs', 'SegEs', 'SegFs', 'SegGs', 'SegSs')] +
                [('EFlags', wt.DWORD)] +
                [(n, ctypes.c_ulonglong) for n in ('Dr0', 'Dr1', 'Dr2', 'Dr3', 'Dr6', 'Dr7', 'Rax', 'Rcx', 'Rdx', 'Rbx',
                                                   'Rsp', 'Rbp', 'Rsi', 'Rdi', 'R8', 'R9', 'R10', 'R11', 'R12', 'R13',
                                                   'R14', 'R15', 'Rip')] +
                [('FltSave', ctypes.c_byte * 512), ('VectorRegister', M128A * 26), ('VectorControl', ctypes.c_ulonglong),
                 ('DebugControl', ctypes.c_ulonglong), ('LastBranchToRip', ctypes.c_ulonglong),
                 ('LastBranchFromRip', ctypes.c_ulonglong), ('LastExceptionToRip', ctypes.c_ulonglong),
                 ('LastExceptionFromRip', ctypes.c_ulonglong)])


def modules(hp):
    arr = (ctypes.c_void_p * 2048)()
    need = wt.DWORD()
    psapi.EnumProcessModulesEx(hp, arr, ctypes.sizeof(arr), ctypes.byref(need), 3)
    out = []
    for i in range(need.value // ctypes.sizeof(ctypes.c_void_p)):
        if not arr[i]:
            continue
        mi = MODULEINFO()
        psapi.GetModuleInformation(hp, ctypes.c_void_p(arr[i]), ctypes.byref(mi), ctypes.sizeof(mi))
        name = ctypes.create_unicode_buffer(260)
        psapi.GetModuleBaseNameW(hp, ctypes.c_void_p(arr[i]), name, 260)
        out.append((mi.lpBaseOfDll, mi.lpBaseOfDll + mi.SizeOfImage, name.value))
    return sorted(out)


def where(mods, a):
    for lo, hi, n in mods:
        if lo <= a < hi:
            return '%s+%x' % (n, a - lo)
    return None


def threads(pid):
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
    te = THREADENTRY32()
    te.dwSize = ctypes.sizeof(te)
    out = []
    ok = k32.Thread32First(snap, ctypes.byref(te))
    while ok:
        if te.th32OwnerProcessID == pid:
            out.append(te.th32ThreadID)
        ok = k32.Thread32Next(snap, ctypes.byref(te))
    k32.CloseHandle(snap)
    return out


def probe(pid, all_threads=False, depth=0x8000, show=24):
    hp = k32.OpenProcess(PROCESS_ALL, False, pid)
    if not hp:
        return ['cannot open the process %d' % pid]
    mods = modules(hp)
    lines = ['modules: %d' % len(mods)]
    tids = threads(pid)
    for n, tid in enumerate(tids if all_threads else tids[:1]):
        ht = k32.OpenThread(THREAD_ALL, False, tid)
        if not ht:
            lines.append('thread %d: cannot open' % tid)
            continue
        ctx = CONTEXT()
        ctx.ContextFlags = 0x100003          # CONTEXT_AMD64 | CONTROL | INTEGER
        k32.SuspendThread(ht)
        try:
            k32.GetThreadContext(ht, ctypes.byref(ctx))
            buf = ctypes.create_string_buffer(depth)
            got = ctypes.c_size_t()
            k32.ReadProcessMemory(hp, ctypes.c_void_p(ctx.Rsp), buf, depth, ctypes.byref(got))
        finally:
            k32.ResumeThread(ht)
            k32.CloseHandle(ht)
        chain = []
        for off in range(0, got.value - 7, 8):
            v = struct.unpack_from('<Q', buf.raw, off)[0]
            w = where(mods, v)
            if w and (not chain or chain[-1] != w):
                chain.append(w)
            if len(chain) >= show:
                break
        lines.append('thread %d (#%d): rip %s; stack: %s' % (tid, n, where(mods, ctx.Rip) or hex(ctx.Rip), ' < '.join(chain)))
    k32.CloseHandle(hp)
    return lines


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    pid = int(args[0]) if args else (C.pids_of(C.GAME_EXE) or [0])[0]
    for line in probe(pid, '--all' in sys.argv):
        print(line)
