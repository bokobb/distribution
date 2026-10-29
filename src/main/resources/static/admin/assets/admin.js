// Админка «Дистрибуция»: меню на телефоне, выбор компании, всплывающая строка, подтверждение действий.
(function () {
  var app = document.getElementById('app');
  var burger = document.getElementById('burger');
  var sideX = document.getElementById('side-x');
  var scrim = document.getElementById('scrim');

  function menu(open) {
    if (!app) return;
    app.classList.toggle('menu-open', open);
    if (burger) burger.setAttribute('aria-expanded', open ? 'true' : 'false');
  }
  if (burger) burger.addEventListener('click', function () { menu(true); });
  if (sideX) sideX.addEventListener('click', function () { menu(false); });
  if (scrim) scrim.addEventListener('click', function () { menu(false); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      menu(false);
      document.querySelectorAll('.me[open], .dd[open]').forEach(function (d) { d.removeAttribute('open'); });
    }
  });

  // выбор компании в шапке — сразу переходим
  var scope = document.getElementById('scope-sel');
  if (scope) scope.addEventListener('change', function () { scope.form.submit(); });

  // меню пользователя и выпадающие фильтры закрываются кликом мимо
  document.addEventListener('click', function (e) {
    document.querySelectorAll('.me[open], .dd[open]').forEach(function (d) {
      if (!d.contains(e.target)) d.removeAttribute('open');
    });
  });

  // всплывающая строка после действия
  var toast = document.getElementById('toast');
  if (toast && toast.textContent.trim()) {
    toast.hidden = false;
    setTimeout(function () { toast.hidden = true; }, 5000);
  }

  // кнопки с data-confirm спрашивают перед отправкой формы
  document.addEventListener('submit', function (e) {
    var btn = e.submitter;
    var text = (btn && btn.getAttribute('data-confirm')) || e.target.getAttribute('data-confirm');
    if (text && !window.confirm(text)) e.preventDefault();
  });

  // галочки списка: «выбрать все на странице» и строка внизу — сколько выбрано и на какую сумму
  var all = document.querySelector('[data-check-all]');
  if (all) {
    var name = all.getAttribute('data-check-all');
    var bar = document.getElementById('bulk-bar');
    var boxes = function () { return document.querySelectorAll('input[type=checkbox][name="' + name + '"]'); };
    var sync = function () {
      var list = boxes(), n = 0, sum = 0;
      list.forEach(function (b) {
        var tr = b.closest('tr');
        if (tr) tr.classList.toggle('is-sel', b.checked);
        if (b.checked) { n++; sum += parseInt(b.getAttribute('data-sum'), 10) || 0; }
      });
      all.checked = list.length > 0 && n === list.length;
      all.indeterminate = n > 0 && n < list.length;
      if (bar) {
        bar.hidden = n === 0;
        bar.querySelector('[data-sel-count]').textContent = n;
        bar.querySelector('[data-sel-sum]').textContent = sum.toLocaleString('ru-RU') + ' ₸';
      }
    };
    all.addEventListener('change', function () {
      boxes().forEach(function (b) { b.checked = all.checked; });
      sync();
    });
    document.addEventListener('change', function (e) { if (e.target.name === name) sync(); });
    sync();
  }

  // приём кассы: разница считается сразу при вводе; недостача больше допуска — открывается решение директора
  var counted = document.getElementById('counted');
  var diffBox = document.getElementById('diff');
  if (counted && diffBox) {
    var expected = parseInt(counted.getAttribute('data-expected'), 10) || 0;
    var tol = parseInt(counted.getAttribute('data-tolerance'), 10) || 0;
    var shortBox = document.getElementById('shortage');
    var fmt = function (n) { return Math.abs(n).toLocaleString('ru-RU') + ' ₸'; };
    var upd = function () {
      var v = parseInt(counted.value.replace(/\D/g, ''), 10);
      if (isNaN(v)) { diffBox.hidden = true; if (shortBox) shortBox.hidden = true; return; }
      var d = v - expected, big = d < -tol;
      diffBox.hidden = false;
      diffBox.className = 'diff ' + (big ? 'diff--bad' : d === 0 ? 'diff--ok' : 'diff--warn');
      diffBox.firstElementChild.textContent = d === 0 ? 'Сошлось'
        : d < 0 ? (big ? 'Недостача — больше допуска ' + fmt(tol) : 'Недостача в пределах допуска')
        : (d > tol ? 'Излишек — больше допуска' : 'Излишек в пределах допуска');
      diffBox.lastElementChild.textContent = d === 0 ? '0 ₸' : (d < 0 ? '−' : '+') + fmt(d);
      if (shortBox) {
        shortBox.hidden = !big;
        var after = shortBox.querySelector('[data-debt]');
        if (after) after.textContent = fmt((parseInt(after.getAttribute('data-debt'), 10) || 0) - d);
      }
    };
    counted.addEventListener('input', upd);
    upd();
  }
})();
