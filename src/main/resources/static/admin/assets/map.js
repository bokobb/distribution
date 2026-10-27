// Карта «Дистрибуция»: магазины цветом их торгового, пути людей за день в порядке времени отметок.
// Данные — JSON из data-src (/admin/map/data с теми же условиями, что у страницы).
(function () {
  var el = document.getElementById('map');
  if (!el || !window.L) return;

  var KIND = {
    ORDER: 'визит, заказ', NO_ORDER: 'визит без заказа',
    DELIVERED: 'выдано', PARTIAL: 'выдано частично', REFUSED: 'отказ магазина'
  };
  var ROLE = { AGENT: 'торговый', EXPEDITOR: 'экспедитор' };

  var map = L.map(el, { scrollWheelZoom: true });
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">участники OpenStreetMap</a>'
  }).addTo(map);
  var shopLayer = L.layerGroup().addTo(map);
  var pathLayer = L.layerGroup().addTo(map);
  var groups = {};

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function draw(d) {
    map.setView(d.center, 12);
    var all = [];

    d.outlets.forEach(function (s) {
      L.circleMarker([s.lat, s.lng], { radius: 6, color: '#fff', weight: 1.5, fillColor: s.color, fillOpacity: 0.85 })
        .bindTooltip('<b>' + esc(s.name) + '</b><br>' + esc(s.address) + (s.route ? '<br>маршрут ' + esc(s.route) : ''))
        .addTo(shopLayer);
      all.push([s.lat, s.lng]);
    });

    var list = document.getElementById('map-people');
    d.people.forEach(function (p) {
      var g = L.featureGroup().addTo(pathLayer);
      groups[p.id] = g;
      var pts = p.stops.map(function (s) { return [s.lat, s.lng]; });
      if (pts.length > 1) {
        L.polyline(pts, { color: p.color, weight: 4, opacity: 0.8, dashArray: p.role === 'EXPEDITOR' ? '10 7' : null }).addTo(g);
      }
      p.stops.forEach(function (s, i) {
        var ok = s.kind === 'ORDER' || s.kind === 'DELIVERED' || s.kind === 'PARTIAL';
        L.marker([s.lat, s.lng], {
          icon: L.divIcon({
            className: 'map-n',
            html: '<span class="' + (ok ? '' : 'off') + '" style="--c:' + p.color + '">' + (i + 1) + '</span>',
            iconSize: [24, 24], iconAnchor: [12, 12]
          }),
          title: (i + 1) + '. ' + s.outlet
        }).bindPopup('<b>' + esc(s.time) + ' · ' + esc(s.outlet) + '</b><br>' + esc(p.name) + ', ' + esc(KIND[s.kind] || s.kind)
          + '<br>' + esc(s.note)).addTo(g);
        all.push([s.lat, s.lng]);
      });

      var li = document.createElement('li');
      li.innerHTML = '<label class="check"><input type="checkbox" checked aria-label="Показывать на карте"></label>'
        + '<button type="button" class="map-who"><i class="dot" style="background:' + p.color + '"></i>'
        + '<span><b>' + esc(p.name) + '</b><small>' + esc(ROLE[p.role] || '') + ' · ' + esc(p.summary) + '</small></span></button>';
      li.querySelector('input').addEventListener('change', function (e) {
        if (e.target.checked) g.addTo(pathLayer); else pathLayer.removeLayer(g);
      });
      li.querySelector('button').addEventListener('click', function () {
        if (!pathLayer.hasLayer(g)) { g.addTo(pathLayer); li.querySelector('input').checked = true; }
        if (pts.length) map.fitBounds(g.getBounds(), { padding: [40, 40], maxZoom: 16 });
      });
      list.appendChild(li);
    });

    document.getElementById('map-empty').hidden = d.people.length > 0;
    if (d.noCoords > 0) {
      var note = document.getElementById('map-note');
      note.hidden = false;
      note.textContent = 'Без координат магазинов: ' + d.noCoords + '. Их отметит агент при визите или можно указать в карточке магазина.';
    }
    if (all.length) map.fitBounds(all, { padding: [30, 30], maxZoom: 15 });
  }

  function toggle(id, layer) {
    var box = document.getElementById(id);
    if (box) box.addEventListener('change', function () {
      if (box.checked) layer.addTo(map); else map.removeLayer(layer);
    });
  }
  toggle('lay-shops', shopLayer);
  toggle('lay-paths', pathLayer);

  fetch(el.getAttribute('data-src'), { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(draw)
    .catch(function () {
      var note = document.getElementById('map-note');
      note.hidden = false;
      note.textContent = 'Не удалось загрузить данные карты — обновите страницу.';
    });
})();
