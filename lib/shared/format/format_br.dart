import 'package:intl/intl.dart';

class FormatBR {
  static String monthYear(DateTime d) {
    return DateFormat('MMMM yyyy', 'pt_BR').format(d);
  }

  static String date(DateTime d) {
    return DateFormat('dd/MM/yyyy', 'pt_BR').format(d);
  }

  static String money(double v) {
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return f.format(v);
  }
}
