(function(){
  var rows = Array.prototype.slice.call(document.querySelectorAll('.log-row'));
  var chips = Array.prototype.slice.call(document.querySelectorAll('.lvl-chip'));
  var search = document.getElementById('logSearch');
  var comp = document.getElementById('logComp');
  var shownEl = document.getElementById('logShown');

  function activeLevels(){
    var s = {};
    chips.forEach(function(c){ if(c.classList.contains('active')){ s[c.getAttribute('data-level')] = true; } });
    return s;
  }
  function apply(){
    if(!rows.length) return;
    var lv = activeLevels();
    var q = (search && search.value ? search.value : '').toLowerCase();
    var cp = comp ? comp.value : 'ALL';
    var shown = 0, i, r, vis;
    for(i=0;i<rows.length;i++){
      r = rows[i];
      vis = !!lv[r.getAttribute('data-level')]
        && (cp === 'ALL' || r.getAttribute('data-comp') === cp)
        && (q === '' || (r.getAttribute('data-text') || '').indexOf(q) >= 0);
      r.style.display = vis ? '' : 'none';
      if(vis) shown++;
    }
    if(shownEl) shownEl.textContent = shown;
  }
  chips.forEach(function(c){ c.addEventListener('click', function(){ c.classList.toggle('active'); apply(); }); });
  if(search) search.addEventListener('input', apply);
  if(comp) comp.addEventListener('change', apply);
  apply();

  var tt = document.getElementById('themeToggle');
  function setToggleLabel(theme){ if(tt) tt.innerHTML = (theme === 'light') ? '☾ Dark' : '☀ Light'; }
  if(tt){
    tt.addEventListener('click', function(){
      var cur = (document.body.getAttribute('data-theme') === 'light') ? 'dark' : 'light';
      document.body.setAttribute('data-theme', cur);
      setToggleLabel(cur);
      try{ localStorage.setItem('wmreport-theme', cur); }catch(e){}
    });
    try{
      var saved = localStorage.getItem('wmreport-theme');
      if(saved){ document.body.setAttribute('data-theme', saved); setToggleLabel(saved); }
    }catch(e){}
  }
})();
