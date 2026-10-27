package com.confectionery.distribution.demo;

import java.util.Map;
import java.util.Random;

/**
 * Координаты демо-данных в Шымкенте: магазины маршрута стоят цепочкой от центра своего района, отметки
 * визитов и выдач — рядом с магазином. Одинаковые входные данные — одинаковые точки.
 */
final class DemoGeo {

    private static final double[] CITY = {42.3155, 69.5869};
    private static final Map<String, double[]> AREAS = Map.of(
            "Центр", new double[]{42.3175, 69.5960},
            "Север", new double[]{42.3520, 69.6010},
            "Восток", new double[]{42.3260, 69.6550},
            "Пригород", new double[]{42.2820, 69.5400},
            "Запад", new double[]{42.3140, 69.5300});

    private DemoGeo() {
    }

    /** Магазин pos-й по порядку на маршруте routeName («Центр-2») района region. */
    static double[] outlet(String region, String routeName, int pos, long seed) {
        double[] c = region == null ? CITY : AREAS.getOrDefault(region, CITY);
        Random r = new Random(seed);
        double dir = Math.toRadians(routeNo(routeName) * 75 + 20 + pos * 9);
        double dist = 500 + pos * 380;
        return shift(c, dist * Math.cos(dir) + jitter(r, 90), dist * Math.sin(dir) + jitter(r, 90));
    }

    /** Точка в meters от (lat, lng) в случайную сторону. */
    static double[] near(double lat, double lng, double meters, long seed) {
        double a = new Random(seed).nextDouble() * 2 * Math.PI;
        return shift(new double[]{lat, lng}, meters * Math.cos(a), meters * Math.sin(a));
    }

    private static int routeNo(String routeName) {
        int dash = routeName == null ? -1 : routeName.lastIndexOf('-');
        try {
            return dash < 0 ? 1 : Integer.parseInt(routeName.substring(dash + 1));
        } catch (NumberFormatException e) {
            return 1;
        }
    }

    private static double jitter(Random r, double meters) {
        return (r.nextDouble() * 2 - 1) * meters;
    }

    /** Сдвиг на north метров к северу и east — к востоку, с округлением до 6 знаков (~10 см). */
    private static double[] shift(double[] p, double north, double east) {
        double lat = p[0] + north / 111_320.0;
        double lng = p[1] + east / (111_320.0 * Math.cos(Math.toRadians(p[0])));
        return new double[]{Math.round(lat * 1e6) / 1e6, Math.round(lng * 1e6) / 1e6};
    }
}
