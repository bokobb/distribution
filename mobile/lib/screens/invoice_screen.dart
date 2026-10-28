import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../invoice.dart';

/// Накладная на экране: посмотреть и «Поделиться» PDF (WhatsApp, Telegram, почта), если магазин попросит
/// электронную; печатают в офисе.
class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Накладная ${invoice.number}')),
        body: PdfPreview(
          build: (_) => invoice.pdf(),
          pdfFileName: invoice.fileName,
          initialPageFormat: PdfPageFormat.a4,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
        ),
      );
}
