#!/usr/bin/env python3
"""Renders a survey JSON (the source of truth) as the readable Markdown next to it.

    python3 docs/scripts/survey/render_md.py docs/founder-survey-3.json > docs/founder-survey-3.md

The app (ex-tales-forge /admin/survey) reads the JSON from main; edit the JSON,
then re-run this script so the .md stays in step. Format: see
ex-tales-forge priv/surveys/README.md.
"""
import json
import re
import sys

GH = 'https://github.com/whyse-ab/ex-tales-forge/blob/main/docs'


def rel(text):
    """GitHub blob links to docs become relative links again."""
    return text.replace(GH, '')


def lst(spec, key, lists):
    v = spec.get(key)
    if isinstance(v, str) and v.startswith('@'):
        return lists[v[1:]], v
    return v, None


def follow_ups(q):
    return [f"- **Follow-up (short answer, optional):** {rel(f['label'])}" for f in q.get('follow_ups', [])]


def render(s):
    lists = s.get('lists', {})
    # founder-survey-3 is the app's current survey (/admin/survey); others live at /admin/surveys/<id>.
    page = '/admin/survey' if s['id'] == 'founder-survey-3' else f"/admin/surveys/{s['id']}"
    out = ['---', f'title: "{s["title"]}"', f'status: {s["status"]}', f'survey_id: {s["id"]}',
           f'survey_version: {s["version"]}', '---', '',
           f'# {s["title"]} ({s["status"]})', '',
           f'> **Generated from [`{s["id"]}.json`]({s["id"]}.json)**, the survey the app shows at `{page}`. '
           'Edit the JSON, then run `python3 docs/scripts/survey/render_md.py '
           f'docs/{s["id"]}.json > docs/{s["id"]}.md`.', '']
    if s['status'] == 'draft':
        out += ['> **DRAFT. Do not open until the "Latest findings" placeholder is filled in** '
                '(tonight\'s post-rework comparison, `analysis-jev-post-rework-2026-10-08.md`). '
                'Opening = set `"status": "open"` in the JSON.', '']
    if s.get('replaces'):
        out += ['This survey replaces ' + ', '.join(f'[{r}]({r}.md)' for r in s['replaces'])
                + ', which never went out.', '']
    if s.get('notes'):
        out += ['## Notes for Fredrik (not shown in the survey)', '']
        out += [f'- {rel(n)}' for n in s['notes']]
        if lists.get('rating'):
            out += [f'- **Rating scale** (every excerpt): {" · ".join(lists["rating"])}, plus "Why?" (optional).']
        if lists.get('archetypes'):
            out += [f'- **Archetype rows** (every grid): {" · ".join(lists["archetypes"])}.']
        out += ['']
    out += ['## Intro', '', *[f'> {l}' if l else '>' for l in rel(s.get('intro', '')).split('\n')], '']
    f = s.get('latest_findings')
    if f:
        out += [f'## {f.get("title", "Latest findings")}' + (' (placeholder)' if f.get('placeholder') else ''), '',
                rel(f['markdown']), '']
    for i, sec in enumerate(s['sections'], 1):
        out += [f'## Section {i}: {sec["title"]}', '']
        if sec.get('markdown'):
            out += [rel(sec['markdown']), '']
        for q in sec.get('questions', []):
            out += render_q(q, lists)
    if s.get('how_we_use'):
        out += ["## How we'll use the answers", ''] + [f'- {rel(h)}' for h in s['how_we_use']] + ['']
    return '\n'.join(out).rstrip() + '\n'


def render_q(q, lists):
    t = q['type']
    req = 'required' if q.get('required') else 'optional'
    o = [f'### {q.get("number", "")}. {q["title"]}'.replace('. ', '. ', 1), '']
    if t == 'excerpt':
        run, turn = q['run_id'], q['turn']
        scale = ', stricter scale' if q.get('jev_scale') == 'stricter' else ''
        ctx = f' {q["context"]}' if q.get('context') else ''
        o += [f'[Turn {turn}](https://tales-forge-playtest.fly.dev/admin/playtest/{run}#turn-{turn}) · '
              f'{q.get("character", "")}{ctx} Jev **{q["jev_score"]:.2f}** of 5{scale}.', '',
              f'> **Player:** {q["player"]}', '>', f'> **Game:** {q["game"]}', '',
              *([f'{rel(q["text"])}', ''] if q.get('text') else []),
              '- **Answer:** the rating scale, required; "Why?" optional'
              + (f' ({q["why_hint"]})' if q.get('why_hint') else '') + '.']
    else:
        kind = {'single': 'Single choice', 'checkboxes': 'Checkboxes (pick several)', 'scale': 'Scale',
                'grid': 'Grid, several per row' if q.get('multi') else 'Grid, one per row',
                'text': 'Paragraph' if q.get('long') else 'Short answer'}[t]
        o.append(f'- **Type:** {kind}, {req}')
        if q.get('text'):
            o.append(f'- **Text:** {rel(q["text"])}')
        if t in ('single', 'checkboxes'):
            opts, _ = lst(q, 'options', lists)
            o.append('- **Options:** ' + ' · '.join(opts) + (' · Other (free text)' if q.get('other') else ''))
        if t == 'scale':
            o.append(f'- **Labels:** {q.get("min", 1)} = {q.get("min_label", "")} · {q.get("max", 5)} = {q.get("max_label", "")}')
        if t == 'grid':
            rows, rref = lst(q, 'rows', lists)
            cols, _ = lst(q, 'columns', lists)
            o.append('- **Rows:** ' + ('the ' + rref[1:] + ' list (see the notes)' if rref == '@archetypes'
                                       else ' · '.join(rows)))
            o.append('- **Columns:** ' + ' · '.join(cols))
    o += follow_ups(q) + ['']
    return o


if __name__ == '__main__':
    print(render(json.load(open(sys.argv[1]))), end='')
