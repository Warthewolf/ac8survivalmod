"""store_recycle_cut.py OUT.c : cuts the runtime's deferred unit destroys (survival_rt_game.c: RcEntry .. RcDrain, Recycle)
and the STORE freeze's hooks (flight_guards.c: MgListFn .. OnMgRestore) out of the real sources into one file, for
tools/checks/store_recycle_test.c to compile against its stubs. Fails if a marker moved."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "runtime"


def cut(name, start, end):
    text = (ROOT / name).read_text(encoding="utf-8")
    a = text.find(start)
    b = text.find(end, a + 1)
    if a < 0 or b < 0:
        sys.exit("store_recycle_cut: a marker of %s not found (%r .. %r)" % (name, start, end))
    return "/* ---- cut from runtime/%s ---- */\n%s\n" % (name, text[a:b])


def main():
    parts = [
        cut("survival_rt_game.c", "#define RC_MAX", "static void* PhaseWorldData"),
        cut("survival_rt_game.c", "static int Recycle(uint8_t* desc", "\nstatic double Sin("),
        cut("flight_guards.c", "typedef void (*MgListFn)", "static void MgInstall"),
    ]
    pathlib.Path(sys.argv[1]).write_text("".join(parts).replace("\r\n", "\n"), encoding="utf-8")


main()
