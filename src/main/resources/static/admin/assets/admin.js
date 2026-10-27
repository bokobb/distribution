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
      var me = document.querySelector('.me[open]');
      if (me) me.removeAttribute('open');
    }
  });

  // выбор компании в шапке — сразу переходим
  var scope = document.getElementById('scope-sel');
  if (scope) scope.addEventListener('change', function () { scope.form.submit(); });

  // меню пользователя закрывается кликом мимо
  document.addEventListener('click', function (e) {
    var me = document.querySelector('.me[open]');
    if (me && !me.contains(e.target)) me.removeAttribute('open');
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
