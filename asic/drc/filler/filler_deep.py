"""Project copy of ihp-sg13cmos5l libs.tech/klayout/tech/scripts/filler.py that runs
the fill macros from this directory (PDK macros with `deep` mode prepended).

The PDK version runs flat and runs out of memory (~30 GB) on hdc_chip_top.

klayout -b -zz -r filler_deep.py -rd output_file=filled.gds input.gds

Takes ~4.5 h and ~1.7 GB on hdc_chip_top (chip2 GDS).
"""
# pylint: disable=import-error,undefined-variable
import pathlib
import sys
import pya

try:
    output_file
except NameError:
    print("Missing output_file argument. Please define '-rd output_file=<path-to-output-file>'")
    sys.exit(1)

macro_dir = globals().get('macro_dir', pathlib.Path(__file__).resolve().parent)

NO_ACTIV = 'no_activ' in globals()
NO_METAL = 'no_metal' in globals()

for disabled, area in [(NO_ACTIV, 'ActGatP'), (NO_METAL, 'Metal')]:
    if disabled:
        print(f"Skip {area} fill because disabled by argument")
    else:
        print(f"Start filling {area}")
        pya.Macro(str(pathlib.Path(macro_dir) / f"sg13cmos5l_filler_{area}.lym")).run()

pya.CellView.active().layout().write(output_file)
