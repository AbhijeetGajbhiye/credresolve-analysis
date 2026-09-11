const { Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell,
        WidthType, ShadingType, BorderStyle, AlignmentType } = require("docx");
const fs = require("fs");

const FONT = "Calibri";

function p(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 120, ...(opts.spacing || {}) },
    children: [new TextRun({ text, font: FONT, size: 21, bold: !!opts.bold, italics: !!opts.italics })],
    ...opts.pOpts,
  });
}

function h(text) {
  return new Paragraph({
    spacing: { before: 200, after: 80 },
    children: [new TextRun({ text, font: FONT, size: 24, bold: true, color: "1F4E79" })],
  });
}

function cell(text, opts = {}) {
  return new TableCell({
    width: { size: opts.width || 2000, type: WidthType.DXA },
    shading: opts.shade ? { type: ShadingType.CLEAR, fill: opts.shade } : undefined,
    children: [new Paragraph({ children: [new TextRun({ text, font: FONT, size: 19, bold: !!opts.bold })] })],
  });
}

const roiTable = new Table({
  width: { size: 9350, type: WidthType.DXA },
  columnWidths: [3350, 3000, 3000],
  rows: [
    new TableRow({ children: [
      cell("Metric", { bold: true, shade: "1F4E79", width: 3350 }),
      cell("Base case", { bold: true, shade: "1F4E79", width: 3000 }),
      cell("Downside case", { bold: true, shade: "1F4E79", width: 3000 }),
    ]}),
    new TableRow({ children: [
      cell("Incremental recovery / year", { width: 3350 }),
      cell("Rs 15-25 Cr", { width: 3000 }),
      cell("Rs 3-5 Cr", { width: 3000 }),
    ]}),
    new TableRow({ children: [
      cell("Cost", { width: 3350 }),
      cell("Rs 10 Cr", { width: 3000 }),
      cell("Rs 10 Cr", { width: 3000 }),
    ]}),
    new TableRow({ children: [
      cell("Year 1 ROI", { width: 3350 }),
      cell("~150-250%", { width: 3000 }),
      cell("~0-30%", { width: 3000 }),
    ]}),
    new TableRow({ children: [
      cell("Break-even", { width: 3350 }),
      cell("3-4 months", { width: 3000 }),
      cell("9-12 months", { width: 3000 }),
    ]}),
  ],
});

const doc = new Document({
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 900, bottom: 900, left: 1000, right: 1000 },
      },
    },
    children: [
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { after: 40 },
        children: [new TextRun({ text: "EXECUTIVE MEMO", font: FONT, size: 30, bold: true, color: "1F4E79" })],
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { after: 200 },
        children: [new TextRun({ text: "Is the Reported 11% Recovery Improvement Real?", font: FONT, size: 24, italics: true })],
      }),
      p("To: Leadership Team    |    From: Data Analytics    |    Re: Monthly recovery performance, Jan-Jul 2026", { bold: true }),

      h("What happened?"),
      p("Collections performance from January through July 2026 was flat. The commonly cited \u201C11% month on month improvement\u201D compares February's raw recovered amount to March's, and February simply has three fewer days than March. Once we adjust for the length of the month, that same comparison becomes a 0.3% change, which is noise. Every properly built metric we tested (contact rate, right party contact rate, promise to pay rate, promise kept rate, and recovery per account) moved in a narrow band all year with no sustained trend up or down."),

      h("Why did it happen?"),
      p("We checked portfolio mix, DPD, loan type, channel, telephony vendor, calling time of day, attempt number, and agent tenure. None of them explain meaningful variation, because there is essentially no variation to explain. What we did find, and what matters most, is a coverage gap: about 22% of the loan book (6,656 accounts, roughly Rs 231 crore outstanding) has never been assigned to any collection activity in the period we reviewed. These accounts look just like the ones we are working today: same risk mix, same average days past due, same average balance. They are simply not being worked."),

      h("How confident are we?"),
      p("High confidence that the reported 11% is a calendar artifact rather than real improvement; this is a direct calculation once results are normalized by days in the month. High confidence that the coverage gap is real, since the untouched and worked populations match on every dimension we can check. Lower confidence on exactly how much recovery the untouched accounts would generate once worked, since this is an extrapolation from similar-looking accounts rather than a controlled test."),

      h("What should we do?"),
      p("Invest the Rs 10 crore in AI voice automation, aimed first at the untouched 22% of the book, with remaining capacity used to increase attempt frequency on accounts already being worked (connect rate does not decline across repeat attempts in our data, so added volume should keep converting near current rates). Before committing the full amount, run a 60-90 day pilot: split the untouched accounts into a treated group and a control group, measure actual results, then scale spend based on what is observed rather than what is assumed."),

      h("What is the expected financial impact?"),
      p("Based on the current recovery rate per worked account, extending equivalent coverage to the untouched accounts could add Rs 15-25 crore a year in the base case, and as much as Rs 45-60 crore if the untouched accounts convert exactly like the existing book. Against a Rs 10 crore investment, that is a year one return of roughly 150-250%, with break-even inside 3-4 months. The downside case, if AI voice underperforms or the untouched accounts turn out to be untouched for a reason not visible in this data, brings that down to Rs 3-5 crore a year. The pilot resolves this uncertainty quickly and cheaply before the full spend is committed.", { spacing: { after: 100 } }),

      roiTable,

      p("Full analysis, data quality findings, and methodology: see the accompanying notebook, SQL repository, and data quality report.", { italics: true, spacing: { before: 200 } }),
    ],
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync("executive_memo.docx", buf);
  console.log("Written executive_memo.docx");
});
