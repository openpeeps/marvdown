<p align="center">
    <img src="https://raw.githubusercontent.com/openpeeps/marvdown/main/.github/marvdown-logo.png" width="128px"><br>
    This is Marvdown ⚡️ A stupid simple Markdown parser
</p>

<p align="center">
  <code>nimble install marvdown</code> / <code>npm install @openpeeps/marvdown</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/marvdown/">API reference</a> | <a href="https://github.com/openpeeps/marvdown/releases">Download</a><br><br>
  <img src="https://github.com/openpeeps/marvdown/workflows/test/badge.svg" alt="Github Actions"> <img src="https://github.com/openpeeps/marvdown/workflows/docs/badge.svg" alt="Github Actions">
</p>

> [!NOTE]  
> Marv is still in early development. More features and improvements are coming soon.

## 😍 Key Features
- [x] Extremely Fast & Lightweight
- [x] Compiled CLI application
- [x] Nim library for easy integration in your 👑 Nim projects
- [x] Addon for Node.js JavaScript runtime via N-API
- [x] Markdown to HTML
  - [ ] Auto-generate Table of Contents (ToC)
  - [x] Auto-generate heading IDs for anchor links
- [ ] Markdown to PDF
- [ ] Markdown to JSON (structured data)
- [ ] GitHub Flavored Markdown (GFM)

## About
Marv is a stupid simple markdown parser written in [Nim](https://nim-lang.org). It can be used as a library in your Nim projects or as a CLI tool to convert markdown files to HTML. Currently, it supports basic markdown syntax like headings, paragraphs, bold, italic, links, images, lists, blockquotes, code blocks and inline code.

## Installing

Install Marvdown via [Nimble](https://nim-lang.org/docs/nimble.html)
```
nimble install marvdown
```

For Node.js install Marvdown via [npm](https://www.npmjs.com/package/@openpeeps/marvdown)

A GitHub action will build the binary CLI app and Node.js addon evertime a new release is published. Download the latest version of Marvdown from the [Github releases page](https://github.com/openpeeps/marvdown/releases).

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

In JavaScript or TypeScript you can load the N-API addon and use the `toHtml()` function.
```js
const fs = require('fs');
const marvdown = require('@openpeeps/marvdown')

let output = marvdown.toHtml(fs.readFileSync('sample.md', 'utf8'))
console.log(output)
```

_todo: example of custom options_

For more examples, see the [/examples folder](#). Also check out the [API reference](https://openpeeps.github.io/marvdown/) for more details 👌

### Benchmarks
todo

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
