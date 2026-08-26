import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const iconDir = resolve(scriptDir, "../src-tauri/icons");
const iconBase64 =
  "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAANjSURBVHgB7VZBbtpQEJ0xUdVFq5AbGAXSdBXIoklUKZATND1ByAnqngBzAsgJQk6Q9ASYLkKyCXTVqhDhniBEyiKtwNP5tgH728YGlu2TwPb3/Hnvz5+Zb4B/HQgrgpr5NF8mPxOPusNF5i8lwCZVFI3vTvhRlV6bgGjA2KqyGDPO18IC6OtuGYhq4Kw4zn0Vi3f6XAtYhLy1q/N/xT9IJv8briCVV5/3M2AdD+8+w6oCOOxlUPDcQ2zws46HnZZkxyKgwsRlD01kJBIJsJ0q2ITpfpOOxW41Zo7Gc2rTAYuOOCcM2U6BJEgpIuxpXnWDXZfjyAWYrM629ZkPrITaQQKICMzLaLcUQS5Bp1pwAJOEtWhDtkkUAUG+eds/3rzpnwfIRWIq+CB+XCE1aR6Tiai5SEFRnh8rINvulXI3/QESXSKQ6iNv5ku+qiDSqJU/8Tmw4NvsfaBnzBfA5DpvUpNcYgI0JRM1ZJo8Znru04kFZK97ml1OMxjK2DqTzK4CExG6EsOO52mYSMB2eyAayowcqd7fzx313m/5nNt7bNFHDn3XaUik4WH3i1+QMmtMiF0I6A0B7/k5h70s7vnauN/fOoUl4PaPgfs4xGJnQ7YJREDtDNITcmYfjmkcW/ORcPqHq4auwkzWAgPPo/wkLoR0Ze6/Nb3vRW6gQp8IYchCq/d7b0Idc3nWmbTsPpq8mGoiARyTIhu7QJ9z0QvESUhCIYn9w0u109kwC4Vpctmlabdg8hxK3LojGtncMkTFn7XcB3Zkm9Sf1x/8A3byesk1bt0XEIG5AohQ9Qmw6Jdsg2gfx2HgDxMoMfkZzEFAgJcEwfKd7b2DrQYPOgcMJyjf6/13uZakuusQdzLyUR2GQBmKKlj7PXqYkIxePmW8e+zYdOyOJo/7fHAy9w9yBsQgEAGzkBFODVcei3lVCdoUhmHkufbPcvamd7n2PB7YyZwA4TngLxkte/1DgxiIc4PQ/mI6JrSGI2t0AQkQ+T2Qve1VWIg+04SNMaWq5kHGlIhL7plRmtry59j9XnY1Aa6IGjP7V4+i7zunIpdlnoWpkke9v5dL3D1jv4jkSESCE5YU6zSqMy4tQGC7/V0dY8oOc2DFImERjNGLp7OoqlhZgBeiBJHW18U94ePjMqT/4cVfZNp1ptgvGtYAAAAASUVORK5CYII=";

mkdirSync(iconDir, { recursive: true });
const png = Buffer.from(iconBase64, "base64");
writeFileSync(resolve(iconDir, "icon.png"), png);

const icoHeader = Buffer.alloc(22);
icoHeader.writeUInt16LE(0, 0);
icoHeader.writeUInt16LE(1, 2);
icoHeader.writeUInt16LE(1, 4);
icoHeader.writeUInt8(32, 6);
icoHeader.writeUInt8(32, 7);
icoHeader.writeUInt16LE(1, 10);
icoHeader.writeUInt16LE(32, 12);
icoHeader.writeUInt32LE(png.length, 14);
icoHeader.writeUInt32LE(22, 18);
writeFileSync(resolve(iconDir, "icon.ico"), Buffer.concat([icoHeader, png]));
