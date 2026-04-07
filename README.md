<p align="center">
    <img src="https://raw.githubusercontent.com/openpeeps/marvdown/main/.github/marvdown-logo.png" width="128px"><br>
    This is Marvdown ⚡️ A stupid simple Markdown parser
</p>

<p align="center">
  <code>nimble install marvdown</code></code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/marvdown/">API reference</a> | <a href="https://github.com/openpeeps/marvdown/releases">Download</a><br><br>
  <img src="https://github.com/openpeeps/marvdown/workflows/test/badge.svg" alt="Github Actions"> <img src="https://github.com/openpeeps/marvdown/workflows/docs/badge.svg" alt="Github Actions">
</p>

> [!NOTE]  
> Marv is still in early development. Some features are not fully implemented yet. Contributions are welcome!

## 😍 Key Features
- [x] Extremely Fast & Lightweight! [Check benchmarks](#benchmarks)
- [x] Compiled cross-platform CLI app
- [x] Nim library for easy integration in your 👑 Nim projects
- [x] Markdown to HTML
  - [x] Auto-generate Table of Contents (ToC)
  - [x] Auto-generate heading IDs for anchor links
- [ ] Markdown to PDF
- [x] Markdown to JSON (structured data)
- [ ] GitHub Flavored Markdown (GFM)

## About
Marv is a stupid simple markdown parser written in [Nim](https://nim-lang.org). It can be used as a library in your Nim projects or as a CLI tool to convert markdown files to HTML. Currently, it supports basic markdown syntax like headings, paragraphs, bold, italic, links, images, lists, blockquotes, code blocks and inline code.

## Installing

Install Marvdown via [Nimble](https://nim-lang.org/docs/nimble.html)
```
nimble install marvdown
```


## Example Usage
Using Marvdown from the command line is super easy. Just run:
```
marvdown html sample.md --optAnchors --bench
```
Enable anchor generations for headings with `--optAnchors` flag. Run benchmarks with `--bench` flag.

### Programming with Marvdown

In Nim language the fastest way to convert markdown to HTML is to use the `toHtml()` proc.
```nim
import marvdown

echo marvdown.toHtml(readFile("sample.md"))
```

_todo: example of custom options_

For more examples, see the [/examples folder](#). Also check out the [API reference](https://openpeeps.github.io/marvdown/) for more details 👌

### Benchmarks
Marvdown is super fast! It can parse large markdown files in milliseconds. Here is a quick benchmark
over 100K lines of markdown text (~5.3 MB)

```
Benchmark 1: marvdown html bigdoc.md
  Time (abs ≡):        188.1 ms               [User: 166.9 ms, System: 19.8 ms]
```

_Benchmark made with [hyperfine](https://github.com/sharkdp/hyperfine)_

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/marvdown/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/marvdown/fork)
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)
- 🥰 [Donate to OpenPeeps via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C)

### Credits
Original illustration made by 💙 [Olha](https://www.deviantart.com/jo316) remixed with Sora.

### 🎩 License
**Marv** | [MIT License](https://github.com/openpeeps/marvdown/blob/main/LICENSE).
[Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2024 OpenPeeps & Contributors &mdash; All rights reserved.
