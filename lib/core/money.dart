import 'package:intl/intl.dart';

/// Amounts are kept as integer cents everywhere.
String formatMoney(int cents, {String currency = 'EUR', String? locale}) {
  final f = NumberFormat.simpleCurrency(name: currency, locale: locale);
  return f.format(cents / 100);
}

/// Parses "12", "12.5", "12,50", "1.234,56", "1,234.56" into cents.
int? parseMoney(String input) {
  var s = input.trim().replaceAll(RegExp(r'[^\d,.\-]'), '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  final decimalSep = lastComma > lastDot ? ',' : '.';
  final thousandSep = decimalSep == ',' ? '.' : ',';
  s = s.replaceAll(thousandSep, '');
  if (decimalSep == ',') s = s.replaceAll(',', '.');
  final v = double.tryParse(s);
  if (v == null) return null;
  return (v * 100).round();
}

/// Cents to an editable string ("12.50").
String centsToInput(int? cents) =>
    cents == null ? '' : (cents / 100).toStringAsFixed(2);
