# Marvdown examples

Runnable examples for the Marvdown Nim library. Each file uses the shared
`config.nims` in this directory, so you can run them straight from the
repository root:

```bash
nim c -r examples/example.nim
```

## example.nim

A single program that walks through every feature and prints the generated
HTML to stdout:

1. Basic conversion
2. Settings / options (`MarkdownOptions`)
3. Headings & anchors
4. Inline formatting
5. Links & autolinks (incl. email autolinks)
6. Images
7. Lists & task lists (checkboxes)
8. Blockquotes & GitHub-style alerts
9. Code blocks (fenced + indented)
10. Tables (with footer)
11. Footnotes
12. Reference links
13. Raw HTML passthrough
14. Components (`@include`, `@attr`, `$variable`)
15. `customTransform` hook
16. Lazy-loading media (iframes / videos / images)
17. YAML front matter + `getHeader`
18. AST / JSON (`getAst`)
19. Table of contents data (`getSelectorItems`)
20. `decodeHtmlEntities`

## sample.md

A feature-rich Markdown document you can feed to the CLI or use for
benchmarks. Build the CLI once (from the repository root) and run it against
the sample:

```bash
nim c src/marvdown.nim          # produces ./marvdown

./marvdown html examples/sample.md --optAnchors          # HTML to stdout
./marvdown html examples/sample.md --optAnchors --output out.html
./marvdown json examples/sample.md                        # AST as JSON
```

> Tip: once installed via `nimble install marvdown`, the `marvdown` binary is
> available directly: `marvdown html examples/sample.md --optAnchors --bench`

## assets/

Fixture files used by the examples (e.g. the HTML component imported by the
`@include` section in `example.nim`).
