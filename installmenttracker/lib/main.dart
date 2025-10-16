import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  runApp(const InstallmentTrackerApp());
}

class InstallmentTrackerApp extends StatelessWidget {
  const InstallmentTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Installment Tracker & Share Splitter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E7490),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

const double kExpectedTotal = 27_500_000;

class Shareholder {
  Shareholder({required this.name, required this.percent, required this.color});
  String name;
  double percent;
  Color color;
}

class TransactionEntry {
  TransactionEntry({
    required this.date,
    required this.amount,
    this.note = '',
  });

  DateTime date;
  double amount;
  String note;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final currency = NumberFormat.currency(locale: 'en_PK', symbol: '₨', decimalDigits: 0);
  final dateFmt = DateFormat('yyyy-MM-dd');

  final List<Shareholder> shareholders = [
    Shareholder(name: 'Afrina Imran', percent: 26.66667, color: const Color(0xFF3B82F6)),
    Shareholder(name: 'Meraj Uddin', percent: 26.66667, color: const Color(0xFF10B981)),
    Shareholder(name: 'Muhammad Imran Abbas', percent: 26.66667, color: const Color(0xFFF59E0B)),
    Shareholder(name: 'Mr X', percent: 20.0, color: const Color(0xFFEF4444)),
  ];

  final List<TransactionEntry> entries = [];

  @override
  void initState() {
    super.initState();
    _loadTransactionsFromCsv();
  }

  Future<void> _loadTransactionsFromCsv() async {
    try {
      final dataDir = Directory('data');
      final csvFile = File('${dataDir.path}/transactions.csv');
      if (!csvFile.existsSync()) return;

      final content = await csvFile.readAsString(encoding: utf8);
      final rows = const CsvToListConverter(eol: '\n').convert(content, shouldParseNumbers: false);

      if (rows.isEmpty) return;

      final header = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
      if (header.length < 2 || header[0] != 'date' || header[1] != 'amount') return;

      final loaded = <TransactionEntry>[];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || row.every((c) => (c?.toString().trim().isEmpty ?? true))) continue;

        try {
          final date = DateTime.parse(row[0].toString().trim());
          final amount = double.parse(row[1].toString().trim());
          final note = (row.length >= 3) ? row[2].toString() : '';
          if (amount <= 0) continue;
          loaded.add(TransactionEntry(date: date, amount: amount, note: note));
        } catch (_) {}
      }

      if (loaded.isNotEmpty) {
        setState(() {
          entries
            ..addAll(loaded)
            ..sort((a, b) => a.date.compareTo(b.date));
        });
      }
    } catch (_) {}
  }

  Future<void> _saveTransactionsToCsv() async {
    try {
      final dataDir = Directory('data');
      if (!dataDir.existsSync()) {
        dataDir.createSync(recursive: true);
      }

      final rows = <List<dynamic>>[
        ['date', 'amount', 'note'],
        ...entries.map((e) => [e.date.toIso8601String(), e.amount.toStringAsFixed(2), e.note]),
      ];
      final csv = const ListToCsvConverter().convert(rows);

      final csvFile = File('${dataDir.path}/transactions.csv');
      await csvFile.writeAsString(csv, encoding: utf8);
    } catch (e) {
      _toast('Auto-save failed: $e', error: true);
    }
  }

  double get totalReceived => entries.fold<double>(0, (sum, e) => sum + e.amount);
  double get remainingTotal => (kExpectedTotal - totalReceived).clamp(0, double.infinity);

  double expectedFor(Shareholder s) => kExpectedTotal * (s.percent / 100);
  double receivedFor(Shareholder s) => totalReceived * (s.percent / 100);
  double remainingFor(Shareholder s) => (expectedFor(s) - receivedFor(s)).clamp(0, double.infinity);

  bool get sharesValid {
    final sum = shareholders.fold<double>(0, (a, s) => a + s.percent);
    return (sum - 100).abs() < 0.0001;
  }
Future<void> _addTransactionDialog() async {
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  DateTime date = DateTime.now();
  final formKey = GlobalKey<FormState>();

  // helper to compute human-friendly amount text
  String amountInWords(double? amt) {
    if (amt == null || amt <= 0) return '';
    int value = amt.floor();
    int mil = value ~/ 1000000;
    int remainAfterMil = value % 1000000;
    int lac = remainAfterMil ~/ 100000;
    int remainAfterLac = remainAfterMil % 100000;
    int thousand = remainAfterLac ~/ 1000;
    List<String> parts = [];
    if (mil > 0) parts.add("$mil mil");
    if (lac > 0) parts.add("$lac lac");
    if (thousand > 0) parts.add("$thousand thousand");
    return parts.join(' ');
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          final amtText = amountCtrl.text;
          final double? amt = double.tryParse(amtText.replaceAll(',', ''));
          String prefixText = amountInWords(amt);
          return AlertDialog(
            title: const Text('Add Transaction'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (text) {
                              setStateDialog(() {}); // refresh UI on change
                            },
                            decoration: InputDecoration(
                              labelText: 'Amount (PKR)',
                              hintText: 'e.g. 150000',
                              // using suffix to show the computed text
                              suffix: Text(prefixText),
                            ),
                            validator: (v) {
                              final d = double.tryParse(v?.replaceAll(',', '') ?? '');
                              if (d == null || d <= 0) return 'Enter a valid amount > 0';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => date = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                      date.hour,
                                      date.minute,
                                    ));
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Date'),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(dateFmt.format(date)),
                                  const Icon(Icons.calendar_today, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final amt = double.parse(amountCtrl.text.replaceAll(',', ''));
                  setState(() {
                    entries.add(TransactionEntry(
                        date: date, amount: amt, note: noteCtrl.text.trim()));
                    entries.sort((a, b) => a.date.compareTo(b.date));
                  });
                  _saveTransactionsToCsv();
                  Navigator.pop(ctx);
                  _toast('Transaction added.');
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );
}

  Future<void> _exportCsv() async {
    try {
      final rows = <List<dynamic>>[
        ['date', 'amount', 'note'],
        ...entries.map((e) => [e.date.toIso8601String(), e.amount.toStringAsFixed(2), e.note]),
      ];
      final csv = const ListToCsvConverter().convert(rows);

      final suggested = 'transactions-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Transactions CSV',
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return;

      await File(path).writeAsString(csv, encoding: utf8);
      _toast('Exported to: $path');
    } catch (e) {
      _toast('Export failed: $e', error: true);
    }
  }

  Future<void> _importCsv() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );
      if (res == null || res.files.single.path == null) return;

      final path = res.files.single.path!;
      final content = await File(path).readAsString(encoding: utf8);
      final rows = const CsvToListConverter(eol: '\n').convert(content, shouldParseNumbers: false);

      if (rows.isEmpty) {
        _toast('CSV is empty', error: true);
        return;
      }

      final header = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
      if (header.length < 2 || header[0] != 'date' || header[1] != 'amount') {
        _toast('Invalid CSV header. Expected: date,amount,note', error: true);
        return;
      }

      final imported = <TransactionEntry>[];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || row.every((c) => (c?.toString().trim().isEmpty ?? true))) continue;

        try {
          final date = DateTime.parse(row[0].toString().trim());
          final amount = double.parse(row[1].toString().trim());
          final note = (row.length >= 3) ? row[2].toString() : '';
          if (amount <= 0) continue;
          imported.add(TransactionEntry(date: date, amount: amount, note: note));
        } catch (_) {}
      }

      if (imported.isEmpty) {
        _toast('No valid rows found in CSV', error: true);
        return;
      }

      setState(() {
        entries
          ..addAll(imported)
          ..sort((a, b) => a.date.compareTo(b.date));
      });
      _saveTransactionsToCsv();
      _toast('Imported ${imported.length} transactions.');
    } catch (e) {
      _toast('Import failed: $e', error: true);
    }
  }

  void _deleteEntry(int index) {
    setState(() {
      entries.removeAt(index);
    });
    _saveTransactionsToCsv();
    _toast('Transaction deleted.');
  }

  void _showSplitDetails(TransactionEntry e) {
    final parts = shareholders
        .map((s) => _SharePart(shareholder: s, amount: e.amount * (s.percent / 100)))
        .toList();
    final totalParts = parts.fold<double>(0, (sum, p) => sum + p.amount);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            'Split for ${currency.format(e.amount)} on ${dateFmt.format(e.date)}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!sharesValid)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Warning: shares do not sum to 100%.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Shareholder')),
                      DataColumn(label: Text('Percent')),
                      DataColumn(label: Text('Amount (PKR)')),
                    ],
                    rows: parts
                        .map(
                          (p) => DataRow(
                            color: WidgetStateProperty.all(p.shareholder.color.withOpacity(0.1)),
                            cells: [
                              DataCell(Text(p.shareholder.name)),
                              DataCell(Text('${p.shareholder.percent.toStringAsFixed(2)}%')),
                              DataCell(Text(currency.format(p.amount))),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Sum: ${currency.format(totalParts)}',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        );
      },
    );
  }

  void _toast(String message, {bool error = false}) {
    final messenger = scaffoldMessengerKey.currentState ?? ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade600 : Colors.teal.shade600,
      ),
    );
  }

  Widget _summaryCard({required String label, required String value, Color? color, IconData? icon}) {
    return Card(
      elevation: 0,
      color: color?.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (icon != null)
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color?.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color ?? Colors.black87),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color ?? Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareholderCard(Shareholder s) {
    final exp = expectedFor(s);
    final rec = receivedFor(s);
    final rem = remainingFor(s);
    return Card(
      elevation: 0,
      color: s.color.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: s.color,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Share: ${s.percent.toStringAsFixed(2)}%'),
              const SizedBox(height: 6),
              Text('Expected: ${currency.format(exp)}'),
              Text('Received: ${currency.format(rec)}'),
              Text('Remaining: ${currency.format(rem)}'),
            ],
          ),
        ),
      ),
    );
  }

  // Widget _editShares() {
  //   final sumPercent = shareholders.fold<double>(0, (a, s) => a + s.percent).toStringAsFixed(2);
  //   return ExpansionTile(
  //     title: const Text('Edit Shareholders'),
  //     subtitle: Text('Sum must be 100%. Current: $sumPercent%'),
  //     childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  //     children: [
  //       Wrap(
  //         runSpacing: 12,
  //         spacing: 12,
  //         children: [
  //           for (var i = 0; i < shareholders.length; i++)
  //             _ShareEditor(
  //               key: ValueKey('share-$i'),
  //               initialName: shareholders[i].name,
  //               initialPercent: shareholders[i].percent,
  //               onChanged: (name, pct) {
  //                 setState(() {
  //                   shareholders[i].name = name;
  //                   if (pct != null && pct >= 0) shareholders[i].percent = pct;
  //                 });
  //               },
  //             ),
  //         ],
  //       ),
  //       const SizedBox(height: 8),
  //       Row(
  //         children: [
  //           if (!sharesValid)
  //             Text(
  //               'Shares must sum to 100%.',
  //               style: TextStyle(color: Theme.of(context).colorScheme.error),
  //             ),
  //           const Spacer(),
  //           TextButton(
  //             onPressed: () {
  //               setState(() {
  //                 shareholders[0].percent = 26.66667;
  //                 shareholders[1].percent = 26.66667;
  //                 shareholders[2].percent = 26.66667;
  //                 shareholders[3].percent = 20.0;
  //               });
  //             },
  //             child: const Text('Reset to Original'),
  //           ),
  //         ],
  //       ),
  //       const SizedBox(height: 8),
  //     ],
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final summary = [
      _summaryCard(
        label: 'Total Expected',
        value: currency.format(kExpectedTotal),
        color: Colors.blueGrey.shade900,
        icon: Icons.flag,
      ),
      _summaryCard(
        label: 'Total Received',
        value: currency.format(totalReceived),
        color: Colors.teal.shade700,
        icon: Icons.download_done,
      ),
      _summaryCard(
        label: 'Remaining',
        value: currency.format(remainingTotal),
        color: Colors.orange.shade800,
        icon: Icons.timelapse,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Installment Tracker & Share Splitter (PKR)'),
        actions: [
          IconButton(
            tooltip: 'Import CSV',
            onPressed: _importCsv,
            icon: const Icon(Icons.file_open),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
            icon: const Icon(Icons.save_alt),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTransactionDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Transaction'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: summary[0])),
                      Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: summary[1])),
                      Expanded(child: summary[2]),
                    ],
                  );
                }
                return Column(
                  children: summary
                      .map((w) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: w,
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 8),
            // _editShares(),
            const SizedBox(height: 12),

            Text('Shareholders', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final columns = c.maxWidth > 1100
                  ? 4
                  : c.maxWidth > 900
                      ? 3
                      : c.maxWidth > 650
                          ? 2
                          : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.8,
                children: shareholders.map(_shareholderCard).toList(),
              );
            }),
            const SizedBox(height: 20),

            Row(
              children: [
                Text('Transactions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _addTransactionDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _importCsv,
                  icon: const Icon(Icons.file_open),
                  label: const Text('Import CSV'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Export CSV'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Card(
              elevation: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Amount (PKR)')),
                    DataColumn(label: Text('Note')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (var i = 0; i < entries.length; i++)
                      DataRow(
                        cells: [
                          DataCell(Text(dateFmt.format(entries[i].date))),
                          DataCell(Text(currency.format(entries[i].amount))),
                          DataCell(Text(entries[i].note)),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'View Split',
                                  icon: const Icon(Icons.pie_chart_outline),
                                  onPressed: () => _showSplitDetails(entries[i]),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteEntry(i),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _ShareEditor extends StatefulWidget {
  const _ShareEditor({
    required this.initialName,
    required this.initialPercent,
    required this.onChanged,
  });

  final String initialName;
  final double initialPercent;
  final void Function(String name, double? percent) onChanged;

  @override
  _ShareEditorState createState() => _ShareEditorState();
}

class _ShareEditorState extends State<_ShareEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pctCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _pctCtrl = TextEditingController(text: widget.initialPercent.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pctCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (v) => widget.onChanged(v, null),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: TextField(
              controller: _pctCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Percent'),
              onChanged: (v) {
                final d = double.tryParse(v);
                if (d != null && d >= 0) {
                  widget.onChanged(_nameCtrl.text, d);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SharePart {
  _SharePart({required this.shareholder, required this.amount});
  final Shareholder shareholder;
  final double amount;
}
