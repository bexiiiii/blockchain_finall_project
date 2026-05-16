import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const jobs = [
  {
    input: "docs/architecture/ARCHITECTURE.md",
    output: "docs/architecture/ARCHITECTURE.pdf",
    kind: "report",
    title: "Architecture & Design Document",
  },
  {
    input: "docs/audit/SECURITY_AUDIT.md",
    output: "docs/audit/SECURITY_AUDIT.pdf",
    kind: "report",
    title: "Internal Security Audit Report",
  },
  {
    input: "docs/reports/gas-comparison.md",
    output: "docs/reports/gas-comparison.pdf",
    kind: "report",
    title: "Gas Optimization Report",
  },
  {
    input: "docs/reports/coverage.md",
    output: "docs/reports/coverage.pdf",
    kind: "report",
    title: "Coverage Report",
  },
  {
    input: "docs/reports/deployment-verification.md",
    output: "docs/reports/deployment-verification.pdf",
    kind: "report",
    title: "Deployment Verification Report",
  },
  {
    input: "docs/presentation/final-presentation.md",
    output: "docs/presentation/final-presentation.pdf",
    kind: "deck",
    title: "RWA T-Bill Protocol Final Presentation",
  },
];

function escapeHtml(value) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function inlineMarkdown(value) {
  const normalized = value.replace(/\\([*_`])/g, "$1");
  return escapeHtml(normalized)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\*([^*]+)\*/g, "<em>$1</em>");
}

function parseTable(lines, start) {
  const rows = [];
  let cursor = start;
  while (cursor < lines.length && /^\s*\|.*\|\s*$/.test(lines[cursor])) {
    rows.push(lines[cursor]);
    cursor += 1;
  }

  if (rows.length < 2 || !/^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(rows[1])) {
    return null;
  }

  const split = (row) =>
    row
      .trim()
      .replace(/^\|/, "")
      .replace(/\|$/, "")
      .split("|")
      .map((cell) => cell.trim());

  const headers = split(rows[0]);
  const body = rows.slice(2).map(split);
  const html = [
    "<table>",
    "<thead><tr>",
    ...headers.map((header) => `<th>${inlineMarkdown(header)}</th>`),
    "</tr></thead>",
    "<tbody>",
    ...body.map(
      (row) => `<tr>${row.map((cell) => `<td>${inlineMarkdown(cell)}</td>`).join("")}</tr>`,
    ),
    "</tbody>",
    "</table>",
  ].join("");

  return { html, next: cursor };
}

function markdownToHtml(markdown) {
  const lines = markdown.split(/\r?\n/);
  const html = [];
  let paragraph = [];
  let list = null;
  let inCode = false;
  let codeLang = "";
  let codeLines = [];

  const closeParagraph = () => {
    if (!paragraph.length) return;
    html.push(`<p>${inlineMarkdown(paragraph.join(" "))}</p>`);
    paragraph = [];
  };

  const closeList = () => {
    if (!list) return;
    html.push(`</${list}>`);
    list = null;
  };

  for (let i = 0; i < lines.length; i += 1) {
    const raw = lines[i];
    const line = raw.trimEnd();

    if (inCode) {
      if (line.startsWith("```")) {
        const code = escapeHtml(codeLines.join("\n"));
        html.push(`<pre class="code-block ${codeLang}"><code>${code}</code></pre>`);
        inCode = false;
        codeLang = "";
        codeLines = [];
      } else {
        codeLines.push(raw);
      }
      continue;
    }

    if (line.startsWith("```")) {
      closeParagraph();
      closeList();
      inCode = true;
      codeLang = line.slice(3).trim() || "text";
      codeLines = [];
      continue;
    }

    if (!line.trim()) {
      closeParagraph();
      closeList();
      continue;
    }

    if (/^\s*</.test(line)) {
      closeParagraph();
      closeList();
      html.push(raw);
      continue;
    }

    const table = parseTable(lines, i);
    if (table) {
      closeParagraph();
      closeList();
      html.push(table.html);
      i = table.next - 1;
      continue;
    }

    const heading = /^(#{1,6})\s+(.+)$/.exec(line);
    if (heading) {
      closeParagraph();
      closeList();
      const level = heading[1].length;
      html.push(`<h${level}>${inlineMarkdown(heading[2])}</h${level}>`);
      continue;
    }

    const unordered = /^\s*[-*]\s+(.+)$/.exec(line);
    if (unordered) {
      closeParagraph();
      if (list !== "ul") {
        closeList();
        html.push("<ul>");
        list = "ul";
      }
      html.push(`<li>${inlineMarkdown(unordered[1])}</li>`);
      continue;
    }

    const ordered = /^\s*\d+\.\s+(.+)$/.exec(line);
    if (ordered) {
      closeParagraph();
      if (list !== "ol") {
        closeList();
        html.push("<ol>");
        list = "ol";
      }
      html.push(`<li>${inlineMarkdown(ordered[1])}</li>`);
      continue;
    }

    paragraph.push(line.trim());
  }

  closeParagraph();
  closeList();
  return html.join("\n");
}

function reportHtml(markdown, title) {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>${escapeHtml(title)}</title>
  <style>${reportCss()}</style>
</head>
<body>
  <main class="report">
    ${markdownToHtml(markdown)}
  </main>
</body>
</html>`;
}

function parseSlides(markdown) {
  return markdown
    .split(/^---\s*$/m)
    .map((slide) => slide.trim())
    .filter(Boolean)
    .map((slide, index) => {
      const lines = slide.split(/\r?\n/).filter((line) => line.trim());
      const titleLine = lines.find((line) => /^#{1,2}\s+/.test(line));
      const title = titleLine ? titleLine.replace(/^#{1,2}\s+/, "") : `Slide ${index + 1}`;
      const body = lines.filter((line) => line !== titleLine).join("\n");
      return { title, body, index };
    });
}

function deckHtml(markdown, title) {
  const slides = parseSlides(markdown);
  const renderedSlides = slides
    .map((slide, index) => {
      const isCover = index === 0;
      const isClosing = index === slides.length - 1;
      return `<section class="slide ${isCover ? "cover" : ""} ${isClosing ? "closing" : ""}">
        <div class="slide-number">${String(index + 1).padStart(2, "0")} / ${String(slides.length).padStart(2, "0")}</div>
        <div class="brand">RWA T-Bill Protocol</div>
        <div class="slide-content">
          <h1>${inlineMarkdown(slide.title)}</h1>
          ${markdownToHtml(slide.body)}
        </div>
      </section>`;
    })
    .join("\n");

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>${escapeHtml(title)}</title>
  <style>${deckCss()}</style>
</head>
<body>${renderedSlides}</body>
</html>`;
}

function reportCss() {
  return `
    @page {
      size: A4;
      margin: 18mm 16mm 18mm 16mm;
      @bottom-right {
        content: counter(page);
        color: #64748b;
        font-size: 9px;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: #172033;
      background: #ffffff;
      font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
      font-size: 10.4px;
      line-height: 1.5;
    }
    .report { max-width: 100%; }
    h1 {
      min-height: 235mm;
      margin: 0 0 18mm;
      padding: 34mm 18mm 18mm;
      color: #f8fafc;
      border-radius: 0 0 18px 18px;
      background:
        linear-gradient(135deg, rgba(14, 37, 63, 0.96), rgba(21, 94, 117, 0.9)),
        radial-gradient(circle at 82% 18%, rgba(125, 211, 252, 0.38), transparent 28%);
      font-size: 34px;
      line-height: 1.04;
      letter-spacing: 0;
      page-break-after: always;
      display: flex;
      align-items: flex-end;
    }
    h2 {
      margin: 0 0 8mm;
      padding-top: 3mm;
      color: #0f253f;
      font-size: 20px;
      line-height: 1.2;
      border-bottom: 1px solid #cbd5e1;
      padding-bottom: 3mm;
      break-after: avoid;
    }
    h2:not(:first-of-type) { break-before: page; }
    h3 {
      margin: 7mm 0 3mm;
      color: #155e75;
      font-size: 13px;
      line-height: 1.25;
      break-after: avoid;
    }
    h4 {
      margin: 5mm 0 2mm;
      color: #334155;
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    p { margin: 0 0 3.2mm; }
    ul, ol { margin: 0 0 4mm 5mm; padding: 0; }
    li { margin: 1.1mm 0; padding-left: 1mm; }
    strong { color: #0f253f; }
    code {
      padding: 1px 4px;
      color: #0f253f;
      background: #e2e8f0;
      border-radius: 4px;
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
      font-size: 0.92em;
    }
    table {
      width: 100%;
      margin: 4mm 0 6mm;
      border-collapse: collapse;
      break-inside: avoid;
      box-shadow: 0 0 0 1px #d9e2ec;
    }
    th {
      background: #0f253f;
      color: #f8fafc;
      text-align: left;
      font-weight: 700;
      padding: 7px 8px;
      border: 1px solid #0f253f;
      vertical-align: top;
    }
    td {
      padding: 6px 8px;
      border: 1px solid #d9e2ec;
      vertical-align: top;
    }
    tr:nth-child(even) td { background: #f8fafc; }
    .code-block {
      margin: 4mm 0 6mm;
      padding: 10px 12px;
      color: #dbeafe;
      background: #0f172a;
      border-radius: 10px;
      white-space: pre-wrap;
      font-size: 8.8px;
      line-height: 1.42;
      break-inside: avoid;
    }
    .document-meta,
    .callout,
    .executive-card {
      margin: 0 0 5mm;
      padding: 5mm;
      border: 1px solid #cbd5e1;
      border-left: 5px solid #155e75;
      border-radius: 10px;
      background: #f8fafc;
      break-inside: avoid;
    }
    .metric-grid,
    .card-grid,
    .diagram-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 4mm;
      margin: 4mm 0 6mm;
      break-inside: avoid;
    }
    .metric,
    .card,
    .diagram-node {
      padding: 4mm;
      border: 1px solid #d9e2ec;
      border-radius: 10px;
      background: #ffffff;
      box-shadow: 0 8px 24px rgba(15, 37, 63, 0.06);
    }
    .metric strong {
      display: block;
      color: #155e75;
      font-size: 18px;
      line-height: 1.1;
    }
    .metric span,
    .card span,
    .diagram-node span {
      display: block;
      color: #64748b;
      font-size: 9px;
      margin-top: 1mm;
    }
    .diagram {
      margin: 5mm 0 7mm;
      padding: 5mm;
      border-radius: 14px;
      background: #eef6f8;
      border: 1px solid #c9dce2;
      break-inside: avoid;
    }
    .diagram-title {
      color: #0f253f;
      font-weight: 800;
      margin-bottom: 4mm;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-size: 9px;
    }
    .flow-row {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 3mm;
      align-items: stretch;
      margin: 3mm 0;
    }
    .flow-row .step {
      position: relative;
      padding: 4mm;
      min-height: 20mm;
      background: #ffffff;
      border: 1px solid #b8cbd3;
      border-radius: 10px;
      font-weight: 700;
      color: #0f253f;
    }
    .flow-row .step small {
      display: block;
      margin-top: 1.5mm;
      color: #64748b;
      font-weight: 500;
      line-height: 1.35;
    }
    .flow-row .step:not(:last-child)::after {
      content: "→";
      position: absolute;
      right: -8px;
      top: 50%;
      transform: translateY(-50%);
      color: #155e75;
      font-size: 16px;
      font-weight: 800;
    }
    .two-col {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 5mm;
      margin: 4mm 0 6mm;
    }
    .page-break { break-before: page; }
  `;
}

function deckCss() {
  return `
    @page { size: 13.333in 7.5in; margin: 0; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: #0b1220;
      color: #f8fafc;
      font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
    }
    .slide {
      position: relative;
      width: 13.333in;
      height: 7.5in;
      overflow: hidden;
      page-break-after: always;
      padding: 0.55in 0.72in 0.52in;
      background:
        linear-gradient(115deg, #f8fafc 0%, #f8fafc 63%, #d8edf2 63%, #d8edf2 100%);
      color: #0f253f;
    }
    .slide::before {
      content: "";
      position: absolute;
      inset: 0;
      background:
        linear-gradient(90deg, rgba(15, 37, 63, 0.075) 1px, transparent 1px),
        linear-gradient(0deg, rgba(15, 37, 63, 0.055) 1px, transparent 1px);
      background-size: 42px 42px;
      opacity: 0.55;
      pointer-events: none;
    }
    .cover,
    .closing {
      background:
        linear-gradient(135deg, rgba(14, 37, 63, 0.97), rgba(21, 94, 117, 0.94)),
        radial-gradient(circle at 78% 22%, rgba(125, 211, 252, 0.35), transparent 28%);
      color: #f8fafc;
    }
    .cover::before,
    .closing::before { opacity: 0.18; }
    .brand {
      position: absolute;
      top: 0.33in;
      left: 0.72in;
      color: #155e75;
      font-size: 0.13in;
      font-weight: 800;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    .cover .brand,
    .closing .brand { color: #a7f3d0; }
    .slide-number {
      position: absolute;
      right: 0.72in;
      bottom: 0.36in;
      color: #64748b;
      font-size: 0.12in;
      font-weight: 700;
    }
    .cover .slide-number,
    .closing .slide-number { color: rgba(248, 250, 252, 0.72); }
    .slide-content {
      position: relative;
      z-index: 2;
      height: 100%;
      display: flex;
      flex-direction: column;
      justify-content: center;
      max-width: 10.75in;
    }
    .slide h1 {
      margin: 0 0 0.22in;
      color: inherit;
      font-size: 0.56in;
      line-height: 1.02;
      letter-spacing: 0;
      max-width: 9.7in;
    }
    .cover h1,
    .closing h1 {
      font-size: 0.72in;
      max-width: 9.3in;
    }
    .slide h2,
    .slide h3 {
      margin: 0.06in 0 0.12in;
      color: #155e75;
      font-size: 0.25in;
    }
    .cover h2,
    .closing h2,
    .cover h3,
    .closing h3 { color: #a7f3d0; }
    .slide p {
      margin: 0 0 0.14in;
      max-width: 9.6in;
      color: #334155;
      font-size: 0.23in;
      line-height: 1.34;
    }
    .cover p,
    .closing p { color: rgba(248, 250, 252, 0.86); }
    .slide ul {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 0.13in 0.18in;
      list-style: none;
      margin: 0.08in 0 0;
      padding: 0;
      max-width: 11.15in;
    }
    .slide li {
      min-height: 0.72in;
      padding: 0.15in 0.18in;
      border: 1px solid rgba(21, 94, 117, 0.18);
      border-left: 0.07in solid #155e75;
      border-radius: 0.1in;
      background: rgba(255, 255, 255, 0.84);
      box-shadow: 0 0.1in 0.32in rgba(15, 37, 63, 0.08);
      color: #172033;
      font-size: 0.2in;
      line-height: 1.28;
    }
    .cover ul,
    .closing ul { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    .cover li,
    .closing li {
      background: rgba(248, 250, 252, 0.1);
      border-color: rgba(248, 250, 252, 0.18);
      border-left-color: #a7f3d0;
      color: #f8fafc;
      box-shadow: none;
    }
    table {
      width: 10.8in;
      border-collapse: collapse;
      margin-top: 0.08in;
      font-size: 0.15in;
      background: rgba(255, 255, 255, 0.92);
      box-shadow: 0 0.1in 0.34in rgba(15, 37, 63, 0.08);
    }
    th {
      background: #0f253f;
      color: #f8fafc;
      text-align: left;
      padding: 0.09in;
    }
    td {
      color: #172033;
      border: 1px solid #d9e2ec;
      padding: 0.08in 0.09in;
    }
    code {
      padding: 0.02in 0.05in;
      border-radius: 0.04in;
      background: #dbeafe;
      color: #0f253f;
      font-family: "SFMono-Regular", Consolas, monospace;
      font-size: 0.9em;
    }
    .code-block {
      max-width: 10.8in;
      padding: 0.18in;
      background: #0f172a;
      color: #dbeafe;
      border-radius: 0.12in;
      font-size: 0.13in;
      line-height: 1.35;
      white-space: pre-wrap;
    }
    .metric-grid,
    .card-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 0.16in;
      max-width: 10.9in;
      margin-top: 0.12in;
    }
    .metric,
    .card {
      padding: 0.2in;
      border: 1px solid rgba(21, 94, 117, 0.2);
      border-radius: 0.12in;
      background: rgba(255, 255, 255, 0.88);
      color: #172033;
      box-shadow: 0 0.1in 0.34in rgba(15, 37, 63, 0.08);
    }
    .metric strong {
      display: block;
      color: #155e75;
      font-size: 0.34in;
      line-height: 1;
      margin-bottom: 0.06in;
    }
    .metric span,
    .card span {
      display: block;
      color: #64748b;
      font-size: 0.16in;
      line-height: 1.3;
    }
    .flow-row {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 0.12in;
      margin-top: 0.16in;
      max-width: 11in;
    }
    .flow-row .step {
      position: relative;
      min-height: 1.08in;
      padding: 0.16in;
      border-radius: 0.12in;
      border: 1px solid rgba(21, 94, 117, 0.2);
      background: rgba(255,255,255,0.9);
      color: #0f253f;
      font-size: 0.18in;
      font-weight: 800;
    }
    .flow-row .step small {
      display: block;
      color: #64748b;
      font-size: 0.13in;
      font-weight: 600;
      line-height: 1.3;
      margin-top: 0.05in;
    }
  `;
}

function findChrome() {
  const candidates = [
    process.env.CHROME_PATH,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ].filter(Boolean);

  for (const candidate of candidates) {
    const result = spawnSync("test", ["-x", candidate]);
    if (result.status === 0) return candidate;
  }

  const which = spawnSync(
    "sh",
    ["-lc", "command -v google-chrome || command -v chromium || command -v chromium-browser"],
    {
      encoding: "utf8",
    },
  );
  const resolved = which.stdout.trim();
  if (resolved) return resolved;
  throw new Error("Chrome/Chromium executable not found. Set CHROME_PATH to generate PDFs.");
}

function printPdf(html, output, kind) {
  const chrome = findChrome();
  const tempDir = mkdtempSync(resolve(tmpdir(), "rwa-docs-"));
  const htmlPath = resolve(tempDir, `${basename(output, ".pdf")}.html`);
  const pdfPath = resolve(output);
  writeFileSync(htmlPath, html);

  const result = spawnSync(
    chrome,
    [
      "--headless=new",
      "--disable-gpu",
      "--disable-dev-shm-usage",
      "--disable-component-update",
      "--disable-default-apps",
      "--disable-extensions",
      "--disable-sync",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-background-networking",
      "--metrics-recording-only",
      "--no-service-autorun",
      "--password-store=basic",
      "--use-mock-keychain",
      `--user-data-dir=${resolve(tempDir, "profile")}`,
      `--print-to-pdf=${pdfPath}`,
      "--no-pdf-header-footer",
      "--print-to-pdf-no-header",
      `file://${htmlPath}`,
    ],
    { encoding: "utf8", timeout: 12000 },
  );

  rmSync(tempDir, { recursive: true, force: true });

  const pdfWasWritten = existsSync(pdfPath) && statSync(pdfPath).size > 1000;
  if (result.status !== 0 && !pdfWasWritten) {
    throw new Error(
      `Chrome failed to render ${kind} PDF ${output}\n${result.stdout}\n${result.stderr}`,
    );
  }
}

for (const job of jobs) {
  const markdown = readFileSync(job.input, "utf8");
  const html =
    job.kind === "deck" ? deckHtml(markdown, job.title) : reportHtml(markdown, job.title);
  printPdf(html, job.output, job.kind);
  console.log(`Wrote ${job.output}`);
}
