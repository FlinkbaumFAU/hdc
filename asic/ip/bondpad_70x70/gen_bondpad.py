# Generates bondpad_70x70 (GDS + LEF) with the PDK's bondpad.py and fixes
# three issues that keep its output from working with LibreLane/OpenROAD:
#   1. `-rd diameter=70.0` arrives as a string, which crashes generate_lef()
#      (str - float) -> pass numeric values by running the script via exec.
#   2. The PCell is centred on (0,0) while the LEF has ORIGIN 0 0 / SIZE 70
#      -> move the GDS cell so its lower-left corner is at (0,0).
#   3. The LEF uses CLASS COVER BUMP, but OpenROAD's place_bondpad requires
#      CLASS COVER (PAD-0011) -> rewrite the class.
#
# Usage (from this directory, inside `nix shell ~/Documents/doktor/nix-passionate#pyenv`):
#   K=/opt/IHP-Open-PDK/ihp-sg13cmos5l/libs.tech/klayout
#   KLAYOUT_PATH=$K KLAYOUT_HOME=$K klayout -n sg13cmos5l -zz -r gen_bondpad.py -rd pdk_root=/opt/IHP-Open-PDK
# (KLAYOUT_HOME keeps ~/.klayout autorun macros of other PDKs out.)
import os
import klayout.db as kdb

diameter = 70.0
shape = 'square'
output = 'gds/bondpad_70x70.gds'
lef_output = 'lef/bondpad_70x70.lef'
script = os.path.join(pdk_root, 'ihp-sg13cmos5l/libs.tech/klayout/tech/scripts/bondpad.py')  # noqa: F821
exec(compile(open(script).read(), script, 'exec'))

# 2. Lower-left corner of the GDS cell to (0,0)
layout = kdb.Layout()
layout.read(output)
top = layout.top_cell()
bbox = top.bbox()
shift = kdb.Trans(-bbox.left, -bbox.bottom)
for inst in top.each_inst():
    inst.transform(shift)
assert top.bbox() == kdb.Box(0, 0, bbox.width(), bbox.height()), top.bbox()
layout.write(output)
print(f'GDS shifted by ({-bbox.left * layout.dbu}, {-bbox.bottom * layout.dbu}) um')

# 3. CLASS COVER BUMP -> CLASS COVER
with open(lef_output) as f:
    lef = f.read()
with open(lef_output, 'w') as f:
    f.write(lef.replace('CLASS COVER BUMP ;', 'CLASS COVER ;'))
