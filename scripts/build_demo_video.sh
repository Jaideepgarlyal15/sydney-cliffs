#!/usr/bin/env bash
# Build the narrated demo walkthrough (1920x1080, ~2:20, H.264 + AAC).
# Thirteen segments: macOS `say` narration, PIL-rendered cards or real assets,
# each segment encoded identically, then concatenated. No secrets, no data.
#   bash scripts/build_demo_video.sh
# Optional: DEMO_SRC=<path to the 30 s vertical social post> (default ~/Downloads/demo.mp4)
set -euo pipefail
cd "$(dirname "$0")/.."
B=out/video_build/demo2
mkdir -p "$B"
DEMO_SRC="${DEMO_SRC:-$HOME/Downloads/demo.mp4}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC_LINE="Source: ABS Census 2021 & SEIFA (CC BY 4.0)"

VOICE=Karen
say -v Karen "x" -o "$B/_vtest.aiff" 2>/dev/null || VOICE=Samantha
echo "voice: $VOICE"

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# ---- narration texts -----------------------------------------------------------------
cat > "$B/n1.txt" <<'EOF'
One street. Two Sydneys. This is Young Street, in Redfern. On one side, nine percent of homes are social housing. On the other, seventy four percent. One side sits in the eightieth percentile for advantage. The other, the bottom half a percent. Is it real? We tried to break it. Sydney's divides are mostly hills, not cliffs.
EOF
cat > "$B/n2.txt" <<'EOF'
That was our social post. Now here is how we built it, and how we tried to break it.
EOF
cat > "$B/n3.txt" <<'EOF'
We used the twenty twenty one Census and the SEIFA advantage index, for eleven thousand two hundred and thirty seven small neighbourhoods across Greater Sydney.
EOF
cat > "$B/n4.txt" <<'EOF'
A cliff is not one odd neighbourhood. It is a cluster of advantage pressed against a cluster of disadvantage. We found those clusters with local Moran's I, using permutation tests and false discovery rate control.
EOF
cat > "$B/n5.txt" <<'EOF'
Then we kept only shared borders where both sides are significant and the gap is in the top five percent, and joined them into lines scored by gap and length.
EOF
cat > "$B/n6.txt" <<'EOF'
This is the interactive map. Every line is a candidate cliff.
EOF
cat > "$B/n7.txt" <<'EOF'
The sharpest one is Young Street in Redfern, about eight hundred and forty metres long.
EOF
cat > "$B/n8.txt" <<'EOF'
Across that street, social housing jumps from nine percent to seventy four percent, and median household income drops from about two thousand five hundred dollars a week to about four hundred and thirty five.
EOF
cat > "$B/n9.txt" <<'EOF'
Microburbs' twenty twenty six estimates are consistent with the same divide.
EOF
cat > "$B/n10.txt" <<'EOF'
Then we tried to break it. We simulated many Sydneys with the same overall clustering. Edges this sharp appeared about a third of the time. P equals zero point three four. Not exceptional.
EOF
cat > "$B/n11.txt" <<'EOF'
Results were only moderately stable across settings, and a twenty sixteen comparison was not possible, because most nearby boundaries changed.
EOF
cat > "$B/n12.txt" <<'EOF'
So our honest finding: Sydney's divides are real, but they are mostly hills, not cliffs.
EOF
cat > "$B/n13.txt" <<'EOF'
Everything is open source, in R, with tests and a reproducible report. Thanks from Team Oracles.
EOF

for i in $(seq 1 13); do
  say -v "$VOICE" -r 175 -o "$B/n$i.aiff" -f "$B/n$i.txt"
done

# ---- cards (PIL) -----------------------------------------------------------------------
sed -n '/^find_cliffs <- function/,/^  lab <- run_lisa/p' R/cliffs.R | head -15 > "$B/code15.txt"
python3 - "$B" "$SRC_LINE" <<'PYEOF'
import sys
from PIL import Image, ImageDraw, ImageFont
B, SRC = sys.argv[1], sys.argv[2]
BG, FG, DIM, ACC, HI, LO = "#0b1020", "white", "#c9d2e0", "#ff2d55", "#ffb000", "#3d8bfd"
def F(sz, mono=False, bold=True):
    f = "/System/Library/Fonts/Menlo.ttc" if mono else "/System/Library/Fonts/Helvetica.ttc"
    return ImageFont.truetype(f, sz, index=1 if (bold and not mono) else 0)
def card(name, title, lines, mono=False, footer=SRC):
    im = Image.new("RGB", (1920, 1080), BG); d = ImageDraw.Draw(im)
    d.text((960, 160), title, font=F(86), fill=FG, anchor="mm")
    y = 320
    for ln, col, sz in lines:
        d.text((960, y), ln, font=F(sz, mono=mono), fill=col, anchor="mm")
        y += int(sz * 1.6)
    d.text((960, 1020), footer, font=F(30, bold=False), fill="#9aa3b2", anchor="mm")
    im.save(f"{B}/{name}.png")
card("c2", "SYDNEY CLIFFS", [("Where one side of the street is a different Sydney", DIM, 44),
                             ("", FG, 44), ("Team ORACLES", HI, 64)])
card("c3", "The data", [("ABS Census 2021  +  SEIFA IRSAD", FG, 56), ("", FG, 30),
                        ("11,237 small neighbourhoods (SA1s)", HI, 64), ("", FG, 30),
                        ("Greater Sydney", DIM, 50)])
# method card with HH | LL diagram
im = Image.new("RGB", (1920, 1080), BG); d = ImageDraw.Draw(im)
d.text((960, 140), "Clusters, not outliers", font=F(86), fill=FG, anchor="mm")
d.rectangle([360, 330, 920, 710], fill=HI); d.rectangle([1000, 330, 1560, 710], fill=LO)
d.rectangle([944, 300, 976, 740], fill=ACC)
d.text((640, 520), "HH", font=F(110), fill=BG, anchor="mm")
d.text((1280, 520), "LL", font=F(110), fill="white", anchor="mm")
d.text((960, 820), "advantage cluster  |  disadvantage cluster", font=F(44), fill=DIM, anchor="mm")
d.text((960, 900), "Local Moran's I · permutation tests · FDR control", font=F(44), fill=FG, anchor="mm")
d.text((960, 1020), SRC, font=F(30, bold=False), fill="#9aa3b2", anchor="mm")
im.save(f"{B}/c4.png")
code = [l.rstrip()[:88] for l in open(f"{B}/code15.txt")]
card("c5", "The cliff rule (R/cliffs.R)", [(l if l else " ", "#d9e2f2", 30) for l in code], mono=True)
# stats card, two columns
im = Image.new("RGB", (1920, 1080), BG); d = ImageDraw.Draw(im)
d.text((960, 140), "Across Young Street", font=F(86), fill=FG, anchor="mm")
for x, col, rows in [(560, HI, ["One side", "Social housing 9%", "IRSAD 80th pct (1143)", "$2,512 a week"]),
                     (1360, LO, ["The other", "Social housing 74%", "IRSAD 0.4th pct (658)", "$435 a week"])]:
    y = 340
    d.text((x, y), rows[0], font=F(56), fill=col, anchor="mm"); y += 110
    for r in rows[1:]:
        d.text((x, y), r, font=F(52), fill=FG, anchor="mm"); y += 100
d.rectangle([944, 300, 976, 760], fill=ACC)
d.text((960, 880), "Median household income is not equivalised", font=F(34, bold=False), fill=DIM, anchor="mm")
d.text((960, 1020), SRC + " · G37 tenure", font=F(30, bold=False), fill="#9aa3b2", anchor="mm")
im.save(f"{B}/c8.png")
card("c9", "Second source", [("Microburbs 2026 estimates are", FG, 54),
                             ("consistent with the divide", FG, 54), ("", FG, 30),
                             ("Cope St  ≈ $1,213 a week", LO, 56),
                             ("Bourke St ≈ $2,389 a week", HI, 56)],
     footer="Microburbs 2026 estimates · © Microburbs")
card("c11", "Honest caveats", [("Stability 0.39 across 18 setting combinations", FG, 54), ("", FG, 30),
                               ("2016: not comparable", HI, 56),
                               ("(only 28% of nearby boundaries unchanged)", DIM, 44)])
# hill vs cliff card
im = Image.new("RGB", (1920, 1080), BG); d = ImageDraw.Draw(im)
d.text((960, 140), "Hills, not cliffs", font=F(96), fill=FG, anchor="mm")
import math
pts = [(300 + x, 700 - int(220 * math.sin((x) / 1320 * math.pi))) for x in range(0, 1321, 20)]
d.line(pts, fill=HI, width=14)
d.line([(300, 860), (900, 860), (900, 760), (1620, 760)], fill="#4a5673", width=10)
d.text((960, 930), "most of Sydney's advantage changes gradually", font=F(44), fill=DIM, anchor="mm")
d.text((960, 1020), SRC, font=F(30, bold=False), fill="#9aa3b2", anchor="mm")
im.save(f"{B}/c12.png")
card("c13", "Open and reproducible", [("R · testthat · Quarto report · one command", FG, 50), ("", FG, 30),
                                      ("github.com/Jaideepgarlyal15/sydney-cliffs", HI, 56), ("", FG, 30),
                                      ("Thanks — Team ORACLES", FG, 54)])
PYEOF

# ---- screenshots (headless Chrome), with fallbacks -------------------------------------
shot() { # $1 html path, $2 out png
  "$CHROME" --headless=new --use-angle=swiftshader --window-size=1920,1080 \
    --virtual-time-budget=10000 --screenshot="$2" "file://$PWD/$1" >/dev/null 2>&1 || true
}
shot out/maps/cliff_01.html "$B/map_shot.png"
python3 - "$B" <<'PYEOF'
# blank-detection: if the map screenshot is near-uniform, build letterboxed fallbacks
import sys, os
from PIL import Image, ImageStat, ImageDraw, ImageFont, ImageFilter
B = sys.argv[1]
def letterbox(src, dst, url=None):
    im = Image.open(src).convert("RGB")
    im.thumbnail((1920, 1080))
    bg = Image.new("RGB", (1920, 1080), "#0b1020")
    bg.paste(im, ((1920 - im.width) // 2, (1080 - im.height) // 2))
    if url:
        d = ImageDraw.Draw(bg)
        f = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 40, index=1)
        d.rectangle([0, 990, 1920, 1080], fill="#0b1020")
        d.text((960, 1035), url, font=f, fill="#ffb000", anchor="mm")
    bg.save(dst)
p = f"{B}/map_shot.png"
ok = os.path.exists(p)
if ok:
    st = ImageStat.Stat(Image.open(p).convert("L"))
    ok = st.stddev[0] > 8
if ok:
    letterbox(p, f"{B}/v6.png")
else:
    letterbox("out/post_assets/04_sydney.png", f"{B}/v6.png")
    print("S6: map screenshot blank; using 04_sydney.png")
letterbox("out/post_assets/02_ledge.png", f"{B}/v7.png")
letterbox("out/post_assets/05_test.png", f"{B}/v10.png")
PYEOF
shot report.html "$B/rep_shot.png"
python3 - "$B" <<'PYEOF'
import sys, os
from PIL import Image, ImageStat
B = sys.argv[1]
p = f"{B}/rep_shot.png"
ok = os.path.exists(p) and ImageStat.Stat(Image.open(p).convert("L")).stddev[0] > 8
print("S13 screenshot:", "ok" if ok else "blank -> card fallback")
open(f"{B}/s13_mode.txt", "w").write("shot" if ok else "card")
PYEOF
if [ "$(cat "$B/s13_mode.txt")" = "shot" ]; then
  python3 - "$B" <<'PYEOF'
import sys
from PIL import Image, ImageDraw, ImageFont
B = sys.argv[1]
im = Image.open(f"{B}/rep_shot.png").convert("RGB").resize((1920, 1080))
d = ImageDraw.Draw(im)
d.rectangle([0, 970, 1920, 1080], fill="#0b1020")
f = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 44, index=1)
d.text((960, 1025), "github.com/Jaideepgarlyal15/sydney-cliffs", font=f, fill="#ffb000", anchor="mm")
im.save(f"{B}/v13.png")
PYEOF
else
  cp "$B/c13.png" "$B/v13.png"
fi

# ---- segment encoding -------------------------------------------------------------------
ENC_V="-r 30 -c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p"
ENC_A="-c:a aac -b:a 160k -ar 48000 -ac 2"

seg_card() { # $1 index, $2 image, $3 extra tail seconds (default 0)
  local i=$1 img=$2 extra=${3:-0}
  local nd D fo
  nd=$(dur "$B/n$i.aiff")
  D=$(python3 -c "print(round($nd + 0.6 + $extra, 2))")
  fo=$(python3 -c "print(round($D - 0.35, 2))")
  ffmpeg -y -loop 1 -t "$D" -i "$img" -i "$B/n$i.aiff" \
    -filter_complex "[0:v]scale=1920:1080,setsar=1,fade=t=in:st=0:d=0.25,fade=t=out:st=$fo:d=0.3[v];[1:a]apad[a]" \
    -map "[v]" -map "[a]" -t "$D" $ENC_V $ENC_A "$B/seg$i.mp4" >/dev/null 2>&1
}

# S1: vertical post centred over a blurred copy; narration padded/trimmed to clip length
cp "$DEMO_SRC" "$B/post.mp4"
CLIP=$(dur "$B/post.mp4")
N1=$(dur "$B/n1.aiff")
if python3 -c "exit(0 if $N1 > $CLIP - 0.8 else 1)"; then
  RATE=$(python3 -c "import math; print(int(math.ceil(175 * $N1 / ($CLIP - 1.2))))")
  echo "S1 narration ${N1}s > clip; re-synthesising at rate $RATE"
  say -v "$VOICE" -r "$RATE" -o "$B/n1.aiff" -f "$B/n1.txt"
fi
FO1=$(python3 -c "print(round($CLIP - 0.35, 2))")
ffmpeg -y -i "$B/post.mp4" -i "$B/n1.aiff" -filter_complex \
  "[0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,boxblur=22[bg];[0:v]scale=-2:1080[fg];[bg][fg]overlay=(W-w)/2:0,fps=30,setsar=1,fade=t=in:st=0:d=0.25,fade=t=out:st=$FO1:d=0.3[v];[1:a]apad[a]" \
  -map "[v]" -map "[a]" -t "$CLIP" $ENC_V $ENC_A "$B/seg1.mp4" >/dev/null 2>&1

seg_card 2  "$B/c2.png"
seg_card 3  "$B/c3.png"
seg_card 4  "$B/c4.png"
seg_card 5  "$B/c5.png"
seg_card 6  "$B/v6.png"
seg_card 7  "$B/v7.png"
seg_card 8  "$B/c8.png"
seg_card 9  "$B/c9.png"
seg_card 10 "$B/v10.png"
seg_card 11 "$B/c11.png"
seg_card 12 "$B/c12.png"
seg_card 13 "$B/v13.png"

# ---- concat; stretch the closing card if we land under 2:15 ----------------------------
cat > "$B/list.txt" <<EOF
$(for i in $(seq 1 13); do echo "file 'seg$i.mp4'"; done)
EOF
(cd "$B" && ffmpeg -y -f concat -safe 0 -i list.txt -c copy demo_full.mp4 >/dev/null 2>&1)
TOT=$(dur "$B/demo_full.mp4")
echo "total: $TOT s"
if python3 -c "exit(0 if $TOT < 135.5 else 1)"; then
  EXTRA=$(python3 -c "print(round(136.5 - $TOT, 2))")
  echo "under 2:15 — extending the closing card by ${EXTRA}s"
  seg_card 13 "$B/v13.png" "$EXTRA"
  (cd "$B" && ffmpeg -y -f concat -safe 0 -i list.txt -c copy demo_full.mp4 >/dev/null 2>&1)
  TOT=$(dur "$B/demo_full.mp4")
fi
mv "$B/demo_full.mp4" demo.mp4
echo "demo.mp4: ${TOT}s $(du -h demo.mp4 | cut -f1)"
