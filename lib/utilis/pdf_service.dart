import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:my_business/database/database_helper.dart';

class PdfService {
  static String _formatPrice(dynamic value) =>
      NumberFormat.decimalPattern('fr_FR')
          .format((value as num?)?.toDouble() ?? 0.0);

  static Future<void> imprimerJournalVentes(List<Map<String, dynamic>> ventes, String titre) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Header(level: 0, child: pw.Text("Journal des Ventes - $titre")),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Client', 'Article', 'Qté', 'Total'],
            data: ventes.map((v) => [
              v['date_vente']?.toString().substring(0, 10) ?? '',
              v['nom_client'] ?? 'Client anonyme',
              v['nom_produit'] ?? '',
              v['quantite_vendue']?.toString() ?? '0',
              "${_formatPrice(v['prix_total'])} USD"
            ]).toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static Future<void> genererFacture(Map<String, dynamic> vente, {List<Map<String, dynamic>>? details}) async {
    final pdf = pw.Document();
    String nomDepot = "Ma Boutique";
    
    try {
      int? depotId = vente['depot_id'];
      if (depotId != null) {
        final db = await DatabaseHelper().database;
        List<Map<String, dynamic>> res = await db.query('depots', where: 'idDepot = ?', whereArgs: [depotId]);
        if (res.isNotEmpty) nomDepot = res.first['nomDepot'];
      }

      final List<Map<String, dynamic>> items = details ?? [vente];
      final double totalGeneral = items.fold(0.0, (sum, item) => sum + ((item['prix_total'] as num?)?.toDouble() ?? 0.0));

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a6,
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(child: pw.Text(nomDepot, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14))),
                pw.Center(child: pw.Text("Facture de Vente", style: const pw.TextStyle(fontSize: 10))),
                pw.Divider(),
                pw.Text("Date: ${vente['date_vente']?.toString().substring(0, 16).replaceAll('T', ' ') ?? ''}", style: const pw.TextStyle(fontSize: 8)),
                pw.Text("Client: ${vente['nom_client'] ?? 'Divers'}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  context: context,
                  data: items.map((item) => [item['nom_produit'], item['quantite_vendue'], _formatPrice(item['prix_total'])]).toList(),
                  headers: ['Art', 'Qté', 'Total'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                ),
                pw.Divider(),
                pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("TOTAL: ${_formatPrice(totalGeneral)} USD", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
              ],
            );
          },
        ),
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      rethrow;
    }
  }
}
