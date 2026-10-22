import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_components.dart';
import '../ui/ir_format.dart';
import '../ui/ir_page_body.dart';
import '../ui/ir_theme.dart';

class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(text: '50000');
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _transactions = [];
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.api.getDriverMe();
      if (mounted) {
        setState(() {
          _profile = profile;
          _error = null;
        });
      }
      try {
        final transactions = await widget.api.getDriverWalletTransactions();
        if (mounted) setState(() => _transactions = transactions);
      } on ApiException catch (error) {
        if (mounted) setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'No se pudo actualizar tu cartera. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _transactionDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return 'Fecha no disponible';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} · ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  String _transactionStatus(dynamic value) => const {
        'completed': 'Completado',
        'sandbox': 'Prueba de desarrollo',
        'pending': 'Pendiente',
        'failed': 'Fallido',
        'cancelled': 'Cancelado',
      }[value?.toString()] ?? 'Estado no disponible';

  Future<void> _recharge() async {
    if (_saving || _confirming || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final amount = int.parse(_amount.text.trim());
    setState(() => _confirming = true);
    try {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: const Text('Confirmar recarga'),
                  content:
                      Text('Vas a recargar ${irMoney(amount)} en tu cartera.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Confirmar'))
                  ]));
      if (confirmed != true || !mounted) return;
      setState(() => _saving = true);
      final result = await widget.api.driverWalletRecharge(amount);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['mode'] == 'sandbox'
                ? 'Recarga de prueba registrada: ${irMoney(amount)}.'
                : 'Recarga registrada: ${irMoney(amount)}.')));
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo registrar la recarga. Revisa la conexión e inténtalo de nuevo.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cartera')),
        body: IrEditorialBackdrop(
          child: IrPageBody(
            child: _loading
                ? const Center(
                    child: IrLoadingState(
                        label: 'Cargando tu cartera', compact: true))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                      children: [
                        const IrPageIntro(
                          title: 'Bolsa IR',
                          description:
                              'Controla el saldo disponible para seguir operando.',
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[
                          IrInlineMessage(
                              message: _error!, error: true, onRetry: _load),
                          const SizedBox(height: 20),
                        ],
                        if (_profile != null) ...[
                          if (_profile!['wallet_recharge_mode'] == 'sandbox') ...[
                            Text(
                              'Modo de prueba: esta recarga no procesa un pago real.',
                              style: TextStyle(color: context.irColors.muted),
                            ),
                            const SizedBox(height: 12),
                          ],
                          IrPanel(
                            accent: true,
                            padding: const EdgeInsets.all(22),
                            child: Column(children: [
                              _balance(
                                  'Saldo total', _profile!['wallet_balance']),
                              _balance('Reservado para viajes',
                                  _profile!['reserved_balance']),
                              Divider(
                                  color: IrPalette.ink.withValues(alpha: .18)),
                              _balance(
                                'Disponible',
                                _profile!['available_balance'] ??
                                    ((num.tryParse(_profile!['wallet_balance']
                                                .toString()) ??
                                            0) -
                                        (num.tryParse(
                                                _profile!['reserved_balance']
                                                    .toString()) ??
                                            0)),
                                prominent: true,
                              ),
                            ]),
                          ),
                          const SizedBox(height: 18),
                          if (_transactions.isNotEmpty) ...[
                            IrPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Movimientos recientes', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 10),
                                  ..._transactions.map((item) {
                                    final value = num.tryParse(item['amount'].toString()) ?? 0;
                                    final isRecharge = item['type'] == 'recharge';
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(isRecharge ? Icons.add_circle_outline : Icons.route_outlined, color: context.irColors.accent),
                                      title: Text(isRecharge ? 'Recarga' : 'Cargo de viaje'),
                                      subtitle: Text('${_transactionDate(item['created_at'])} · ${_transactionStatus(item['status'])}'),
                                      trailing: Text('${value < 0 ? '−' : '+'}${irMoney(value.abs())}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ] else ...[
                            IrPanel(
                              child: Text('Todavía no hay movimientos en tu cartera.', style: TextStyle(color: context.irColors.muted)),
                            ),
                            const SizedBox(height: 18),
                          ],
                          IrPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Recargar cartera',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -.5)),
                                if (_profile!['wallet_recharge_mode'] == 'unavailable') ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'Las recargas están temporalmente deshabilitadas. No se realizará ningún cargo ni cambio de saldo.',
                                    style: TextStyle(color: context.irColors.muted, height: 1.4),
                                  ),
                                ] else ...[
                                const SizedBox(height: 6),
                                Text('Define el monto antes de confirmarlo.',
                                    style: TextStyle(
                                        color: context.irColors.muted)),
                                const SizedBox(height: 20),
                                Form(
                                  key: _form,
                                  child: TextFormField(
                                    controller: _amount,
                                    enabled: !_saving,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _recharge(),
                                    decoration: const InputDecoration(
                                      labelText: 'Monto en COP',
                                      helperText: 'Mínimo COP 5.000',
                                      prefixIcon: Icon(Icons.payments_outlined),
                                    ),
                                    validator: (value) {
                                      final amount =
                                          int.tryParse(value?.trim() ?? '');
                                      if (amount == null || amount < 5000) {
                                        return 'Ingresa al menos COP 5.000.';
                                      }
                                      if (amount > 99999999) {
                                        return 'El monto supera el máximo permitido.';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 22),
                                FilledButton(
                                  onPressed:
                                      _saving || _confirming ? null : _recharge,
                                  child: _saving
                                      ? const SizedBox.square(
                                          dimension: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Text('Revisar recarga'),
                                ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      );

  Widget _balance(String label, dynamic amount, {bool prominent = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 24,
          runSpacing: 6,
          children: [
            Text(label,
                style: TextStyle(
                    color: IrPalette.ink.withValues(alpha: .68),
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            Text(irMoney(amount),
                style: TextStyle(
                    color: IrPalette.ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                    fontSize: prominent ? 24 : 18)),
          ],
        ),
      );
}
