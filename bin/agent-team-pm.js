#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const source = path.resolve(__dirname, '..');
const manifestName = '.agent-team-pm-install.json';
const roots = ['SKILL.md', 'scripts', 'references', 'templates'];

function inventory(dir, names = fs.readdirSync(dir)) {
  const result = {};
  function walk(relative) {
    if (relative === manifestName) return;
    const absolute = path.join(dir, relative);
    const st = fs.lstatSync(absolute);
    if (st.isSymbolicLink()) result[relative] = `link:${fs.readlinkSync(absolute)}`;
    else if (st.isDirectory()) fs.readdirSync(absolute).sort().forEach(n => walk(path.join(relative, n)));
    else result[relative] = `${crypto.createHash('sha256').update(fs.readFileSync(absolute)).digest('hex')}:${st.mode & 0o777}`;
  }
  names.forEach(walk);
  return result;
}
function changes(before, after) {
  return [...new Set([...Object.keys(before), ...Object.keys(after)])].sort()
    .filter(p => before[p] !== after[p])
    .map(p => `${!(p in before) ? 'A' : !(p in after) ? 'D' : 'M'} ${p}`);
}
function exists(p) { try { fs.lstatSync(p); return true; } catch (e) { if (e.code === 'ENOENT') return false; throw e; } }
function main() {
  const args = process.argv.slice(2);
  const command = args.shift();
  let force = false, skills = path.join(os.homedir(), '.claude', 'skills');
  while (args.length) {
    const arg = args.shift();
    if (arg === '--force') force = true;
    else if (arg === '--dir' && args.length) skills = path.resolve(args.shift());
    else throw new Error(`Unknown or incomplete option: ${arg}`);
  }
  if (!['install', 'uninstall', 'doctor'].includes(command)) {
    console.log('Usage: agent-team-pm install|uninstall|doctor [--force] [--dir <skills dir>]');
    process.exitCode = command && !['--help', '-h'].includes(command) ? 1 : 0;
    return;
  }
  const target = path.join(skills, 'agent-team-pm');
  const link = path.join(os.homedir(), '.local', 'bin', 'team');
  const desiredLink = path.join(target, 'scripts', 'team');
  function ownsLink() { return exists(link) && fs.lstatSync(link).isSymbolicLink() && path.resolve(path.dirname(link), fs.readlinkSync(link)) === desiredLink; }
  function dependencies() {
    let ok = true;
    for (const cmd of ['herdr', 'jq', 'git', 'python3', 'bash', 'perl', 'rsync']) {
      const found = spawnSync('/bin/sh', ['-c', 'command -v "$1" >/dev/null 2>&1', 'doctor', cmd]).status === 0;
      console.log(`${found ? 'OK' : 'MISSING'} ${cmd}`); ok = ok && found;
    }
    return ok;
  }
  function checkInstalled() {
    if (!exists(target)) return;
    if (!fs.lstatSync(target).isDirectory() || fs.lstatSync(target).isSymbolicLink()) throw new Error(`Refusing non-directory or symlink: ${target}`);
    const actual = inventory(target);
    let baseline;
    try { baseline = JSON.parse(fs.readFileSync(path.join(target, manifestName), 'utf8')).files; }
    catch { baseline = inventory(source, roots); }
    if (!baseline || typeof baseline !== 'object' || Array.isArray(baseline)) throw new Error('Invalid install manifest; inspect the installed copy');
    const diff = changes(baseline, actual);
    if (diff.length) {
      console.log(`Installed copy differs from ${exists(path.join(target, manifestName)) ? 'its install manifest' : 'this package'}:\n${diff.join('\n')}`);
      if (!force) throw new Error('Installed copy has changes; inspect the diff summary and rerun with --force to replace/remove it');
    }
  }
  if (command === 'doctor') {
    let ok = dependencies();
    if (!exists(target)) { console.log(`MISSING skill ${target}`); ok = false; }
    else {
      try { checkInstalled(); console.log(`OK skill ${target}`); }
      catch (e) { console.log(e.message); ok = false; }
    }
    console.log(`${ownsLink() ? 'OK' : 'MISSING or foreign'} team link ${link}`);
    ok = ok && ownsLink();
    console.log(`PATH: add ${path.dirname(link)} to PATH if needed`);
    process.exitCode = ok ? 0 : 1;
    return;
  }
  checkInstalled();
  if (command === 'uninstall') {
    if (ownsLink()) fs.unlinkSync(link);
    if (exists(target)) fs.rmSync(target, { recursive: true });
    console.log(`Uninstalled ${target}; removed its team link if owned`);
    return;
  }
  if (exists(link) && !ownsLink() && !force) throw new Error(`Existing team command at ${link}; use --force to replace it`);
  if (exists(link) && fs.lstatSync(link).isDirectory()) throw new Error(`Refusing to replace directory ${link}`);
  fs.mkdirSync(skills, { recursive: true });
  const staging = fs.mkdtempSync(path.join(skills, '.agent-team-pm-'));
  try {
    for (const name of roots) fs.cpSync(path.join(source, name), path.join(staging, name), { recursive: true, preserveTimestamps: true });
    fs.writeFileSync(path.join(staging, manifestName), JSON.stringify({ version: require('../package.json').version, files: inventory(staging) }, null, 2) + '\n');
    if (exists(target)) fs.rmSync(target, { recursive: true });
    fs.renameSync(staging, target);
  } finally { if (exists(staging)) fs.rmSync(staging, { recursive: true }); }
  fs.mkdirSync(path.dirname(link), { recursive: true });
  if (exists(link)) fs.unlinkSync(link);
  fs.symlinkSync(desiredLink, link);
  console.log(`Installed skill: ${target}\nLinked team: ${link} -> ${desiredLink}\nPATH: add ${path.dirname(link)} to PATH if needed`);
  if (!dependencies()) console.log('Install complete; install the missing prerequisites before running the skill');
}
try { main(); } catch (e) { console.error(`agent-team-pm: ${e.message}`); process.exitCode = 1; }
