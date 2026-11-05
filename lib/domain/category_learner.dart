// Suggests a category for a new expense from what was categorised before:
// a multinomial naive Bayes over words of the vendor/description, the
// amount's order of magnitude, the place and the consumption unit, plus a
// strong boost when the same vendor was seen with a similar amount
// (recurring bills). Seeded with keyword priors so it helps from day one.

import 'dart:math';

class ExpenseFeatures {
  final String vendor;
  final String description;
  final int amountCents;
  final String? building;
  final String? apartment;
  final String? unit;

  const ExpenseFeatures({
    this.vendor = '',
    this.description = '',
    this.amountCents = 0,
    this.building,
    this.apartment,
    this.unit,
  });

  List<String> tokens() => [
        ...wordsOf('$vendor $description').map((w) => 'w:$w'),
        if (amountCents > 0) 'a:${amountBucket(amountCents)}',
        if (building != null && building!.isNotEmpty) 'b:$building',
        if (apartment != null && apartment!.isNotEmpty) 'p:$apartment',
        if (unit != null && unit!.isNotEmpty) 'u:${unit!.toLowerCase()}',
      ];
}

/// Half-octave buckets of the amount in euros.
int amountBucket(int cents) => (log(cents / 100 + 1) / ln2 * 2).floor();

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n',
};

String normalize(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

List<String> wordsOf(String s) => normalize(s)
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.length >= 2 && !RegExp(r'^\d+$').hasMatch(w))
    .toList();

/// Keyword priors per default category key.
const categoryKeywords = <String, List<String>>{
  'water': ['agua', 'water', 'epal', 'aguas', 'saneamento', 'smas', 'indaqua'],
  'energy': ['edp', 'luz', 'eletricidade', 'electricidade', 'energia', 'energy', 'electricity', 'iberdrola', 'endesa', 'goldenergy', 'kwh'],
  'gas': ['gas', 'galp', 'butano', 'propano'],
  'internet': ['meo', 'nos', 'vodafone', 'nowo', 'digi', 'internet', 'fibra', 'wifi', 'router'],
  'condo': ['condominio', 'condo', 'administracao'],
  'material': ['leroy', 'merlin', 'aki', 'bricomarche', 'tinta', 'material', 'ferramenta', 'parafusos'],
  'repairs': ['canalizador', 'eletricista', 'reparacao', 'arranjo', 'repair', 'plumber'],
  'cleaning': ['limpeza', 'cleaning', 'detergente', 'lixivia'],
  'food': ['continente', 'pingo', 'doce', 'lidl', 'aldi', 'mercadona', 'minipreco', 'supermercado', 'restaurante', 'cafe'],
  'furniture': ['ikea', 'conforama', 'moveis', 'colchao', 'sofa', 'cama'],
  'insurance': ['seguro', 'seguros', 'fidelidade', 'tranquilidade', 'allianz', 'insurance'],
  'taxes': ['imi', 'irs', 'financas', 'imposto', 'taxa', 'at'],
};

class Suggestion {
  final String categoryId;
  final double score; // 0..1, relative confidence
  final bool recurring;
  Suggestion(this.categoryId, this.score, {this.recurring = false});
}

class CategoryLearner {
  final _docs = <String, int>{}; // category -> examples
  final _feat = <String, Map<String, double>>{}; // category -> token -> count
  final _total = <String, double>{}; // category -> token count
  final _vocab = <String>{};
  // vendor (normalised) -> list of (category, amount)
  final _byVendor = <String, List<(String, int)>>{};

  /// [categoryIdByKey] maps default keys to category ids (for the priors).
  CategoryLearner(Map<String, String> categoryIdByKey) {
    for (final e in categoryKeywords.entries) {
      final id = categoryIdByKey[e.key];
      if (id == null) continue;
      for (final w in e.value) {
        _add(id, 'w:$w', 0.5);
      }
      _total[id] = (_total[id] ?? 0);
    }
  }

  void _add(String cat, String tok, double n) {
    final m = _feat.putIfAbsent(cat, () => {});
    m[tok] = (m[tok] ?? 0) + n;
    _total[cat] = (_total[cat] ?? 0) + n;
    _vocab.add(tok);
  }

  /// Learns one categorised expense.
  void learn(ExpenseFeatures f, String categoryId) {
    _docs[categoryId] = (_docs[categoryId] ?? 0) + 1;
    for (final t in f.tokens()) {
      _add(categoryId, t, 1);
    }
    final v = normalize(f.vendor.trim());
    if (v.isNotEmpty) {
      _byVendor.putIfAbsent(v, () => []).add((categoryId, f.amountCents));
    }
  }

  int get examples => _docs.values.fold(0, (a, b) => a + b);

  /// Up to [n] categories, best first.
  List<Suggestion> suggest(ExpenseFeatures f, {int n = 3}) {
    final toks = f.tokens();
    if (toks.isEmpty) return const [];
    final cats = {..._feat.keys, ..._docs.keys};
    if (cats.isEmpty) return const [];
    final totalDocs = examples + cats.length;
    final v = _vocab.length + 1;
    final scores = <String, double>{};
    for (final c in cats) {
      var s = log(((_docs[c] ?? 0) + 1) / totalDocs);
      final m = _feat[c] ?? const {};
      final tot = _total[c] ?? 0;
      var known = false;
      for (final t in toks) {
        final cnt = m[t] ?? 0;
        if (cnt > 0 && t.startsWith('w:')) known = true;
        s += log((cnt + 0.1) / (tot + 0.1 * v));
      }
      if (known) s += 2; // a matching word is strong evidence
      scores[c] = s;
    }
    // Same vendor, similar amount: almost surely the same kind of bill.
    final recurringCats = <String>{};
    final vendor = normalize(f.vendor.trim());
    for (final (cat, amt) in _byVendor[vendor] ?? const <(String, int)>[]) {
      final similar = f.amountCents == 0 ||
          amt == 0 ||
          (f.amountCents - amt).abs() <= amt * 0.15;
      scores[cat] = (scores[cat] ?? -1e9) + (similar ? 25 : 8);
      if (similar) recurringCats.add(cat);
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first.value;
    final exps = [for (final e in ranked) exp(e.value - top)];
    final sum = exps.fold(0.0, (a, b) => a + b);
    // Without any word, vendor or place evidence there is nothing to say.
    final informative = toks.any((t) => !t.startsWith('a:'));
    if (!informative && examples < 5) return const [];
    return [
      for (var i = 0; i < ranked.length && i < n; i++)
        Suggestion(ranked[i].key, exps[i] / sum,
            recurring: recurringCats.contains(ranked[i].key)),
    ];
  }
}
