import 'data/expeditor_data.dart';
import 'deliveries.dart';

/// Итог рейса для экспедитора — что сдавать вечером: наличные и Kaspi (за заказы и в счёт долгов), что ушло в долг
/// магазинам, возвраты негодного и невыданный товар. Считается как в кассе: то, что уже на сервере (данные
/// экспедитора), плюс то, что ещё на телефоне и в эти данные не попало, — без двойного счёта.
class TripSummary {
  TripSummary._(this.trip);

  factory TripSummary.of(TripInfo trip, DeliveryBook book, DateTime syncedAt) {
    final s = TripSummary._(trip)
      ..cash = trip.cash.cash
      ..kaspi = trip.cash.kaspi
      ..oldDebt = trip.cash.oldDebt
      ..returnsQty = trip.cash.returnsQty
      ..returnsTotal = trip.cash.returnsTotal;
    for (final stop in trip.stops) {
      final order = stop.order;
      final local = book.of(order.id);
      final ordered = order.lines.fold(0, (a, l) => a + l.qty);
      if (order.done) {
        // выдача уже на сервере — её деньги в trip.cash
        if (order.refused) {
          s.refused++;
          s.backQty += ordered;
        } else {
          if (order.status == 'PARTIAL') {
            s.partial++;
          } else {
            s.full++;
          }
          for (final l in order.lines) {
            final given = l.delivered ?? l.qty;
            s.deliveredTotal += given * l.price;
            s.backQty += l.qty - given;
          }
        }
      } else if (local != null && local.error == null) {
        if (!local.sent) s.unsent++;
        if (local.refused) {
          s.refused++;
          s.backQty += ordered;
        } else {
          if (local.partial) {
            s.partial++;
          } else {
            s.full++;
          }
          s.deliveredTotal += local.total;
          s.cash += local.cash;
          s.kaspi += local.kaspi;
          for (final l in order.lines) {
            s.backQty += l.qty - (local.items.isEmpty ? l.qty : local.items[l.productId] ?? 0);
          }
        }
      } else {
        s.left++;
        s.backQty += ordered;
      }
    }
    // оплаты долга и возвраты: на сервере их нет, пока не ушли или пока данные не обновились после отправки
    for (final p in book.paymentsIn(trip.id)) {
      if (!p.sent) s.unsent++;
      if (p.sent && !p.paidAt.isAfter(syncedAt)) continue;
      if (p.method == 'KASPI') {
        s.kaspi += p.amount;
      } else {
        s.cash += p.amount;
      }
      s.oldDebt += p.amount;
    }
    for (final r in book.returnsIn(trip.id)) {
      if (!r.sent) s.unsent++;
      if (r.sent && !r.returnedAt.isAfter(syncedAt)) continue;
      s.returnsQty += r.qty;
      s.returnsTotal += r.total;
    }
    return s;
  }

  final TripInfo trip;

  /// Точки: выдано целиком, частично, отказ, ещё не пройдено.
  int full = 0, partial = 0, refused = 0, left = 0;

  /// На сколько выдано товара.
  int deliveredTotal = 0;

  /// Получено — сдать в кассу наличными и сверить Kaspi; из них в счёт старых долгов.
  int cash = 0, kaspi = 0, oldDebt = 0;

  /// Возвраты негодного: штук и на сколько уменьшили долги.
  int returnsQty = 0, returnsTotal = 0;

  /// Невыданный товар в машине (не доехал, отказ, выдано не всё), штук.
  int backQty = 0;

  /// Записей рейса на телефоне ещё не ушло на сервер (в итоге учтены).
  int unsent = 0;

  int get done => full + partial + refused;

  /// Ушло в долг магазинам за выдачу: выдано минус оплачено за заказы.
  int get debt => deliveredTotal - (cash + kaspi - oldDebt);
}
