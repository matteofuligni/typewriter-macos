#!/usr/bin/env python3
"""Stage an offline pdfLaTeX runtime from the active TeX Live installation."""
import argparse
import pathlib
import re
import shutil
import subprocess

LATEX = """
base latexconfig amsmath amsfonts amscls tools graphics graphics-cfg graphics-def
geometry xcolor hyperref l3kernel l3backend l3packages etoolbox booktabs microtype
psnfss lm url parskip setspace enumitem caption fancyhdr listings pgf pgfplots
mathtools float makecell multirow xkeyval textcase kvoptions kvsetkeys kvdefinekeys
pdfescape pdftexcmds infwarerr iftex letltxmacro refcount rerunfilecheck
uniquecounter auxhook gettitlestring hycolor intcalc bitset bigintcalc atbegshi
atveryend grfext epstopdf-pkg colorprofiles transparent ragged2e fontaxes
xstring mweights zapfding utopia euenc ts1 cm-super siunitx csquotes colortbl
""".split()
GENERIC = """
babel babel-english babel-italian babel-french babel-german babel-spanish babel-portuges
iftex infwarerr intcalc bigintcalc bitset etexcmds kvdefinekeys kvsetkeys ltxcmds
ltxsys pdfescape pdftexcmds uniquecounter gettitlestring stringenc auxhook
hycolor atbegshi atveryend dehyph hyph-utf8 config l3backend pgf pgfplots pdftex
""".split()
FONTS = """
cm cmextra amsfonts lm ec cm-super cm-super-minimal cmcyr cyrillic-modern
latex-fonts marvosym rsfs wasy wasy2 wasysym xypic ifsym symbols
tex-gyre tex-gyre-math utopia txfonts pxfonts
""".split()
VENDORS = ["urw"]
ADOBE = "avantgar bookman courier helvetic ly1 ncntrsbk palatino symbol times utopia zapfchan zapfding".split()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=pathlib.Path)
    parser.add_argument("--texbin", type=pathlib.Path, default=pathlib.Path("/Library/TeX/texbin"))
    args = parser.parse_args()
    destination = args.destination.resolve()
    texbin = args.texbin.resolve()
    def lookup(*opts):
        return pathlib.Path(subprocess.check_output([texbin / "kpsewhich", *opts], text=True).strip())
    root = lookup("-var-value=TEXMFROOT")
    dist = lookup("-var-value=TEXMFDIST")
    fmt = lookup("--engine=pdftex", "--format=fmt", "pdflatex.fmt")
    generated = lookup("-var-value=TEXMFSYSVAR")

    def copy(relative):
        path = dist / relative
        target = destination / "tree" / relative
        if path.is_dir():
            shutil.copytree(path, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".DS_Store"))
        elif path.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)

    for name in LATEX:
        copy(f"tex/latex/{name}")
    for name in GENERIC:
        copy(f"tex/generic/{name}")
    for relative in ["tex/plain/base", "tex/context/base/mkii/supp-pdf.mkii"]:
        # Some graphics packages use ConTeXt's shared support files.
        copy(relative)
    for kind in ["tfm", "type1", "vf", "enc", "map"]:
        for vendor in VENDORS:
            copy(f"fonts/{kind}/{vendor}")
        for name in ADOBE:
            copy(f"fonts/{kind}/adobe/{name}")
        for family in FONTS:
            copy(f"fonts/{kind}/public/{family}")
        if kind == "enc":
            for family in FONTS + ["base", "psnfss", "dvips", "tex-gyre", "xetex"]:
                copy(f"fonts/enc/dvips/{family}")
    for family in ["ec", "tc"]:
        copy(f"fonts/tfm/jknappen/{family}")
    for filename in ["cp227.tcx"]:
        copy(f"web2c/{filename}")

    (destination / "bin").mkdir(parents=True, exist_ok=True)
    binary = destination / "bin/pdflatex"
    subprocess.run(["lipo", "-thin", "arm64", texbin / "pdftex", "-output", binary], check=True)
    binary.chmod(0o755)
    # Updating the executable layout breaks its original signature.
    subprocess.run(["codesign", "--force", "--sign", "-", binary], check=True)
    fmt_dest = destination / "tree/web2c/pdftex"
    fmt_dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fmt, fmt_dest / "pdflatex.fmt")

    mapdir = destination / "tree/fonts/map/pdftex"
    mapdir.mkdir(parents=True, exist_ok=True)
    mapfile = generated / "fonts/map/pdftex/updmap/pdftex.map"
    fontfiles = {p.name for p in (destination / "tree/fonts").rglob("*") if p.is_file()}
    lines = mapfile.read_text(encoding="latin1").splitlines()
    selected = []
    for line in lines:
        deps = re.findall(r"<\[?<?\s*([^\s<>]+\.(?:enc|pfb|pfa|ttf|otf))", line, re.I)
        if all(dep in fontfiles for dep in deps):
            selected.append(line)
    (mapdir / "pdftex.map").write_text("\n".join(selected) + "\n", encoding="latin1")

    overrides = """TEXMFROOT = $TEXMFCNF
TEXMFDIST = $TEXMFROOT/tree
TEXMFMAIN = $TEXMFDIST
TEXMFLOCAL = $TEXMFDIST
TEXMFSYSVAR = $TEXMFDIST
TEXMFSYSCONFIG = $TEXMFDIST
TEXMFHOME = $TEXMFDIST
TEXMFVAR = $TEXMFDIST
TEXMFCONFIG = $TEXMFDIST
TEXMF = !!$TEXMFDIST
TEXMFDBS = !!$TEXMFDIST
shell_escape = f
openin_any = p
openout_any = p
"""
    standard = (dist / "web2c/texmf.cnf").read_text(encoding="utf-8")
    patched = {}
    for line in overrides.strip().splitlines():
        name = line.split("=", 1)[0].strip()
        standard = re.sub(r"^" + re.escape(name) + r"\s*=[^\n]*$", "", standard, flags=re.M)
        patched[name] = line
    (destination / "texmf.cnf").write_text(standard + "\n" + "\n".join(patched.values()) + "\n", encoding="utf-8")
    subprocess.run([texbin / "mktexlsr", destination / "tree"], check=True)
    for filename in ("LICENSE.TL", "LICENSE.CTAN"):
        if (root / filename).is_file():
            shutil.copy2(root / filename, destination / filename)

if __name__ == "__main__":
    main()
