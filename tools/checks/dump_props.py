# dump_props.py <zen package> <struct/class name> [export index] : print an export's properties via uprop.
import sys, os, pprint
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))
import uprop
from zen import Zen
z = Zen(sys.argv[1]); c = uprop.Ctx(z.d, z.names)
i = int(sys.argv[3]) if len(sys.argv) > 3 else 0; e = z.exports[i]
v, o = uprop.read_struct(c, z.header_size + e['off'], sys.argv[2])
print('export', e['name'], 'consumed', o - (z.header_size + e['off']), 'of', e['size'])
pprint.pprint(v, width=200)
