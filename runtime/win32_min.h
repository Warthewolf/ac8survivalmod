/* Minimal hand-written Win32 declarations, so the runtime builds with nothing
 * but clang + lld-link (no Windows SDK, no C runtime). Same approach as the
 * AC8 Mod Loader's win32_min.h, trimmed to what survival_rt.c uses.          */
#ifndef WIN32_MIN_H
#define WIN32_MIN_H

#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

#define WINAPI
#define IMPORT __declspec(dllimport)

typedef void*    HANDLE;
typedef uint32_t DWORD;
typedef int32_t  BOOL;

#define INVALID_HANDLE_VALUE      ((HANDLE)(intptr_t)-1)
#define INVALID_FILE_ATTRIBUTES   0xFFFFFFFFu
#define GENERIC_WRITE             0x40000000u
#define FILE_SHARE_READ           1u
#define FILE_SHARE_WRITE          2u
#define CREATE_ALWAYS             2u
#define FILE_ATTRIBUTE_NORMAL     0x80u
#define CP_UTF8                   65001u
#define PAGE_EXECUTE_READ         0x20u
#define PAGE_EXECUTE_READWRITE    0x40u
#define PAGE_READWRITE            0x04u
#define MEM_COMMIT                0x1000u
#define MEM_RESERVE               0x2000u
#define PAGE_NOACCESS             0x01u
#define PAGE_GUARD                0x100u
#define TH32CS_SNAPTHREAD         4u
#define THREAD_SUSPEND_RESUME     0x0002u
#define THREAD_GET_CONTEXT        0x0008u
#define THREAD_QUERY_INFORMATION  0x0040u
#define CONTEXT_CONTROL           0x00100001u
#define DLL_PROCESS_ATTACH        1u
#define IMAGE_SCN_MEM_EXECUTE     0x20000000u
#define IMAGE_SCN_MEM_WRITE       0x80000000u

typedef struct {
    DWORD   dwSize;
    DWORD   cntUsage;
    DWORD   th32ThreadID;
    DWORD   th32OwnerProcessID;
    int32_t tpBasePri;
    int32_t tpDeltaPri;
    DWORD   dwFlags;
} THREADENTRY32;

typedef struct {
    uint8_t  pad0[0x30];
    DWORD    ContextFlags;
    uint8_t  pad1[0xF8 - 0x34];
    uint64_t Rip;
    uint8_t  pad2[0x4D0 - 0x100];
} __attribute__((aligned(16))) CONTEXT64;

typedef struct {
    void*    BaseAddress;
    void*    AllocationBase;
    DWORD    AllocationProtect;
    uint16_t PartitionId;
    uint16_t pad0;
    size_t   RegionSize;
    DWORD    State;
    DWORD    Protect;
    DWORD    Type;
    DWORD    pad1;
} MEMORY_BASIC_INFORMATION;

_Static_assert(sizeof(MEMORY_BASIC_INFORMATION) == 48, "MEMORY_BASIC_INFORMATION layout");
_Static_assert(sizeof(wchar_t) == 2, "wchar_t must be UTF-16");
_Static_assert(sizeof(THREADENTRY32) == 28, "THREADENTRY32 layout");
_Static_assert(sizeof(CONTEXT64) == 0x4D0, "CONTEXT size");

typedef DWORD (WINAPI *ThreadProc)(void* arg);

/* ---- KERNEL32.dll ------------------------------------------------------- */
IMPORT HANDLE WINAPI GetModuleHandleW(const wchar_t* name);
IMPORT HANDLE WINAPI LoadLibraryW(const wchar_t* name);
IMPORT DWORD  WINAPI GetLastError(void);
IMPORT void*  WINAPI GetProcAddress(HANDLE module, const char* name);
IMPORT DWORD  WINAPI GetModuleFileNameW(HANDLE module, wchar_t* buf, DWORD cap);
IMPORT BOOL   WINAPI DisableThreadLibraryCalls(HANDLE module);
IMPORT HANDLE WINAPI CreateFileW(const wchar_t* path, DWORD access, DWORD share, void* sec,
                                 DWORD disposition, DWORD flags, HANDLE templ);
IMPORT BOOL   WINAPI WriteFile(HANDLE h, const void* buf, DWORD n, DWORD* put, void* ov);
IMPORT BOOL   WINAPI FlushFileBuffers(HANDLE h);
IMPORT BOOL   WINAPI CloseHandle(HANDLE h);
IMPORT DWORD  WINAPI GetFileAttributesW(const wchar_t* path);
IMPORT int    WINAPI WideCharToMultiByte(DWORD cp, DWORD flags, const wchar_t* in, int inLen,
                                         char* out, int outCap, const char* def, BOOL* used);
IMPORT void*  WINAPI VirtualAlloc(void* addr, size_t size, DWORD type, DWORD protect);
IMPORT BOOL   WINAPI VirtualProtect(void* addr, size_t size, DWORD protect, DWORD* old);
IMPORT size_t WINAPI VirtualQuery(const void* addr, MEMORY_BASIC_INFORMATION* info, size_t size);
IMPORT BOOL   WINAPI FlushInstructionCache(HANDLE process, const void* addr, size_t size);
IMPORT HANDLE WINAPI GetCurrentProcess(void);
IMPORT DWORD  WINAPI GetCurrentProcessId(void);
IMPORT DWORD  WINAPI GetCurrentThreadId(void);
IMPORT HANDLE WINAPI CreateToolhelp32Snapshot(DWORD flags, DWORD pid);
IMPORT BOOL   WINAPI Thread32First(HANDLE snap, THREADENTRY32* te);
IMPORT BOOL   WINAPI Thread32Next(HANDLE snap, THREADENTRY32* te);
IMPORT HANDLE WINAPI OpenThread(DWORD access, BOOL inherit, DWORD tid);
IMPORT DWORD  WINAPI SuspendThread(HANDLE thread);
IMPORT DWORD  WINAPI ResumeThread(HANDLE thread);
IMPORT BOOL   WINAPI GetThreadContext(HANDLE thread, CONTEXT64* ctx);
IMPORT HANDLE WINAPI CreateThread(void* sec, size_t stack, ThreadProc fn, void* arg, DWORD flags, DWORD* id);
IMPORT void   WINAPI Sleep(DWORD ms);
IMPORT uint64_t WINAPI GetTickCount64(void);
IMPORT void   WINAPI GetLocalTime(uint16_t st[8]);

/* ---- api-ms-win-crt-heap-l1-1-0.dll (the same heap UE4SS.dll uses) ------- */
IMPORT void* malloc(size_t n);
IMPORT void  free(void* p);

/* ---- UE4SS.dll: RC::CppUserModBase constructor / destructor -------------- */
IMPORT void* UE4SS_ModBase_Ctor(void* self) __asm__("??0CppUserModBase@RC@@QEAA@XZ");
IMPORT void  UE4SS_ModBase_Dtor(void* self) __asm__("??1CppUserModBase@RC@@UEAA@XZ");

#endif /* WIN32_MIN_H */
