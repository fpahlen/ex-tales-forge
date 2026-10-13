# Founders' page data

`data.json` is a snapshot of tales-forge-docs `docs/team-page/data.json`, the
numbers behind the founders' pages: the landing page at `/team`
(`TalesForgeWeb.TeamLive`) and the full presentation at `/team/presentation`
(`TalesForgeWeb.TeamPresentationLive`). The copy comes from
`docs/team-page/content.md` in the same folder (section 6, the shared board,
from `shared_board`, is `TalesForgeWeb.TeamBoard`).

It is read **at compile time** by `TalesForge.TeamPage` (`@external_resource`):
no file or network IO on a request, a broken file fails the build and CI
instead of the page, and the tests check the exact file that ships. A `null`
or missing value shows as "not measured yet"; never put a guess in.

To refresh the numbers, copy the docs file, put back the `workflow` block
(see "Team config" below) and open a PR:

    jq --slurpfile w <(jq .workflow priv/team/data.json) '. + {workflow: $w[0]}' \
      ../tales-forge-docs/docs/team-page/data.json > /tmp/data.json
    mv /tmp/data.json priv/team/data.json

A plain `cp` removes the `workflow` block, and then the build stops.

Both pages show `_about.as_of` in their footer ("Numbers as of ...").

## Illustrations

The painted illustrations come from tales-forge-docs `docs/team-page/images/`
(approved by Fredrik) and are served from `priv/static/images/team/` by
`TalesForgeWeb.TeamArt.picture/1`: WebP with a JPEG fallback, one file per
width for `srcset`, explicit `width`/`height`, lazy loading below the fold.
The files are generated once and committed; nothing runs at build time.

| Picture | Used for | Crop of the 1280×720 original | Widths |
|---|---|---|---|
| `hero` | the hero at the top | none (16:9) | 480, 960, 1280 |
| `case`, `bobby`, `gentry` | the bots' cards | centred 960×720 (4:3) | 320, 640, 960 |
| `founders-seal` | the "A founder's OK" steps of the flow | 660×660 at +320+10 (the seal) | 96, 192 |

No width above the original's: upscaling adds bytes, not detail. To redo
them (ImageMagick 7 and cwebp), from the repo root with the docs checkout next
to it:

    SRC=../tales-forge-docs/docs/team-page/images OUT=priv/static/images/team T=$(mktemp -d)
    convert $SRC/hero.jpg $T/hero.png
    for b in case bobby gentry; do convert $SRC/$b.jpg -gravity center -crop 960x720+0+0 +repage $T/$b.png; done
    convert $SRC/founders-seal.jpg -crop 660x660+320+10 +repage $T/founders-seal.png
    gen() { n=$1; shift; for w in "$@"; do
      convert $T/$n.png -filter Lanczos -resize ${w}x $T/$n-$w.png
      convert $T/$n-$w.png -strip -sampling-factor 4:2:0 -interlace JPEG -quality 78 $OUT/$n-$w.jpg
      cwebp -quiet -q 72 -m 6 -sharp_yuv -metadata none $T/$n-$w.png -o $OUT/$n-$w.webp
    done; }
    gen hero 480 960 1280; for b in case bobby gentry; do gen $b 320 640 960; done; gen founders-seal 96 192

Like every file under `priv/static/images`, they can be fetched without
signing in (the page itself still needs the team sign-in).

## Team config (Workflow)

The Workflow code (the idea board, the team pages, mentions, chat, the work
log and `TalesForge.TeamOnline`) has no team names in it. It gets them from
one plain struct, `Workflow.Team`, that the edge reads once
(`Workflow.Team.Source`, at compile time) and gives to each pure function as
an argument.

- `data.json`, key `workflow`: the product name, the repo URL, the docs
  repo, the founders (name and GitHub login), the bots (id, name and role:
  `refiner`, `builder` or `checker`), the labels of the seven board columns
  and the goals. All teams use the same seven columns; only the labels
  change.
- `content.json`: the presentation text that names the product or the
  team, by key (`Workflow.Team.text/2`). `{product}` in a text becomes the
  product name.
- `workflow-files.txt`: the Workflow `lib/` files. CI runs
  `mix workflow.check_names`, which reads only these files and stops when
  one of them has a name from the team config. The module names
  `TalesForge` and `TalesForgeWeb` and the app name `:ex_tales_forge` are
  shared wiring and stay for now.

A bot portrait is a file pair in `priv/static/images/team/`
(`<bot id>-avatar-192.jpg` and `<bot id>-960.jpg`, see "Illustrations"); its
alt text is the content key `art.alt.<bot id>`.
