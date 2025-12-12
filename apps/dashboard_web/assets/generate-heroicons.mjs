import fs from 'fs';
import path from 'path';

// Path to heroicons - use absolute path based on script location
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const iconsDir = path.resolve(__dirname, '../../../deps/heroicons/optimized');
let css = '/* Heroicons - auto-generated for Tailwind v4 */\n';

const icons = [
  ['', '24/outline'],      // hero-icon-name (default outline)
  ['-solid', '24/solid'],  // hero-icon-name-solid
  ['-mini', '20/solid'],   // hero-icon-name-mini
  ['-micro', '16/solid'],  // hero-icon-name-micro
];

let totalIcons = 0;

icons.forEach(([suffix, dir]) => {
  const fullDir = path.join(iconsDir, dir);
  if (!fs.existsSync(fullDir)) {
    console.log(`Skipping ${fullDir} - directory not found`);
    return;
  }
  fs.readdirSync(fullDir).forEach((file) => {
    if (!file.endsWith('.svg')) return;

    const name = path.basename(file, '.svg') + suffix;
    const fullPath = path.join(fullDir, file);
    const content = fs
      .readFileSync(fullPath)
      .toString()
      .replace(/\r?\n|\r/g, '')
      .replace(/"/g, "'")
      .replace(/#/g, '%23');

    // Determine default size based on icon type
    let defaultSize = '1.5rem'; // 24px icons
    if (suffix === '-mini') defaultSize = '1.25rem'; // 20px icons
    if (suffix === '-micro') defaultSize = '1rem'; // 16px icons

    css += `.hero-${name} {
  -webkit-mask-image: url("data:image/svg+xml;utf8,${content}");
  mask-image: url("data:image/svg+xml;utf8,${content}");
  -webkit-mask-repeat: no-repeat;
  mask-repeat: no-repeat;
  -webkit-mask-size: 100% 100%;
  mask-size: 100% 100%;
  background-color: currentColor;
  vertical-align: middle;
  display: inline-block;
  width: ${defaultSize};
  height: ${defaultSize};
  flex-shrink: 0;
}
`;
    totalIcons++;
  });
});

const outputPath = path.resolve(__dirname, './css/heroicons.css');
fs.writeFileSync(outputPath, css);
console.log(`Generated heroicons.css with ${totalIcons} icons at ${outputPath}`);
