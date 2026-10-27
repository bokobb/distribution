// Карты «Дистрибуции» (Leaflet + OpenStreetMap). Раздел «Карта»: магазины цветом их торгового и пути
// людей за день — трек GPS (сплошная линия, точками — где пропал сигнал) или, без GPS, по прямой между
// отметками в порядке времени (пунктир). «Заказы»: по «На карте» — магазины найденных заказов цветом
// торгового или экспедитора. Данные — JSON из data-src с теми же условиями, что у страницы.
(function () {
  if (!window.L) return;

  var KIND = {
    ORDER: 'визит, заказ', NO_ORDER: 'визит без заказа',
    DELIVERED: 'выдано', PARTIAL: 'выдано частично', REFUSED: 'отказ магазина'
  };
  var ROLE = { AGENT: 'торговый', EXPEDITOR: 'экспедитор' };

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function money(n) {
    return Number(n).toLocaleString('ru-RU') + ' ₸';
  }

  function newMap(el) {
    var map = L.map(el, { scrollWheelZoom: true });
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">участники OpenStreetMap</a>'
    }).addTo(map);
    return map;
  }

  function load(el, draw, note) {
    fetch(el.getAttribute('data-src'), { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(draw)
      .catch(function () { note('Не удалось загрузить данные карты — обновите страницу.'); });
  }

  function noteIn(id) {
    return function (text) {
      var p = document.getElementById(id);
      if (!p) return;
      p.hidden = !text;
      p.textContent = text || '';
    };
  }

  // ---------------------------------------------------------------- раздел «Карта»
  (function () {
    var el = document.getElementById('map');
    if (!el) return;
    var map = newMap(el);
    var shopLayer = L.layerGroup().addTo(map);
    var pathLayer = L.layerGroup().addTo(map);
    var note = noteIn('map-note');

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
        var pts = p.stops.map(function (s) { return [s.lat, s.lng]; });
        if (p.track.length) {
          var tip = esc(p.name) + ' · трек GPS · ' + String(p.km).replace('.', ',') + ' км';
          p.track.forEach(function (seg, i) {
            if (i > 0) {
              var prev = p.track[i - 1];
              L.polyline([prev[prev.length - 1], seg[0]], { color: p.color, weight: 3, opacity: 0.7, dashArray: '1 8', lineCap: 'round' })
                .bindTooltip(esc(p.name) + ' · сигнала GPS не было больше 15 минут').addTo(g);
            }
            if (seg.length > 1) L.polyline(seg, { color: p.color, weight: 4, opacity: 0.85 }).bindTooltip(tip).addTo(g);
            else L.circleMarker(seg[0], { radius: 3, color: p.color, weight: 2, fillOpacity: 1 }).bindTooltip(tip).addTo(g);
            seg.forEach(function (x) { all.push(x); });
          });
        } else if (pts.length > 1) {
          L.polyline(pts, { color: p.color, weight: 3, opacity: 0.75, dashArray: '8 7' })
            .bindTooltip(esc(p.name) + ' · без GPS: по прямой между отметками').addTo(g);
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
          if (g.getLayers().length) map.fitBounds(g.getBounds(), { padding: [40, 40], maxZoom: 16 });
        });
        list.appendChild(li);
      });

      document.getElementById('map-empty').hidden = d.people.length > 0;
      if (d.noCoords > 0) note('Без координат магазинов: ' + d.noCoords + '. Их отметит агент при визите или можно указать в карточке магазина.');
      if (all.length) map.fitBounds(all, { padding: [30, 30], maxZoom: 15 });
    }

    [['lay-shops', shopLayer], ['lay-paths', pathLayer]].forEach(function (x) {
      var box = document.getElementById(x[0]);
      if (box) box.addEventListener('change', function () {
        if (box.checked) x[1].addTo(map); else map.removeLayer(x[1]);
      });
    });

    load(el, draw, note);
  })();

  // ---------------------------------------------------------------- «Заказы» → «На карте»
  (function () {
    var el = document.getElementById('orders-map');
    var box = el && el.closest('details');
    if (!box) return;
    var map, layer, data, mode = 'agent';
    var note = noteIn('orders-map-note');

    function paint() {
      if (!data) return;
      layer.clearLayers();
      data.points.forEach(function (o) {
        var color = mode === 'exp' ? o.expColor : o.agentColor;
        L.circleMarker([o.lat, o.lng], { radius: 7, color: '#fff', weight: 1.5, fillColor: color, fillOpacity: 0.9 })
          .bindTooltip('<b>' + esc(o.outlet) + '</b><br>№ ' + esc(o.number) + ' · ' + money(o.sum) + ' · ' + esc(o.status)
            + '<br>торговый: ' + esc(o.agent) + '<br>экспедитор: ' + esc(o.expeditor || 'ещё не отгружен'))
          .addTo(layer);
      });
      var legend = document.getElementById('orders-map-legend');
      legend.innerHTML = '';
      (mode === 'exp' ? data.expeditors : data.agents).forEach(function (l) {
        var li = document.createElement('li');
        li.innerHTML = '<i class="dot" style="background:' + l.color + '"></i><span>' + esc(l.name)
          + ' <small>' + l.count + ' · ' + money(l.sum) + '</small></span>';
        legend.appendChild(li);
      });
    }

    function draw(d) {
      data = d;
      map.setView(d.center, 12);
      paint();
      if (d.points.length) map.fitBounds(d.points.map(function (o) { return [o.lat, o.lng]; }), { padding: [30, 30], maxZoom: 15 });
      var text = [];
      if (!d.points.length) text.push('Нет заказов с координатами магазина.');
      if (d.noCoords > 0) text.push('Без координат магазина: ' + d.noCoords + ' заказ(ов) — их на карте нет.');
      if (d.cut) text.push('Показаны первые ' + d.points.length + ' заказов — сузьте условия.');
      note(text.join(' '));
    }

    box.addEventListener('toggle', function () {
      try { localStorage.setItem('orders-map-open', box.open ? '1' : ''); } catch (e) { /* без хранилища — просто не помним */ }
      if (!box.open) return;
      if (!map) {
        map = newMap(el);
        layer = L.layerGroup().addTo(map);
        load(el, draw, note);
      } else {
        map.invalidateSize();
      }
    });
    box.querySelectorAll('input[name="map-color"]').forEach(function (r) {
      r.addEventListener('change', function () { mode = r.value; paint(); });
    });
    // карту открывали — после смены условий списка она снова открыта
    try { if (localStorage.getItem('orders-map-open')) box.open = true; } catch (e) { /* нет хранилища */ }
  })();
})();
