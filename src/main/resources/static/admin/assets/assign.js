// «Закрепление магазинов»: точки магазинов на карте (Leaflet + OpenStreetMap). Нажатие на точку отмечает магазин в
// списке (магазин другого торгового появляется в списке строкой), галочка в списке подсвечивает точку.
(function () {
  var el = document.getElementById('assign-map');
  var form = document.getElementById('assign-form');
  if (!el || !form || !window.L) return;
  var shops = JSON.parse(el.getAttribute('data-shops') || '[]');
  var agent = Number(el.getAttribute('data-agent'));
  var css = getComputedStyle(document.documentElement);
  var ACCENT = css.getPropertyValue('--accent').trim() || '#4136F1';
  var WARN = css.getPropertyValue('--warn-dot').trim() || '#E39B2D';
  var OTHER = '#A9AFB8';

  var map = L.map(el, { scrollWheelZoom: true });
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">участники OpenStreetMap</a>'
  }).addTo(map);

  function row(id) { return form.querySelector('tr[data-id="' + id + '"]'); }
  function box(id) { var r = row(id); return r && r.querySelector('input[name=ids]'); }

  var markers = {};
  function fill(s) { return s.agent === agent ? ACCENT : s.agent === 0 ? WARN : OTHER; }
  function paint(s) {
    var b = box(s.id), on = b && b.checked;
    markers[s.id].setStyle({ radius: on ? 8 : 6, color: on ? ACCENT : '#fff', weight: on ? 3 : 1.5,
      fillColor: on ? '#fff' : fill(s), fillOpacity: on ? 1 : 0.9 });
  }

  // вид — до точек: Leaflet не рисует слой на карте без вида
  if (shops.length) map.fitBounds(shops.map(function (s) { return [s.lat, s.lng]; }), { padding: [24, 24], maxZoom: 15 });
  else map.setView([43.24, 76.89], 11);

  shops.forEach(function (s) {
    var m = L.circleMarker([s.lat, s.lng]).addTo(map).bindTooltip(s.name);
    markers[s.id] = m;
    paint(s);
    m.on('click', function () {
      var b = box(s.id);
      if (!b) return;
      b.checked = !b.checked;
      row(s.id).hidden = false;
      update();
    });
  });
  var sel = document.getElementById('assign-sel');
  function update() {
    var n = 0;
    form.querySelectorAll('tr[data-id]').forEach(function (r) {
      var b = r.querySelector('input[name=ids]');
      r.classList.toggle('is-sel', b.checked);
      if (b.checked) n++;
    });
    shops.forEach(paint);
    sel.textContent = n === 0 ? 'Отметьте магазины в списке или на карте'
      : 'Выбрано: ' + n + ' ' + (n % 10 === 1 && n % 100 !== 11 ? 'магазин' : n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? 'магазина' : 'магазинов');
  }
  form.addEventListener('change', function (e) {
    if (e.target.id === 'assign-all') {
      form.querySelectorAll('tr[data-id]').forEach(function (r) {
        if (!r.hidden) r.querySelector('input[name=ids]').checked = e.target.checked;
      });
    }
    update();
  });
  update();
})();
