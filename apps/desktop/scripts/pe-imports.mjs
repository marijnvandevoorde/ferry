// The DLL names a Windows executable or DLL imports (its import and delay-load tables), read from the PE file.
import { readFileSync } from "node:fs";

export function dllImports(file) {
  const pe = readFileSync(file);
  const header = pe.readUInt32LE(0x3c);
  if (pe.toString("latin1", header, header + 4) !== "PE\0\0") throw new Error(`${file} isn't a PE file`);
  const sections = pe.readUInt16LE(header + 6);
  const optional = header + 24;
  const directories = optional + (pe.readUInt16LE(optional) === 0x20b ? 112 : 96);
  const sectionTable = optional + pe.readUInt16LE(header + 20);

  const offset = (rva) => {
    for (let i = 0; i < sections; i++) {
      const s = sectionTable + i * 40;
      const address = pe.readUInt32LE(s + 12);
      const size = Math.max(pe.readUInt32LE(s + 8), pe.readUInt32LE(s + 16));
      if (rva >= address && rva < address + size) return rva - address + pe.readUInt32LE(s + 20);
    }
    throw new Error(`${file}: address ${rva} is in no section`);
  };
  const name = (rva) => {
    const start = offset(rva);
    return pe.toString("latin1", start, pe.indexOf(0, start));
  };

  const names = [];
  // Import descriptors are 20 bytes with the name at +12; delay-load descriptors 32 bytes with it at +4.
  for (const [index, size, at] of [[1, 20, 12], [13, 32, 4]]) {
    const rva = pe.readUInt32LE(directories + index * 8);
    if (!rva) continue;
    for (let d = offset(rva); pe.readUInt32LE(d + at); d += size) names.push(name(pe.readUInt32LE(d + at)));
  }
  return names;
}
