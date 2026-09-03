// hydrogen: keep `editor/title` actions in the title bar when NO editor is open.
//
// VS Code's EditorGroupView.createEditorActions() builds the editor/title menu
// only when the group has an active editor pane; an empty group returns nothing,
// so with workbench.editor.editorActionsLocation=titleBar the agent-bar buttons
// (docs/features/ui/agent-bar.md) vanish the moment the last tab closes. This
// patches the minified workbench.js so the empty-group branch builds the SAME
// menu against the group's own scoped context instead (and still re-fires when
// an editor opens). Idempotent (marker) and self-verifying; keeps a .orig.
//
// Cache bust: code-server serves workbench.js under /stable-<commit>/static/
// with max-age=1y and no ETag, so a patched file would never reach a client
// that already loaded the old one (Hydrogen's WKWebView included). The route
// prefix is product.json's `commit`, but the client bakes its own copy of the
// product literal into workbench.js and the websocket handshake refuses a
// client whose commit differs from the server's — so both are rewritten in
// lockstep to sha1(<original commit>:hydrogen:<BUST>). Bump BUST whenever the
// patch output changes; product.json remembers the generation and the pristine
// commit (`hydrogenCacheBust`, `hydrogenOrigCommit`).
//
// usage: node patch-empty-group-actions.cjs <workbench.js> [<product.json>]
// prints one line per step (already | CHANGED | NOMATCH) then a summary line:
//   CHANGED   — something was rewritten (restart code-server)
//   already   — nothing to do
//   NOMATCH   — code-server build no longer fits the regex/literal (exit 2)
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const file = process.argv[2];
const productFile = process.argv[3] || path.resolve(path.dirname(file), '../../../../../product.json');
const MARK = '/*hydrogenEmptyGroupEditorActions*/';
const BUST = 1;
let src = fs.readFileSync(file, 'utf8');
const orig = src;
let nomatch = false;

// --- 1. empty-group editor actions -------------------------------------------
// createEditorActions(e){let t={primary:[],secondary:[]},s;const n=this.activeEditorPane;
//   if(n instanceof fd){const r=n.scopedContextKeyService??this.scopedContextKeyService,
//     o=e.add(this.Y.createMenu(x.EditorTitle,r,{emitEventsForSubmenuChanges:!0,eventDebounceDelay:0}));
//     s=o.onDidChange;const a=(l,c)=>c==="navigation"&&l.actions.length<=1;
//     t=kc(o.getActions({arg:this.D.get(),shouldForwardArgs:!0}),"navigation",a)}
//   else{const r=e.add(new E);s=r.event,e.add(this.onDidActiveEditorChange(()=>r.fire()))}
//   return{actions:t,onDidChange:s}}
// Every identifier is captured from the same match so a re-minified build still fits.
if (src.includes(MARK)) {
  console.log('editorActions: already');
} else {
  const re = new RegExp(
    'createEditorActions\\((\\w+)\\)\\{let (\\w+)=\\{primary:\\[\\],secondary:\\[\\]\\},(\\w+);' +
    'const (\\w+)=this\\.activeEditorPane;if\\(\\4 instanceof \\w+\\)\\{' +
    'const (\\w+)=\\4\\.scopedContextKeyService\\?\\?this\\.scopedContextKeyService,' +
    '(\\w+)=\\1\\.add\\(this\\.(\\w+)\\.createMenu\\((\\w+)\\.EditorTitle,\\5,(\\{[^}]*\\})\\)\\);' +
    '\\3=\\6\\.onDidChange;const (\\w+)=(\\([^)]*\\)=>[^;]+);' +
    '\\2=(\\w+)\\(\\6\\.getActions\\(\\{arg:this\\.\\w+\\.get\\(\\),shouldForwardArgs:!0\\}\\),"navigation",\\10\\)\\}' +
    'else\\{const (\\w+)=\\1\\.add\\(new (\\w+)\\);\\3=\\13\\.event,\\1\\.add\\(this\\.onDidActiveEditorChange\\(\\(\\)=>\\13\\.fire\\(\\)\\)\\)\\}'
  );
  const m = src.match(re);
  if (!m) {
    console.log('editorActions: NOMATCH'); nomatch = true;
  } else {
    const [whole, e, t, s, , , , svc, menuId, opts, , pred, fill, r, emitter] = m;
    const elseNew =
      `else{${MARK}const ${r}=${e}.add(new ${emitter});${s}=${r}.event;` +
      `const o=${e}.add(this.${svc}.createMenu(${menuId}.EditorTitle,this.scopedContextKeyService,${opts}));` +
      `${e}.add(o.onDidChange(()=>${r}.fire()));${e}.add(this.onDidActiveEditorChange(()=>${r}.fire()));` +
      `${t}=${fill}(o.getActions({shouldForwardArgs:!0}),"navigation",${pred})}`;
    const elseOld = whole.slice(whole.indexOf('else{'));
    src = src.replace(whole, whole.replace(elseOld, elseNew));
    console.log('editorActions: CHANGED');
  }
}

// --- 2. cache bust (product.json + baked client literal, in lockstep) ---------
const product = JSON.parse(fs.readFileSync(productFile, 'utf8'));
if (product.hydrogenCacheBust === BUST) {
  console.log('cacheBust: already');
} else if (!/^[0-9a-f]{40}$/.test(product.commit || '')) {
  console.log('cacheBust: NOMATCH'); nomatch = true;
} else {
  const cur = product.commit;
  const origCommit = product.hydrogenOrigCommit || cur;
  const next = crypto.createHash('sha1').update(`${origCommit}:hydrogen:${BUST}`).digest('hex');
  const lit = `commit:"${cur}"`;
  if (src.split(lit).length !== 2) {
    console.log('cacheBust: NOMATCH'); nomatch = true;
  } else {
    src = src.replace(lit, `commit:"${next}"`);
    product.commit = next;
    product.hydrogenOrigCommit = origCommit;
    product.hydrogenCacheBust = BUST;
    fs.writeFileSync(productFile, JSON.stringify(product, null, 2) + '\n');
    console.log(`cacheBust: CHANGED (${cur.slice(0, 8)} -> ${next.slice(0, 8)})`);
  }
}

if (nomatch) { console.log('NOMATCH'); process.exit(2); }
if (src === orig) { console.log('already'); process.exit(0); }
if (!fs.existsSync(file + '.orig')) fs.copyFileSync(file, file + '.orig');
fs.writeFileSync(file, src);
console.log('CHANGED');
