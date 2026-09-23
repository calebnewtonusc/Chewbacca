// Every visible control on the page as role and name, the vocabulary a click goes by.
// chrome-js cannot reach Playwright's aria_snapshot inside the person's own Chrome, so
// this rebuilds the part of it a pointer needs: role from the tag or [role], name from
// aria-label, then visible text, then placeholder or title.
(function () {
  var INVISIBLE = /[​-‏⁠﻿]/g;
  function role(e) {
    var r = e.getAttribute('role');
    if (r) return r;
    var t = e.tagName.toLowerCase();
    if (t === 'a') return 'link';
    if (t === 'button' || t === 'summary') return 'button';
    if (t === 'select') return 'combobox';
    if (t === 'textarea') return 'textbox';
    if (t === 'input') {
      var ty = (e.type || 'text').toLowerCase();
      if (ty === 'checkbox' || ty === 'radio') return ty;
      if (ty === 'search') return 'searchbox';
      if (ty === 'submit' || ty === 'button') return 'button';
      if (ty === 'hidden') return null;
      return 'textbox';
    }
    if (e.isContentEditable) return 'textbox';
    return null;
  }
  function name(e) {
    var n = e.getAttribute('aria-label') || '';
    if (!n) { var by = e.getAttribute('aria-labelledby'); if (by) n = by.split(' ').map(function (id) { var x = document.getElementById(id); return x ? x.innerText : ''; }).join(' '); }
    if (!n) n = (e.innerText || '').split('\n').map(function (s) { return s.trim(); }).filter(Boolean).join(' ');
    if (!n) n = e.getAttribute('placeholder') || e.getAttribute('title') || e.value || '';
    return n.replace(INVISIBLE, '').replace(/\s+/g, ' ').trim().slice(0, 120);
  }
  function visible(e) {
    var r = e.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    var s = getComputedStyle(e);
    return s.visibility !== 'hidden' && s.display !== 'none';
  }
  var sel = 'a,button,summary,select,textarea,input,[role=button],[role=link],[role=tab],[role=menuitem],[role=checkbox],[role=radio],[role=combobox],[role=switch],[role=option],[contenteditable=true]';
  var seen = {}, controls = [];
  document.querySelectorAll(sel).forEach(function (e) {
    if (!visible(e)) return;
    var r = role(e); if (!r) return;
    var n = name(e); if (!n) return;
    var k = r + ': ' + n; if (seen[k]) return; seen[k] = 1;
    controls.push({ role: r, name: n });
  });
  var headings = Array.from(document.querySelectorAll('h1,h2,h3')).filter(visible).map(function (h) { return h.innerText.replace(/\s+/g, ' ').trim(); }).filter(Boolean).slice(0, 40);
  return JSON.stringify({ url: location.href, title: document.title, headings: headings, controls: controls });
})()
