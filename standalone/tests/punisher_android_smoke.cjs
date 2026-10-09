#!/usr/bin/env node
/* Self-contained smoke test for packaged Android HTML / offline controls. */
const fs = require('node:fs');
const assert = require('node:assert/strict');
const html = fs.readFileSync('PunisherAndroid/app/src/main/assets/index.html', 'utf8');
const scripts = [...html.matchAll(/<script(?: [^>]*)?>([\s\S]*?)<\/script>/g)];
assert(scripts.length >= 1, 'Expected inline application JavaScript');
for (const [, body] of scripts) new Function(body); // syntax check on every inline script

const start = html.indexOf('function plateHtml(v,preview){');
const end = html.indexOf('function vehiclePic(v,cls)', start);
assert(start >= 0 && end > start, 'Plate renderer not found');

const code = html.slice(start, end);
const plateHtml = new Function('migratePlate', 'visualMeta', 'esc',
  code + '\nreturn plateHtml;'
)(
  () => {},
  () => ({ plateX: .52, plateY: .70, plateW: .10, plateAngle: -2 }),
  (s) => String(s)
);
const v = {
  plateGovernorateCode: '14', plateLetter: 'A', plateNumber: '555555',
  plateShiftX: .02, plateShiftY: -.05, plateScale: 1.5, plateAngleOffset: 3
};
const plate = plateHtml(v, false);
assert(plate.includes('left:54.00%'), 'Plate X correction lost');
assert(plate.includes('top:65.00%'), 'Plate Y correction lost');
assert(plate.includes('width:15.00%'), 'Plate scale correction lost');
assert(plate.includes('rotate(1.00deg)'), 'Plate angle correction lost');
assert(plate.includes('555555'), 'Six digits should remain in plate');
assert(plateHtml(v, true).includes('iraq-plate-preview'), 'Preview plate missing');

assert(html.includes('class="vehicle-media"'), 'Vehicle image lacks relative coordinate frame');
assert(html.includes('id="fitScale"') || html.includes("'fitScale'"), 'Plate slider missing');
assert(html.includes('refreshAppearancePreview'), 'Live preview missing');
assert(html.includes('class="ctrl red" disabled'), 'Unwired car controls must be disabled');
assert(!html.includes("v.espDeviceID?'Online'"), 'ESP link is not proof of online status');
console.log('PASS: Android JavaScript syntax, plate geometry, 6 digits, live preview and safe statuses');
