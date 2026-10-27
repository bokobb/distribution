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

  // приём кассы: разница считается сразу при вводе
  var counted = document.getElementById('counted');
  var diffBox = document.getElementById('diff');
  if (counted && diffBox) {
    var expected = parseInt(counted.getAttribute('data-expected'), 10) || 0;
    var fmt = function (n) { return Math.abs(n).toLocaleString('ru-RU') + ' ₸'; };
    var upd = function () {
      var v = parseInt(counted.value.replace(/\D/g, ''), 10);
      if (isNaN(v)) { diffBox.hidden = true; return; }
      var d = v - expected;
      diffBox.hidden = false;
      diffBox.className = 'diff ' + (d < 0 ? 'diff--bad' : 'diff--ok');
      diffBox.firstElementChild.textContent = d < 0 ? 'Недостача на экспедиторе' : d > 0 ? 'Излишек' : 'Касса сходится';
      diffBox.lastElementChild.textContent = d === 0 ? '0 ₸' : (d < 0 ? '−' : '+') + fmt(d);
    };
    counted.addEventListener('input', upd);
    upd();
  }
})();
