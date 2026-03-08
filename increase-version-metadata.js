const fs = require('fs');
const version = process.argv[2];

const metadataPath = './metadata.json';
const metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));

metadata.version = metadata.version + 1
metadata["version-name"] = version

fs.writeFileSync(metadataPath, JSON.stringify(metadata, null, 2));
